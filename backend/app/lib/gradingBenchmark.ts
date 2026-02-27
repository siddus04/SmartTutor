import { gradeWithRouter, GradingResultEnvelope, StrategyFamily } from "./gradingRouter";

type CaseLabel = "correct" | "incorrect" | "ambiguous" | "adversarial";
type FeedbackFlag = "contains_retry_guidance" | "contains_target_reference" | "contains_bounded_hint" | "contains_positive_reinforcement";

type BenchmarkCase = {
  id: string;
  conceptId: string;
  objectiveType: string;
  label: CaseLabel;
  expectedCorrectness: GradingResultEnvelope["correctness"];
  expectedStrategy: StrategyFamily;
  input: Parameters<typeof gradeWithRouter>[0];
  expectedFeedbackFlags: FeedbackFlag[];
};

type BenchmarkMetrics = {
  totalCases: number;
  accuracyByConceptObjective: Record<string, { passed: number; total: number; accuracy: number }>;
  ambiguityFalsePositives: number;
  ambiguityFalseNegatives: number;
  feedbackQualityFlags: Record<FeedbackFlag, { hit: number; total: number }>;
  regressionAlerts: string[];
};

function keyFor(conceptId: string, objectiveType: string): string {
  return `${conceptId}::${objectiveType}`;
}

function evaluateFeedbackFlags(envelope: GradingResultEnvelope): Set<FeedbackFlag> {
  const text = envelope.evidence_summary.toLowerCase();
  const flags = new Set<FeedbackFlag>();
  if (envelope.correctness === "ambiguous") flags.add("contains_retry_guidance");
  if (text.includes("submitted") || text.includes("detected")) flags.add("contains_target_reference");
  if (text.includes("tolerance") || text.includes("canonical")) flags.add("contains_bounded_hint");
  if (envelope.correctness === "correct") flags.add("contains_positive_reinforcement");
  return flags;
}

async function runCase(testCase: BenchmarkCase): Promise<{ pass: boolean; envelope: GradingResultEnvelope; feedbackHits: Set<FeedbackFlag>; alerts: string[] }> {
  const envelope = await gradeWithRouter(testCase.input);
  const feedbackHits = evaluateFeedbackFlags(envelope);
  const alerts: string[] = [];

  if (envelope.strategy_family !== testCase.expectedStrategy) {
    alerts.push(`strategy_regression:${testCase.id}:expected=${testCase.expectedStrategy}:got=${envelope.strategy_family}`);
  }

  const pass = envelope.correctness === testCase.expectedCorrectness;
  return { pass, envelope, feedbackHits, alerts };
}

export async function runGradingBenchmark(cases: BenchmarkCase[]): Promise<BenchmarkMetrics> {
  const accuracy: BenchmarkMetrics["accuracyByConceptObjective"] = {};
  let ambiguityFalsePositives = 0;
  let ambiguityFalseNegatives = 0;
  const feedbackQualityFlags: BenchmarkMetrics["feedbackQualityFlags"] = {
    contains_retry_guidance: { hit: 0, total: 0 },
    contains_target_reference: { hit: 0, total: 0 },
    contains_bounded_hint: { hit: 0, total: 0 },
    contains_positive_reinforcement: { hit: 0, total: 0 }
  };
  const regressionAlerts: string[] = [];

  for (const testCase of cases) {
    const result = await runCase(testCase);
    const k = keyFor(testCase.conceptId, testCase.objectiveType);
    accuracy[k] = accuracy[k] ?? { passed: 0, total: 0, accuracy: 0 };
    accuracy[k].total += 1;
    if (result.pass) accuracy[k].passed += 1;

    const predictedAmbiguous = result.envelope.correctness === "ambiguous";
    const expectedAmbiguous = testCase.expectedCorrectness === "ambiguous";
    if (predictedAmbiguous && !expectedAmbiguous) ambiguityFalsePositives += 1;
    if (!predictedAmbiguous && expectedAmbiguous) ambiguityFalseNegatives += 1;

    for (const flag of testCase.expectedFeedbackFlags) {
      feedbackQualityFlags[flag].total += 1;
      if (result.feedbackHits.has(flag)) feedbackQualityFlags[flag].hit += 1;
    }

    regressionAlerts.push(...result.alerts);
  }

  for (const k of Object.keys(accuracy)) {
    const bucket = accuracy[k];
    bucket.accuracy = bucket.total === 0 ? 0 : bucket.passed / bucket.total;
  }

  return {
    totalCases: cases.length,
    accuracyByConceptObjective: accuracy,
    ambiguityFalsePositives,
    ambiguityFalseNegatives,
    feedbackQualityFlags,
    regressionAlerts
  };
}

export const benchmarkCases: BenchmarkCase[] = [
  {
    id: "hypotenuse-correct-choice",
    conceptId: "tri.structure.hypotenuse",
    objectiveType: "identify_segment",
    label: "correct",
    expectedCorrectness: "correct",
    expectedStrategy: "deterministic_choice",
    input: {
      concept_id: "tri.structure.hypotenuse",
      grading_strategy_id: "deterministic_rule",
      answer_schema: "enum",
      expected_answer_kind: "option_id",
      expected_answer_value: "A",
      submitted_choice_id: "A"
    },
    expectedFeedbackFlags: ["contains_target_reference", "contains_positive_reinforcement"]
  },
  {
    id: "pyth-eqn-variant-correct",
    conceptId: "tri.pyth.equation_a2_b2_c2",
    objectiveType: "select_equation",
    label: "correct",
    expectedCorrectness: "correct",
    expectedStrategy: "symbolic_equivalence",
    input: {
      concept_id: "tri.pyth.equation_a2_b2_c2",
      grading_strategy_id: "symbolic_equivalence",
      answer_schema: "expression_equivalence",
      expected_answer_kind: "expression",
      expected_answer_value: "b^2+a^2=c^2",
      submitted_expression: "a^2 + b^2 = c^2"
    },
    expectedFeedbackFlags: ["contains_bounded_hint", "contains_positive_reinforcement"]
  },
  {
    id: "pyth-eqn-adversarial",
    conceptId: "tri.pyth.equation_a2_b2_c2",
    objectiveType: "select_equation",
    label: "adversarial",
    expectedCorrectness: "incorrect",
    expectedStrategy: "symbolic_equivalence",
    input: {
      concept_id: "tri.pyth.equation_a2_b2_c2",
      grading_strategy_id: "symbolic_equivalence",
      answer_schema: "expression_equivalence",
      expected_answer_kind: "expression",
      expected_answer_value: "a^2+b^2=c^2",
      submitted_expression: "a^2+b^2=c"
    },
    expectedFeedbackFlags: ["contains_bounded_hint"]
  },
  {
    id: "numeric-edge-correct-boundary",
    conceptId: "tri.pyth.solve_missing_side",
    objectiveType: "compute_value",
    label: "correct",
    expectedCorrectness: "correct",
    expectedStrategy: "numeric_rule",
    input: {
      concept_id: "tri.pyth.solve_missing_side",
      grading_strategy_id: "deterministic_rule",
      answer_schema: "numeric_with_tolerance",
      expected_answer_kind: "number",
      expected_answer_value: "5",
      submitted_numeric_value: "5.1",
      numeric_rule: { tolerance: 0.1 }
    },
    expectedFeedbackFlags: ["contains_bounded_hint", "contains_positive_reinforcement"]
  },
  {
    id: "numeric-edge-incorrect-boundary",
    conceptId: "tri.pyth.solve_missing_side",
    objectiveType: "compute_value",
    label: "incorrect",
    expectedCorrectness: "incorrect",
    expectedStrategy: "numeric_rule",
    input: {
      concept_id: "tri.pyth.solve_missing_side",
      grading_strategy_id: "deterministic_rule",
      answer_schema: "numeric_with_tolerance",
      expected_answer_kind: "number",
      expected_answer_value: "5",
      submitted_numeric_value: "5.11",
      numeric_rule: { tolerance: 0.1 }
    },
    expectedFeedbackFlags: ["contains_bounded_hint"]
  },
  {
    id: "visual-ambiguous-vertices",
    conceptId: "tri.basics.identify_right_angle",
    objectiveType: "identify_vertex",
    label: "ambiguous",
    expectedCorrectness: "ambiguous",
    expectedStrategy: "visual_target_locator",
    input: {
      concept_id: "tri.basics.identify_right_angle",
      grading_strategy_id: "vision_locator",
      answer_schema: "point_set",
      expected_answer_kind: "point_set",
      expected_answer_value: "C",
      visual_target_evaluator: async () => ({
        strategy_family: "visual_target_locator",
        detected_answer: { kind: "point_set", value: null },
        correctness: "ambiguous",
        confidence: 0.2,
        ambiguity_codes: ["NO_CLOSED_LOOP"],
        evidence_summary: "detected_target_class=vertices with ambiguous loop"
      })
    },
    expectedFeedbackFlags: ["contains_retry_guidance", "contains_target_reference"]
  },
  {
    id: "visual-incorrect-segment",
    conceptId: "tri.structure.hypotenuse",
    objectiveType: "identify_segment",
    label: "incorrect",
    expectedCorrectness: "incorrect",
    expectedStrategy: "visual_target_locator",
    input: {
      concept_id: "tri.structure.hypotenuse",
      grading_strategy_id: "vision_locator",
      answer_schema: "segment_set",
      expected_answer_kind: "segment",
      expected_answer_value: "AB",
      visual_target_evaluator: async () => ({
        strategy_family: "visual_target_locator",
        detected_answer: { kind: "segment", value: "CA" },
        correctness: "incorrect",
        confidence: 0.9,
        ambiguity_codes: [],
        evidence_summary: "detected_target_class=segments submitted=CA expected=AB"
      })
    },
    expectedFeedbackFlags: ["contains_target_reference"]
  }
];
