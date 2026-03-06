import { GradingResultEnvelope } from "./gradingRouter";

export type FeedbackNextAction = "retry" | "proceed" | "scaffold";

export type FeedbackMetadata = {
  message: string;
  hint_level: 0 | 1 | 2;
  remediation_tag: string;
  next_action: FeedbackNextAction;
};

type FeedbackContext = {
  conceptId: string;
  objectiveType: string;
  promptText: string;
  expectedAnswer: string;
  detectedAnswer: string | null;
  noAnswerLeakage: boolean;
};

type ObjectiveVocab = { targetType: string; boundedHints: [string, string]; reinforcement: string };

function extractVisualCueHints(promptText: string, objectiveHints: [string, string]): [string, string] {
  const normalized = promptText.toLowerCase();

  if (/(right[-\s]?angle|90\s*°|90\s*degrees?)/.test(normalized)) {
    return [
      "Hint 1: Look for the small square angle marker in the triangle.",
      "Hint 2: Choose the target touching that 90° marker."
    ];
  }

  if (/hypotenuse|opposite the right angle/.test(normalized)) {
    return [
      "Hint 1: Find the side opposite the right-angle marker.",
      "Hint 2: That opposite side is the hypotenuse."
    ];
  }

  if (/equation|pythag|a\^2|b\^2|c\^2/.test(normalized)) {
    return [
      "Hint 1: Keep the right-triangle relationship balanced on both sides.",
      "Hint 2: Check that squared terms match the relationship named in the prompt."
    ];
  }

  return objectiveHints;
}

export function buildStudentFeedback(
  envelope: GradingResultEnvelope,
  context: FeedbackContext,
  vocab: ObjectiveVocab
): FeedbackMetadata {
  const conceptLabel = context.conceptId.startsWith("tri.pyth") ? "Pythagoras" : "triangle";

  if (envelope.correctness === "correct") {
    return {
      message: `${vocab.reinforcement} ${conceptLabel === "Pythagoras" ? "That pattern helps when you solve missing-side problems." : "You used the prompt intent correctly."}`,
      hint_level: 0,
      remediation_tag: "reinforce_correct_concept",
      next_action: "proceed"
    };
  }

  if (envelope.correctness === "ambiguous") {
    return {
      message: `I detected an unclear ${vocab.targetType}. Please retry with one clear ${vocab.targetType} so I can grade it accurately.`,
      hint_level: 1,
      remediation_tag: "ambiguous_input_retry",
      next_action: "retry"
    };
  }

  if (envelope.feedback_message && envelope.feedback_message.trim().length > 0) {
    return {
      message: envelope.feedback_message.trim(),
      hint_level: 2,
      remediation_tag: "incorrect_with_contextual_feedback",
      next_action: envelope.correctness === "error" ? "scaffold" : "retry"
    };
  }

  const detected = context.detectedAnswer ?? "no clear answer";
  const hints = extractVisualCueHints(context.promptText, vocab.boundedHints);
  const mismatchText = `Nice try! You selected ${detected}, but that's not correct for this question.`;
  const answerLeak = context.noAnswerLeakage ? "" : ` The correct answer is ${context.expectedAnswer}.`;

  return {
    message: `${mismatchText} ${hints[0]} ${hints[1]}${answerLeak}`,
    hint_level: 2,
    remediation_tag: "incorrect_with_bounded_hints",
    next_action: envelope.correctness === "error" ? "scaffold" : "retry"
  };
}
