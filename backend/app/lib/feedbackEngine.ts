import { GradingResultEnvelope } from "./gradingRouter";

export type FeedbackNextAction = "retry" | "proceed" | "scaffold";

export type FeedbackMetadata = {
  message: string;
  hint_level: 0 | 1 | 2;
  remediation_tag: string;
  next_action: FeedbackNextAction;
};

export type FeedbackPolicy = {
  skill_focus?: string;
  cue_types?: string[];
  hint_templates?: string[];
  feedback_style?: string;
  reveal_policy?: string;
};

export type FeedbackQuestionContext = {
  objectiveType: string;
  expectedAnswer: string;
  detectedAnswer: string | null;
  noAnswerLeakage: boolean;
};

type ObjectiveVocabulary = {
  targetType: string;
  boundedHints: [string, string];
  reinforcement: string;
};

const OBJECTIVE_VOCAB: Record<string, ObjectiveVocabulary> = {
  vertex: {
    targetType: "vertex",
    boundedHints: ["Hint 1: Find a single corner point with a letter.", "Hint 2: Match the letter to the exact point the prompt names."],
    reinforcement: "Nice work spotting the right corner point in the triangle."
  },
  equation: {
    targetType: "equation",
    boundedHints: ["Hint 1: Keep both sides of the equation balanced.", "Hint 2: Check that the squared terms match the triangle relationship in the prompt."],
    reinforcement: "Great equation choice—this is the key pattern for right triangles."
  },
  number: {
    targetType: "number",
    boundedHints: ["Hint 1: Recheck your arithmetic step by step.", "Hint 2: Compare your result to the values shown in the prompt."],
    reinforcement: "Great computation—your number fits the triangle information."
  },
  segment: {
    targetType: "segment",
    boundedHints: ["Hint 1: Trace one side between two labeled points.", "Hint 2: Pick the side that matches the relationship named in the prompt."],
    reinforcement: "Great side identification—you linked the labels to the right segment."
  },
  angle: {
    targetType: "angle",
    boundedHints: ["Hint 1: Focus on the angle marker at one vertex.", "Hint 2: Use the three-letter angle name order carefully."],
    reinforcement: "Great angle reasoning—you connected the marker to the right angle name."
  },
  text: {
    targetType: "response",
    boundedHints: ["Hint 1: Use a short sentence with math words from the prompt.", "Hint 2: Name the key triangle relationship directly."],
    reinforcement: "Great explanation—you used triangle vocabulary clearly."
  }
};

function resolveObjectiveVocabulary(objectiveType: string, detectedKind: GradingResultEnvelope["detected_answer"]["kind"]) {
  const normalized = objectiveType.trim().toLowerCase();
  if (normalized.includes("vertex")) return OBJECTIVE_VOCAB.vertex;
  if (normalized.includes("equation") || normalized.includes("pyth")) return OBJECTIVE_VOCAB.equation;
  if (normalized.includes("number") || normalized.includes("numeric")) return OBJECTIVE_VOCAB.number;
  if (normalized.includes("angle")) return OBJECTIVE_VOCAB.angle;
  if (normalized.includes("side") || normalized.includes("segment") || normalized.includes("hypotenuse") || normalized.includes("leg")) return OBJECTIVE_VOCAB.segment;

  if (detectedKind === "expression") return OBJECTIVE_VOCAB.equation;
  if (detectedKind === "number") return OBJECTIVE_VOCAB.number;
  if (detectedKind === "segment") return OBJECTIVE_VOCAB.segment;
  if (detectedKind === "point_set") return OBJECTIVE_VOCAB.vertex;
  if (detectedKind === "option_id") return OBJECTIVE_VOCAB.segment;
  return OBJECTIVE_VOCAB.text;
}

function normalizeHintTemplates(policy: FeedbackPolicy | undefined, fallbackHints: [string, string]): [string, string] {
  const templates = policy?.hint_templates?.filter((value): value is string => typeof value === "string" && value.trim().length > 0) ?? [];
  if (templates.length < 2) return fallbackHints;
  return [`Hint 1: ${templates[0].trim()}.`, `Hint 2: ${templates[1].trim()}.`];
}

function shouldRevealAnswer(context: FeedbackQuestionContext, policy?: FeedbackPolicy): boolean {
  if (context.noAnswerLeakage) return false;
  const revealPolicy = policy?.reveal_policy?.toLowerCase() ?? "";
  if (!revealPolicy) return true;
  if (revealPolicy.includes("no_direct_answer")) return false;
  return true;
}

export function buildFeedbackMetadata(
  envelope: GradingResultEnvelope,
  context: FeedbackQuestionContext,
  policy?: FeedbackPolicy
): FeedbackMetadata {
  const vocab = resolveObjectiveVocabulary(context.objectiveType, envelope.detected_answer.kind);
  const hints = normalizeHintTemplates(policy, vocab.boundedHints);

  if (envelope.correctness === "correct") {
    return {
      message: `${vocab.reinforcement} You used the prompt intent correctly.`,
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

  const detected = context.detectedAnswer ?? "no clear answer";
  const mismatchText = `I detected ${detected}. The prompt asks for a ${vocab.targetType}, so this does not match the prompt intent.`;
  const answerLeak = shouldRevealAnswer(context, policy) ? ` The correct answer is ${context.expectedAnswer}.` : "";

  return {
    message: `${mismatchText} ${hints[0]} ${hints[1]}${answerLeak}`,
    hint_level: 2,
    remediation_tag: "incorrect_with_bounded_hints",
    next_action: envelope.correctness === "error" ? "scaffold" : "retry"
  };
}
