import OpenAI from "openai";
import { createHash } from "crypto";

export type QuestionSpec = {
  schema_version: "m3.question_spec.v2";
  question_id: string;
  concept_id: string;
  grade: number;
  interaction_type: "highlight" | "multiple_choice" | "numeric_input";
  difficulty_metadata: { generator_self_rating: number };
  diagram_spec: {
    type: "triangle";
    points_normalized: Array<{ id: "A" | "B" | "C"; x: number; y: number }>;
    right_angle_at?: "A" | "B" | "C" | null;
  };
  prompt: string;
  response_contract: {
    mode: "highlight" | "multiple_choice" | "numeric_input";
    answer: { kind: string; value: string };
    options?: Array<{ id: string; text: string }>;
    numeric_rule?: { tolerance?: number };
  };
  hint: string;
  explanation: string;
  real_world_connection: string;
};

export type DifficultyRating = {
  schema_version: "m3.difficulty_rating.v1";
  overall: number;
  dimensions: { visual: number; language: number; reasoning_steps: number; numeric: number };
  grade_fit: { ok: boolean; notes: string };
  flags: {
    contains_trig: boolean;
    contains_formal_proof: boolean;
    contains_surd_or_irrational_root: boolean;
    out_of_ontology: boolean;
    non_renderable_diagram: boolean;
    interaction_answer_mismatch: boolean;
  };
};

export type LearnerContext = {
  recentConceptIds: string[];
  recentPromptHashes: string[];
  recentInteractionTypes: string[];
  recentExpectedAnswers: string[];
};

export type NoveltyConfig = {
  promptHashWindow: number;
  expectedAnswerRepeatLimit: number;
};

const DEFAULT_NOVELTY_CONFIG: NoveltyConfig = {
  promptHashWindow: 3,
  expectedAnswerRepeatLimit: 2
};

const ontology = new Set([
  "tri.basics.identify_right_angle","tri.basics.identify_right_triangle","tri.basics.vertices_sides_angles",
  "tri.structure.hypotenuse","tri.structure.legs","tri.structure.opposite_adjacent_relative",
  "tri.reasoning.compare_side_lengths","tri.reasoning.hypotenuse_longest","tri.reasoning.informal_side_relationships",
  "tri.pyth.check_if_right_triangle","tri.pyth.equation_a2_b2_c2","tri.pyth.solve_missing_side","tri.pyth.square_area_intuition","tri.pyth.square_numbers_refresher",
  "tri.app.mixed_mastery_test","tri.app.real_life_modeling","tri.app.word_problems"
]);

export function validateQuestionSpec(spec: QuestionSpec, allowedInteractionTypes: string[]): string[] {
  const errors: string[] = [];
  if (spec.schema_version !== "m3.question_spec.v2") errors.push("schema");
  if (spec.grade !== 6) errors.push("grade_cap");
  if (!ontology.has(spec.concept_id)) errors.push("ontology");
  if (!allowedInteractionTypes.includes(spec.interaction_type)) errors.push("interaction_not_allowed");

  const text = [spec.prompt, spec.hint, spec.explanation, spec.real_world_connection].join(" ").toLowerCase();
  if (/\b(sin|cos|tan)\b/.test(text)) errors.push("contains_trig");
  if (/\b(proof|surd|irrational)\b/.test(text)) errors.push("grade_cap");

  if (spec.diagram_spec.type !== "triangle" || spec.diagram_spec.points_normalized.length !== 3) errors.push("diagram_invalid");
  const ids = new Set(spec.diagram_spec.points_normalized.map((p) => p.id));
  if (!["A", "B", "C"].every((id) => ids.has(id as "A" | "B" | "C"))) errors.push("diagram_points");
  if (spec.diagram_spec.points_normalized.some((p) => p.x < 0 || p.x > 1 || p.y < 0 || p.y > 1)) errors.push("diagram_bounds");
  if (triangleArea(spec) <= 0.001) errors.push("diagram_degenerate");

  if (spec.response_contract.mode !== spec.interaction_type) errors.push("answer_mismatch");
  if (spec.interaction_type === "multiple_choice") {
    if (spec.response_contract.answer.kind !== "option_id") errors.push("answer_mismatch");
    if (!spec.response_contract.options || spec.response_contract.options.length < 2) errors.push("answer_mismatch");
    if (!spec.response_contract.options?.some((opt) => opt.id === spec.response_contract.answer.value)) errors.push("answer_mismatch");
  }
  if (spec.interaction_type === "numeric_input" && (spec.response_contract.answer.kind !== "number" || Number.isNaN(Number(spec.response_contract.answer.value)))) errors.push("answer_mismatch");
  if (spec.interaction_type === "highlight" && !(spec.response_contract.answer.kind === "point_set" || spec.response_contract.answer.kind === "segment")) errors.push("answer_mismatch");
  return errors;
}

export function normalizeLearnerContext(raw: unknown): LearnerContext {
  if (!raw || typeof raw !== "object") {
    return {
      recentConceptIds: [],
      recentPromptHashes: [],
      recentInteractionTypes: [],
      recentExpectedAnswers: []
    };
  }

  const payload = raw as Record<string, unknown>;
  return {
    recentConceptIds: readStringArray(payload.recent_concept_ids),
    recentPromptHashes: readStringArray(payload.recent_prompt_hashes),
    recentInteractionTypes: readStringArray(payload.recent_interaction_types),
    recentExpectedAnswers: readStringArray(payload.recent_expected_answers)
  };
}

export function validateNovelty(spec: QuestionSpec, learnerContext: LearnerContext, config: NoveltyConfig = DEFAULT_NOVELTY_CONFIG): string[] {
  const violations: string[] = [];
  const promptHash = promptTemplateHash(spec.prompt);
  const expectedTarget = expectedAnswerKey(spec);

  if (learnerContext.recentPromptHashes.slice(-config.promptHashWindow).includes(promptHash)) {
    violations.push("novelty_violation");
  }

  const repeats = learnerContext.recentExpectedAnswers.filter((value) => value === expectedTarget).length;
  if (repeats >= config.expectedAnswerRepeatLimit) {
    violations.push("novelty_violation");
  }

  return [...new Set(violations)];
}

export function prioritizeInteractionTypes(allowedInteractionTypes: string[], learnerContext: LearnerContext): string[] {
  const unseen = allowedInteractionTypes.filter((type) => !learnerContext.recentInteractionTypes.includes(type));
  if (unseen.length === 0) return allowedInteractionTypes;
  const seen = allowedInteractionTypes.filter((type) => learnerContext.recentInteractionTypes.includes(type));
  return [...unseen, ...seen];
}

export function validateDifficultyRating(rating: DifficultyRating): string[] {
  const errors: string[] = [];
  if (rating.schema_version !== "m3.difficulty_rating.v1") errors.push("schema");
  const values = [rating.overall, rating.dimensions.visual, rating.dimensions.language, rating.dimensions.reasoning_steps, rating.dimensions.numeric];
  if (!values.every((value) => Number.isInteger(value) && value >= 1 && value <= 4)) errors.push("range");
  return errors;
}

export async function generateWithLLM(input: {
  conceptId: string;
  grade: number;
  allowedInteractionTypes: string[];
  targetDirection?: string;
  targetBand?: { min: number; max: number };
  learnerContext?: LearnerContext;
}): Promise<QuestionSpec> {
  const learnerContext = input.learnerContext ?? {
    recentConceptIds: [],
    recentPromptHashes: [],
    recentInteractionTypes: [],
    recentExpectedAnswers: []
  };
  const prioritizedInteractions = prioritizeInteractionTypes(input.allowedInteractionTypes, learnerContext);
  const fallback = makeFallbackSpec(input.conceptId, prioritizedInteractions[0] ?? "highlight", input.targetBand?.min ?? 2);
  if (!process.env.OPENAI_API_KEY) return fallback;
  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const prompt = `You are SmartTutor's Grade-6 K12 geometry tutor.\nReturn strict JSON only.\nTopic scope: Triangles up to Pythagoras.\nNo trig, no formal proofs, no surds/irrational roots.\nUse concept_id=${input.conceptId}, grade=${input.grade}.\nAllowed interaction types (prioritized): ${prioritizedInteractions.join(",")}.\nTarget band: ${JSON.stringify(input.targetBand ?? null)}. Target direction: ${input.targetDirection ?? "null"}.\nAvoid recent prompt templates with hashes: ${learnerContext.recentPromptHashes.join(",") || "none"}.\nAvoid repeating expected answer targets recently used: ${learnerContext.recentExpectedAnswers.join(",") || "none"}.\nPrefer interaction types not used recently: ${learnerContext.recentInteractionTypes.join(",") || "none"}.\nSchema keys required: schema_version,question_id,concept_id,grade,interaction_type,difficulty_metadata,diagram_spec,prompt,response_contract,hint,explanation,real_world_connection.`;

  try {
    const response = await client.responses.create({
      model: "gpt-4.1-mini",
      input: [{ role: "user", content: [{ type: "input_text", text: prompt }] }]
    });
    const text = response.output_text || "";
    const parsed = JSON.parse(text) as QuestionSpec;
    return parsed;
  } catch {
    return fallback;
  }
}

function readStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((entry): entry is string => typeof entry === "string")
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0)
    .slice(-8);
}

function promptTemplateHash(prompt: string): string {
  const normalized = prompt
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
  return createHash("sha256").update(normalized).digest("hex").slice(0, 16);
}

function expectedAnswerKey(spec: QuestionSpec): string {
  return `${spec.response_contract.answer.kind}:${spec.response_contract.answer.value}`.toLowerCase().trim();
}

export async function rateWithLLM(questionSpec: QuestionSpec, grade: number): Promise<DifficultyRating> {
  const fallback = heuristicRating(questionSpec);
  if (!process.env.OPENAI_API_KEY) return fallback;
  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const rubric = `You are an independent difficulty rater. Return strict JSON only. Grade=${grade}.\nRate overall + dimensions visual/language/reasoning_steps/numeric in range 1..4.\nSet grade_fit.ok and notes; set flags for trig/proof/surd/out_of_ontology/non_renderable_diagram/interaction_answer_mismatch.`;
  try {
    const response = await client.responses.create({
      model: "gpt-4.1-mini",
      input: [
        { role: "user", content: [{ type: "input_text", text: rubric }, { type: "input_text", text: JSON.stringify(questionSpec) }] }
      ]
    });
    const parsed = JSON.parse(response.output_text || "") as DifficultyRating;
    return parsed;
  } catch {
    return fallback;
  }
}

function heuristicRating(spec: QuestionSpec): DifficultyRating {
  const interactionBoost = spec.interaction_type === "numeric_input" ? 1 : 0;
  const reasoning = Math.min(4, Math.max(1, spec.prompt.split(" ").length > 20 ? 3 : 2));
  const overall = Math.min(4, Math.max(1, Math.round((reasoning + interactionBoost + spec.difficulty_metadata.generator_self_rating) / 2)));
  const flags = {
    contains_trig: false,
    contains_formal_proof: false,
    contains_surd_or_irrational_root: false,
    out_of_ontology: !ontology.has(spec.concept_id),
    non_renderable_diagram: triangleArea(spec) <= 0.001,
    interaction_answer_mismatch: (spec.interaction_type === "multiple_choice" && spec.response_contract.answer.kind !== "option_id") ||
      (spec.interaction_type === "numeric_input" && spec.response_contract.answer.kind !== "number") ||
      (spec.interaction_type === "highlight" && !(spec.response_contract.answer.kind === "point_set" || spec.response_contract.answer.kind === "segment"))
  };

  return {
    schema_version: "m3.difficulty_rating.v1",
    overall,
    dimensions: {
      visual: spec.interaction_type === "highlight" ? 3 : 2,
      language: 2,
      reasoning_steps: reasoning,
      numeric: spec.interaction_type === "numeric_input" ? 3 : 1
    },
    grade_fit: {
      ok: !Object.values(flags).some(Boolean),
      notes: Object.values(flags).some(Boolean) ? "One or more grade/scope constraints violated." : "Within Grade 6 scope."
    },
    flags
  };
}

function triangleArea(spec: QuestionSpec): number {
  const a = spec.diagram_spec.points_normalized.find((point) => point.id === "A");
  const b = spec.diagram_spec.points_normalized.find((point) => point.id === "B");
  const c = spec.diagram_spec.points_normalized.find((point) => point.id === "C");
  if (!a || !b || !c) return 0;
  return Math.abs(a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y)) / 2;
}

function makeFallbackSpec(conceptId: string, interactionType: string, difficulty: number): QuestionSpec {
  const safeType: QuestionSpec["interaction_type"] = ["highlight", "multiple_choice", "numeric_input"].includes(interactionType)
    ? interactionType as QuestionSpec["interaction_type"]
    : "highlight";
  const isPyth = conceptId.includes("tri.pyth");
  const isBasics = conceptId.includes("tri.basics");

  const answerKind = safeType === "multiple_choice" ? "option_id" : safeType === "numeric_input" ? "number" : "segment";
  const answerValue = safeType === "numeric_input" ? (isPyth ? "13" : "5") : "AB";
  const options = safeType === "multiple_choice"
    ? [
      { id: "opt_ab", text: "AB" },
      { id: "opt_bc", text: "BC" },
      { id: "opt_ca", text: "CA" }
    ]
    : undefined;

  const prompt = isPyth
    ? (safeType === "numeric_input" ? "A right triangle has legs 5 and 12. Enter the hypotenuse length." : "Which statement matches a 5-12-13 right triangle?")
    : isBasics
      ? "Identify the side opposite the marked right angle."
      : "Identify the segment that matches the prompt for this triangle concept.";
  const hint = isPyth ? "Use a² + b² = c²." : "Look at the right-angle marker first.";
  const explanation = isPyth
    ? "For a right triangle, the square of the hypotenuse equals the sum of squares of the legs."
    : "Use labels and structure to reason about which side satisfies the condition in the prompt.";
  const realWorld = isPyth
    ? "Ramps and ladders often form right triangles where this relation helps estimate length."
    : "Triangle side identification helps in maps, roof trusses, and basic engineering sketches.";

  return {
    schema_version: "m3.question_spec.v2",
    question_id: `fallback.${conceptId}.${Date.now()}`,
    concept_id: conceptId,
    grade: 6,
    interaction_type: safeType,
    difficulty_metadata: { generator_self_rating: Math.max(1, Math.min(4, difficulty)) },
    diagram_spec: {
      type: "triangle",
      points_normalized: [
        { id: "A", x: 0.2, y: 0.75 },
        { id: "B", x: 0.8, y: 0.75 },
        { id: "C", x: 0.55, y: 0.2 }
      ],
      right_angle_at: "C"
    },
    prompt,
    response_contract: {
      mode: safeType,
      answer: {
        kind: answerKind,
        value: safeType === "multiple_choice" ? "opt_ab" : answerValue
      },
      options,
      numeric_rule: safeType === "numeric_input" ? { tolerance: 0 } : undefined
    },
    hint,
    explanation,
    real_world_connection: realWorld
  };
}
