import { buildFeedbackMetadata, FeedbackPolicy } from "./feedbackEngine";
import { gradeWithRouter, GradingResultEnvelope, StrategyFamily } from "./gradingRouter";

type CaseLabel = "correct" | "incorrect" | "ambiguous" | "adversarial";
type FeedbackAssertion = "diagnosis_accuracy" | "context_cue_usage" | "progressive_hinting" | "no_direct_answer_leakage";
type DiagnosisExpectation = "wrong_target" | "type_mismatch" | "ambiguous_input" | "missing_input" | "partially_correct";

type BenchmarkCase = {
  id: string;
  conceptId: string;
  objectiveType: "identify" | "compute" | "select_equation";
  label: CaseLabel;
  expectedCorrectness: GradingResultEnvelope["correctness"];
  expectedStrategy: StrategyFamily;
  input: Parameters<typeof gradeWithRouter>[0];
  questionContext: {
    promptText: string;
    interactionType: string;
    expectedAnswer: string;
    expectedAnswerKind: string;
  };
  policy?: FeedbackPolicy;
  expectedDiagnosis: DiagnosisExpectation;
  expectedAssertions: FeedbackAssertion[];
};

type BenchmarkMetrics = {
  totalCases: number;
  accuracyByObjective: Record<string, { passed: number; total: number; accuracy: number }>;
  ambiguityFalsePositives: number;
  ambiguityFalseNegatives: number;
  feedbackQualityAssertions: Record<FeedbackAssertion, { hit: number; total: number }>;
  regressionAlerts: string[];
};

function keyForObjective(objectiveType: BenchmarkCase["objectiveType"]): string {
  return objectiveType;
}

function includesAny(text: string, needles: string[]): boolean {
  return needles.some((needle) => text.includes(needle));
}

function checkAssertion(
  assertion: FeedbackAssertion,
  envelope: GradingResultEnvelope,
  feedbackMessage: string,
  expectedDiagnosis: DiagnosisExpectation,
  expectedAnswer: string,
  actualDiagnosis: string
): boolean {
  const lower = feedbackMessage.toLowerCase();

  if (assertion === "diagnosis_accuracy") {
    return actualDiagnosis === expectedDiagnosis;
  }

  if (assertion === "context_cue_usage") {
    return includesAny(lower, ["prompt", "question", "labels", "marker", "relationship", "checklist"]);
  }

  if (assertion === "progressive_hinting") {
    return includesAny(lower, ["hint 1", "hint 2"])
      || (includesAny(lower, ["first", "next"]) && includesAny(lower, ["then", "after"]));
  }

  if (assertion === "no_direct_answer_leakage") {
    return !lower.includes(expectedAnswer.toLowerCase());
  }

  return envelope.correctness !== "error";
}

async function runCase(testCase: BenchmarkCase): Promise<{ pass: boolean; envelope: GradingResultEnvelope; assertionHits: Set<FeedbackAssertion>; alerts: string[] }> {
  const envelope = await gradeWithRouter(testCase.input);
  const alerts: string[] = [];

  if (envelope.strategy_family !== testCase.expectedStrategy) {
    alerts.push(`strategy_regression:${testCase.id}:expected=${testCase.expectedStrategy}:got=${envelope.strategy_family}`);
  }

  const detected = envelope.detected_answer.value == null ? null : String(envelope.detected_answer.value);
  const feedback = buildFeedbackMetadata(envelope, {
    promptText: testCase.questionContext.promptText,
    interactionType: testCase.questionContext.interactionType,
    objectiveType: testCase.objectiveType,
    expectedAnswer: testCase.questionContext.expectedAnswer,
    expectedAnswerKind: testCase.questionContext.expectedAnswerKind,
    detectedAnswer: detected,
    detectedAnswerKind: envelope.detected_answer.kind,
    feedbackPolicyId: testCase.policy?.reveal_policy ?? "benchmark_policy",
    noAnswerLeakage: true
  }, testCase.policy);

  const assertionHits = new Set<FeedbackAssertion>();
  for (const assertion of testCase.expectedAssertions) {
    if (checkAssertion(assertion, envelope, feedback.message, testCase.expectedDiagnosis, testCase.questionContext.expectedAnswer, feedback.diagnosis_category)) {
      assertionHits.add(assertion);
    }
  }

  const pass = envelope.correctness === testCase.expectedCorrectness;
  return { pass, envelope, assertionHits, alerts };
}

export async function runGradingBenchmark(cases: BenchmarkCase[]): Promise<BenchmarkMetrics> {
  const accuracy: BenchmarkMetrics["accuracyByObjective"] = {};
  let ambiguityFalsePositives = 0;
  let ambiguityFalseNegatives = 0;
  const feedbackQualityAssertions: BenchmarkMetrics["feedbackQualityAssertions"] = {
    diagnosis_accuracy: { hit: 0, total: 0 },
    context_cue_usage: { hit: 0, total: 0 },
    progressive_hinting: { hit: 0, total: 0 },
    no_direct_answer_leakage: { hit: 0, total: 0 }
  };
  const regressionAlerts: string[] = [];

  for (const testCase of cases) {
    const result = await runCase(testCase);
    const key = keyForObjective(testCase.objectiveType);
    accuracy[key] = accuracy[key] ?? { passed: 0, total: 0, accuracy: 0 };
    accuracy[key].total += 1;
    if (result.pass) accuracy[key].passed += 1;

    const predictedAmbiguous = result.envelope.correctness === "ambiguous";
    const expectedAmbiguous = testCase.expectedCorrectness === "ambiguous";
    if (predictedAmbiguous && !expectedAmbiguous) ambiguityFalsePositives += 1;
    if (!predictedAmbiguous && expectedAmbiguous) ambiguityFalseNegatives += 1;

    for (const assertion of testCase.expectedAssertions) {
      feedbackQualityAssertions[assertion].total += 1;
      if (result.assertionHits.has(assertion)) feedbackQualityAssertions[assertion].hit += 1;
    }

    regressionAlerts.push(...result.alerts);
  }

  for (const key of Object.keys(accuracy)) {
    const bucket = accuracy[key];
    bucket.accuracy = bucket.total === 0 ? 0 : bucket.passed / bucket.total;
  }

  return {
    totalCases: cases.length,
    accuracyByObjective: accuracy,
    ambiguityFalsePositives,
    ambiguityFalseNegatives,
    feedbackQualityAssertions,
    regressionAlerts
  };
}

export const benchmarkCases: BenchmarkCase[] = [
  {
    id: "identify-wrong-target",
    conceptId: "tri.structure.hypotenuse",
    objectiveType: "identify",
    label: "incorrect",
    expectedCorrectness: "incorrect",
    expectedStrategy: "deterministic_choice",
    input: {
      concept_id: "tri.structure.hypotenuse",
      grading_strategy_id: "deterministic_rule",
      answer_schema: "enum",
      expected_answer_kind: "option_id",
      expected_answer_value: "A",
      submitted_choice_id: "B"
    },
    questionContext: {
      promptText: "Identify the side opposite the right angle.",
      interactionType: "multiple_choice",
      expectedAnswer: "A",
      expectedAnswerKind: "option_id"
    },
    policy: { cue_types: ["prompt", "relationship"], reveal_policy: "no_direct_answer" },
    expectedDiagnosis: "wrong_target",
    expectedAssertions: ["diagnosis_accuracy", "context_cue_usage", "progressive_hinting", "no_direct_answer_leakage"]
  },
  {
    id: "compute-type-mismatch",
    conceptId: "tri.pyth.solve_missing_side",
    objectiveType: "compute",
    label: "incorrect",
    expectedCorrectness: "incorrect",
    expectedStrategy: "symbolic_equivalence",
    input: {
      concept_id: "tri.pyth.solve_missing_side",
      grading_strategy_id: "symbolic_equivalence",
      answer_schema: "expression_equivalence",
      expected_answer_kind: "number",
      expected_answer_value: "5",
      submitted_expression: "x=5"
    },
    questionContext: {
      promptText: "Compute the missing side length using a² + b² = c².",
      interactionType: "numeric_input",
      expectedAnswer: "5",
      expectedAnswerKind: "number"
    },
    policy: { cue_types: ["prompt", "format"], reveal_policy: "no_direct_answer" },
    expectedDiagnosis: "type_mismatch",
    expectedAssertions: ["diagnosis_accuracy", "context_cue_usage", "progressive_hinting", "no_direct_answer_leakage"]
  },
  {
    id: "select-equation-type-mismatch",
    conceptId: "tri.pyth.equation_a2_b2_c2",
    objectiveType: "select_equation",
    label: "incorrect",
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
    questionContext: {
      promptText: "Select the equation that correctly models a right triangle.",
      interactionType: "multiple_choice",
      expectedAnswer: "a^2+b^2=c^2",
      expectedAnswerKind: "expression"
    },
    policy: { cue_types: ["prompt", "format"], reveal_policy: "no_direct_answer" },
    expectedDiagnosis: "wrong_target",
    expectedAssertions: ["diagnosis_accuracy", "context_cue_usage", "progressive_hinting", "no_direct_answer_leakage"]
  }
];
