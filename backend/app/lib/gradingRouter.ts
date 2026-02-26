export type StrategyFamily =
  | "deterministic_choice"
  | "numeric_rule"
  | "symbolic_equivalence"
  | "visual_target_locator"
  | "rubric_llm";

export type TypedDetectedAnswer = {
  kind: "option_id" | "number" | "expression" | "segment" | "point_set" | "text" | "unknown";
  value: string | number | string[] | null;
  unit?: string;
};

export type GradingResultEnvelope = {
  strategy_family: StrategyFamily;
  detected_answer: TypedDetectedAnswer;
  correctness: "correct" | "incorrect" | "ambiguous" | "error";
  confidence: number;
  ambiguity_codes: string[];
  evidence_summary: string;
};

export type ConceptPolicy = {
  concept_id: string;
  acceptable_strategies: StrategyFamily[];
  fallback_order: StrategyFamily[];
};

export const conceptPolicyRegistry: Record<string, ConceptPolicy> = {
  "tri.pyth.equation_a2_b2_c2": {
    concept_id: "tri.pyth.equation_a2_b2_c2",
    acceptable_strategies: ["symbolic_equivalence", "deterministic_choice", "rubric_llm"],
    fallback_order: ["symbolic_equivalence", "deterministic_choice", "rubric_llm"]
  }
};

const DEFAULT_POLICY: ConceptPolicy = {
  concept_id: "*",
  acceptable_strategies: ["deterministic_choice", "numeric_rule", "visual_target_locator", "symbolic_equivalence", "rubric_llm"],
  fallback_order: ["deterministic_choice", "numeric_rule", "visual_target_locator", "symbolic_equivalence", "rubric_llm"]
};

export type GradeRouterInput = {
  concept_id: string;
  grading_strategy_id?: string | null;
  answer_schema?: string | null;
  expected_answer_value?: string | null;
  expected_answer_kind?: string | null;
  submitted_choice_id?: string | null;
  submitted_numeric_value?: string | null;
  submitted_expression?: string | null;
  submitted_text?: string | null;
  numeric_rule?: {
    tolerance?: number;
    min_value?: number;
    max_value?: number;
    unit?: string;
  };
  visual_target_evaluator?: () => Promise<GradingResultEnvelope>;
  rubric_evaluator?: () => Promise<GradingResultEnvelope>;
};

type InterpretedEvidence = {
  selected_option_id: string | null;
  parsed_number: number | null;
  parsed_equation: string;
  parsed_text: string;
};

type EvaluationContext = {
  input: GradeRouterInput;
  evidence: InterpretedEvidence;
};

function clampConfidence(value: number) {
  if (!Number.isFinite(value)) return 0;
  return Math.max(0, Math.min(1, value));
}

function normalizeChoiceId(value: string | null | undefined): string | null {
  if (!value) return null;
  const cleaned = value.trim();
  return cleaned.length > 0 ? cleaned : null;
}

function parseNumeric(value: string | null | undefined): number | null {
  if (!value) return null;
  const parsed = Number(value.trim());
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizeExpression(value: string | null | undefined): string {
  if (!value) return "";
  return value.toLowerCase().replace(/\s+/g, "").replace(/²/g, "^2");
}

function canonicalizeExpression(value: string | null | undefined): string {
  const normalized = normalizeExpression(value);
  if (!normalized.includes("=")) return normalized;
  const [left, right] = normalized.split("=");
  const canonicalSide = (side: string) => side.split("+").map((term) => term.trim()).filter(Boolean).sort().join("+");
  return `${canonicalSide(left)}=${canonicalSide(right)}`;
}

function interpretEvidence(input: GradeRouterInput): InterpretedEvidence {
  return {
    selected_option_id: normalizeChoiceId(input.submitted_choice_id),
    parsed_number: parseNumeric(input.submitted_numeric_value),
    parsed_equation: input.submitted_expression?.trim() ?? "",
    parsed_text: input.submitted_text?.trim() ?? ""
  };
}

function mapToStrategyFamily(gradingStrategyId?: string | null, answerSchema?: string | null): StrategyFamily {
  const strategy = gradingStrategyId?.trim().toLowerCase();
  const schema = answerSchema?.trim().toLowerCase();

  if (strategy === "deterministic_choice") return "deterministic_choice";
  if (strategy === "numeric_rule") return "numeric_rule";
  if (strategy === "symbolic_equivalence") return "symbolic_equivalence";
  if (strategy === "visual_target_locator") return "visual_target_locator";
  if (strategy === "rubric_llm") return "rubric_llm";

  if (strategy === "deterministic_rule" && schema === "enum") return "deterministic_choice";
  if (strategy === "deterministic_rule" && schema === "numeric_with_tolerance") return "numeric_rule";
  if (strategy === "vision_locator" || strategy === "hybrid") return "visual_target_locator";

  if (schema === "enum") return "deterministic_choice";
  if (schema === "numeric_with_tolerance") return "numeric_rule";
  if (schema === "expression_equivalence") return "symbolic_equivalence";
  if (schema === "segment_set" || schema === "point_set") return "visual_target_locator";

  return "rubric_llm";
}

function evaluateDeterministicChoice(context: EvaluationContext): GradingResultEnvelope {
  const expected = normalizeChoiceId(context.input.expected_answer_value);
  const submitted = context.evidence.selected_option_id;

  if (!submitted) {
    return {
      strategy_family: "deterministic_choice",
      detected_answer: { kind: "option_id", value: null },
      correctness: "ambiguous",
      confidence: 0,
      ambiguity_codes: ["NO_CHOICE_SUBMITTED"],
      evidence_summary: "No option id was submitted for deterministic choice grading."
    };
  }

  const isCorrect = expected != null && submitted === expected;
  return {
    strategy_family: "deterministic_choice",
    detected_answer: { kind: "option_id", value: submitted },
    correctness: isCorrect ? "correct" : "incorrect",
    confidence: 1,
    ambiguity_codes: [],
    evidence_summary: isCorrect
      ? `Submitted option '${submitted}' matched expected option '${expected}'.`
      : `Submitted option '${submitted}' did not match expected option '${expected ?? "null"}'.`
  };
}

function evaluateNumericRule(context: EvaluationContext): GradingResultEnvelope {
  const submitted = context.evidence.parsed_number;
  const expected = parseNumeric(context.input.expected_answer_value);

  if (submitted == null) {
    return {
      strategy_family: "numeric_rule",
      detected_answer: { kind: "number", value: null, unit: context.input.numeric_rule?.unit },
      correctness: "ambiguous",
      confidence: 0,
      ambiguity_codes: ["INVALID_NUMERIC_INPUT"],
      evidence_summary: "Submitted value is missing or not parseable as a number."
    };
  }

  if (expected == null) {
    return {
      strategy_family: "numeric_rule",
      detected_answer: { kind: "number", value: submitted, unit: context.input.numeric_rule?.unit },
      correctness: "error",
      confidence: 0,
      ambiguity_codes: ["MISSING_EXPECTED_NUMERIC_RULE"],
      evidence_summary: "Expected numeric answer is missing or invalid in assessment contract."
    };
  }

  const tolerance = Math.abs(context.input.numeric_rule?.tolerance ?? 0);
  const inRange = (context.input.numeric_rule?.min_value == null || submitted >= context.input.numeric_rule.min_value)
    && (context.input.numeric_rule?.max_value == null || submitted <= context.input.numeric_rule.max_value);
  const delta = Math.abs(submitted - expected);
  const correctByTolerance = delta <= tolerance;
  const isCorrect = inRange && correctByTolerance;

  return {
    strategy_family: "numeric_rule",
    detected_answer: { kind: "number", value: submitted, unit: context.input.numeric_rule?.unit },
    correctness: isCorrect ? "correct" : "incorrect",
    confidence: 1,
    ambiguity_codes: inRange ? [] : ["NUMERIC_OUTSIDE_ALLOWED_RANGE"],
    evidence_summary: `submitted=${submitted}, expected=${expected}, tolerance=±${tolerance}, in_range=${inRange}, |delta|=${delta}.`
  };
}

function evaluateSymbolicEquivalence(context: EvaluationContext): GradingResultEnvelope {
  const submitted = context.evidence.parsed_equation;
  const expected = context.input.expected_answer_value?.trim() ?? "";
  if (!submitted) {
    return {
      strategy_family: "symbolic_equivalence",
      detected_answer: { kind: "expression", value: null },
      correctness: "ambiguous",
      confidence: 0,
      ambiguity_codes: ["MISSING_SYMBOLIC_INPUT"],
      evidence_summary: "No symbolic expression was submitted."
    };
  }

  const canonicalSubmitted = canonicalizeExpression(submitted);
  const canonicalExpected = canonicalizeExpression(expected);
  const isEquivalent = canonicalSubmitted.length > 0 && canonicalSubmitted === canonicalExpected;

  return {
    strategy_family: "symbolic_equivalence",
    detected_answer: { kind: "expression", value: submitted },
    correctness: isEquivalent ? "correct" : "incorrect",
    confidence: isEquivalent ? 0.95 : 0.75,
    ambiguity_codes: [],
    evidence_summary: `Canonical comparison used. submitted='${canonicalSubmitted}' expected='${canonicalExpected}'.`
  };
}

function getPolicy(conceptId: string): ConceptPolicy {
  return conceptPolicyRegistry[conceptId] ?? DEFAULT_POLICY;
}

export async function gradeWithRouter(input: GradeRouterInput): Promise<GradingResultEnvelope> {
  const evidence = interpretEvidence(input);
  const inferred = mapToStrategyFamily(input.grading_strategy_id, input.answer_schema);
  const policy = getPolicy(input.concept_id);
  const candidateOrder = [inferred, ...policy.fallback_order.filter((strategy) => strategy !== inferred)];

  for (const strategy of candidateOrder) {
    if (!policy.acceptable_strategies.includes(strategy)) continue;

    const context: EvaluationContext = { input, evidence };
    if (strategy === "deterministic_choice") return evaluateDeterministicChoice(context);
    if (strategy === "numeric_rule") return evaluateNumericRule(context);
    if (strategy === "symbolic_equivalence") return evaluateSymbolicEquivalence(context);
    if (strategy === "visual_target_locator" && input.visual_target_evaluator) return input.visual_target_evaluator();
    if (strategy === "rubric_llm" && input.rubric_evaluator) return input.rubric_evaluator();
  }

  return {
    strategy_family: inferred,
    detected_answer: { kind: input.expected_answer_kind === "number" ? "number" : "unknown", value: null },
    correctness: "error",
    confidence: clampConfidence(0),
    ambiguity_codes: ["NO_AVAILABLE_STRATEGY"],
    evidence_summary: `No usable strategy for inferred='${inferred}' and concept='${input.concept_id}'.`
  };
}
