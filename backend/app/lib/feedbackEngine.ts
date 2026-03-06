import { GradingResultEnvelope } from "./gradingRouter";

export type FeedbackNextAction = "retry" | "proceed" | "scaffold";

export type FeedbackMetadata = {
  message: string;
  hint_level: 0 | 1 | 2;
  remediation_tag: string;
  next_action: FeedbackNextAction;
  diagnosis_category: FeedbackDiagnosisCategory;
};

export type FeedbackDiagnosisCategory =
  | "wrong_target"
  | "type_mismatch"
  | "ambiguous_input"
  | "missing_input"
  | "partially_correct";

export type FeedbackPolicy = {
  skill_focus?: string;
  cue_types?: string[];
  hint_templates?: string[];
  feedback_style?: string;
  reveal_policy?: string;
};

export type FeedbackQuestionContext = {
  promptText: string;
  interactionType: string;
  objectiveType: string;
  expectedAnswer: string;
  expectedAnswerKind?: string | null;
  detectedAnswer: string | null;
  detectedAnswerKind?: string | null;
  explanationText?: string | null;
  diagramMetadata?: Record<string, unknown> | null;
  feedbackPolicyId?: string;
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
  if (revealPolicy.includes("allow_direct_answer")) return true;
  if (revealPolicy.includes("no_direct_answer")) return false;
  return true;
}

function resolveExpectedKind(context: FeedbackQuestionContext): string {
  const explicitKind = context.expectedAnswerKind?.trim().toLowerCase();
  if (explicitKind) return explicitKind;

  const objective = context.objectiveType.trim().toLowerCase();
  if (objective.includes("numeric") || objective.includes("number")) return "number";
  if (objective.includes("equation") || objective.includes("expression") || objective.includes("pyth")) return "expression";
  if (objective.includes("vertex") || objective.includes("point")) return "point_set";
  if (objective.includes("option") || objective.includes("mcq") || objective.includes("choice")) return "option_id";
  if (objective.includes("side") || objective.includes("segment") || objective.includes("hypotenuse") || objective.includes("leg")) return "segment";
  if (objective.includes("text") || objective.includes("explain")) return "text";
  return "unknown";
}

function normalizeDetectedKind(context: FeedbackQuestionContext, envelope: GradingResultEnvelope): string {
  const detected = context.detectedAnswerKind?.trim().toLowerCase();
  if (detected) return detected;
  return envelope.detected_answer.kind?.toLowerCase() ?? "unknown";
}

function classifyRelationship(expected: string | null, detected: string | null): "match" | "mismatch" | "missing" {
  const expectedValue = expected?.trim().toLowerCase() ?? "";
  const detectedValue = detected?.trim().toLowerCase() ?? "";
  if (!detectedValue) return "missing";
  if (expectedValue && expectedValue === detectedValue) return "match";
  return "mismatch";
}

function diagnose(envelope: GradingResultEnvelope, context: FeedbackQuestionContext): FeedbackDiagnosisCategory {
  const relationship = classifyRelationship(context.expectedAnswer, context.detectedAnswer);
  const expectedKind = resolveExpectedKind(context);
  const detectedKind = normalizeDetectedKind(context, envelope);

  if (envelope.correctness === "ambiguous") return "ambiguous_input";
  if (!context.expectedAnswer?.trim()) return "missing_input";
  if (relationship === "missing") return "missing_input";

  if (expectedKind !== "unknown" && detectedKind !== "unknown" && expectedKind !== detectedKind) {
    return "type_mismatch";
  }

  if (envelope.correctness === "correct") {
    return "partially_correct";
  }

  const ambiguitySignals = envelope.ambiguity_codes.map((code) => code.toLowerCase());
  if (ambiguitySignals.some((code) => code.includes("partial") || code.includes("close") || code.includes("almost"))) {
    return "partially_correct";
  }

  return "wrong_target";
}

function resolveCueSnippet(cueType: string, artifacts: {
  promptText: string;
  explanationText: string;
  diagramMetadata: string;
  detectedTarget: string;
  interactionType: string;
  relationship: "match" | "mismatch" | "missing";
}): string {
  const cue = cueType.trim().toLowerCase();
  if (cue === "prompt") {
    return artifacts.promptText
      ? `Use the prompt wording as your checklist: "${artifacts.promptText}".`
      : "Use the prompt wording as your checklist before submitting.";
  }
  if (cue === "explanation") {
    return artifacts.explanationText
      ? `Anchor your next attempt to this explanation clue: ${artifacts.explanationText}.`
      : "Anchor your next attempt to the explanation clue shown in the task.";
  }
  if (cue === "diagram") {
    return artifacts.diagramMetadata
      ? `Use visible diagram labels/markers (${artifacts.diagramMetadata}) to verify the target.`
      : "Use visible diagram labels and markers to verify the target before submitting.";
  }
  if (cue === "detected_target") {
    return artifacts.detectedTarget
      ? `Your last attempt focused on "${artifacts.detectedTarget}"; now align it with the asked target.`
      : "Compare your last attempt with the exact target the question asks for.";
  }
  if (cue === "clarify") {
    return "Submit one clear, unambiguous answer in the expected format.";
  }
  if (cue === "format") {
    return `Match the required ${artifacts.interactionType || "response"} format exactly.`;
  }
  if (cue === "relationship") {
    return artifacts.relationship === "missing"
      ? "I could not detect a gradeable target yet—choose one specific target and resubmit."
      : "Double-check whether your selected target matches the relationship asked in the question.";
  }

  return "Re-read the question and submit one target that directly matches it.";
}

function compose(
  diagnosis: FeedbackDiagnosisCategory,
  envelope: GradingResultEnvelope,
  context: FeedbackQuestionContext,
  policy: FeedbackPolicy | undefined,
  hints: [string, string],
  vocab: ObjectiveVocabulary
): FeedbackMetadata {
  const relationship = classifyRelationship(context.expectedAnswer, context.detectedAnswer);
  const artifacts = {
    promptText: context.promptText?.trim() ?? "",
    explanationText: context.explanationText?.trim() ?? "",
    diagramMetadata: context.diagramMetadata ? JSON.stringify(context.diagramMetadata) : "",
    detectedTarget: context.detectedAnswer?.trim() ?? "",
    interactionType: context.interactionType?.trim() ?? "",
    relationship
  };

  const cueTypes = policy?.cue_types?.filter((cue): cue is string => typeof cue === "string" && cue.trim().length > 0) ?? [];
  const resolvedCues = cueTypes.slice(0, 3).map((cue) => resolveCueSnippet(cue, artifacts));
  const cueFallback = [hints[0], hints[1]];
  const cueSequence = (resolvedCues.length > 0 ? resolvedCues : cueFallback).join(" ");
  const answerLeak = shouldRevealAnswer(context, policy) ? ` The expected answer is ${context.expectedAnswer}.` : "";

  if (envelope.correctness === "correct") {
    return {
      message: `${vocab.reinforcement} You aligned with the prompt target.`,
      hint_level: 0,
      remediation_tag: "reinforce_correct_concept",
      next_action: "proceed",
      diagnosis_category: diagnosis
    };
  }

  if (diagnosis === "ambiguous_input") {
    return {
      message: `Nice effort. I need one clear ${vocab.targetType} to grade this accurately. ${resolveCueSnippet("clarify", artifacts)} ${cueSequence}`,
      hint_level: 1,
      remediation_tag: "ambiguous_input_retry",
      next_action: "retry",
      diagnosis_category: diagnosis
    };
  }

  if (diagnosis === "type_mismatch") {
    return {
      message: `Good attempt. Your response type doesn't match the requested ${vocab.targetType}. ${resolveCueSnippet("format", artifacts)} ${cueSequence}${answerLeak}`,
      hint_level: 2,
      remediation_tag: "type_mismatch_retry",
      next_action: "scaffold",
      diagnosis_category: diagnosis
    };
  }

  if (diagnosis === "missing_input") {
    return {
      message: `You're close—no gradeable target was detected yet. ${resolveCueSnippet("clarify", artifacts)} ${cueSequence}`,
      hint_level: 1,
      remediation_tag: "missing_input_retry",
      next_action: "retry",
      diagnosis_category: diagnosis
    };
  }

  if (diagnosis === "partially_correct") {
    return {
      message: `Good progress. You are partially aligned but need a more precise ${vocab.targetType}. ${cueSequence}${answerLeak}`,
      hint_level: 1,
      remediation_tag: "partial_alignment_refine",
      next_action: "retry",
      diagnosis_category: diagnosis
    };
  }

  return {
    message: `Nice try. I detected ${context.detectedAnswer ?? "no clear target"}, but it does not match what is asked. ${cueSequence}${answerLeak}`,
    hint_level: 2,
    remediation_tag: "incorrect_with_bounded_hints",
    next_action: envelope.correctness === "error" ? "scaffold" : "retry",
    diagnosis_category: diagnosis
  };
}

export function buildFeedbackMetadata(
  envelope: GradingResultEnvelope,
  context: FeedbackQuestionContext,
  policy?: FeedbackPolicy
): FeedbackMetadata {
  const vocab = resolveObjectiveVocabulary(context.objectiveType, envelope.detected_answer.kind);
  const hints = normalizeHintTemplates(policy, vocab.boundedHints);
  const diagnosis = diagnose(envelope, context);
  return compose(diagnosis, envelope, context, policy, hints, vocab);
}
