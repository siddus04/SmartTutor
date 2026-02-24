import OpenAI from "openai";

export type QuestionSpec = {
  schema_version: "m3.question_spec.v1";
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
  answer: { kind: string; value: string };
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

const ontology = new Set([
  "tri.basics.identify_right_angle","tri.basics.identify_right_triangle","tri.basics.vertices_sides_angles",
  "tri.structure.hypotenuse","tri.structure.legs","tri.structure.opposite_adjacent_relative",
  "tri.reasoning.compare_side_lengths","tri.reasoning.hypotenuse_longest","tri.reasoning.informal_side_relationships",
  "tri.pyth.check_if_right_triangle","tri.pyth.equation_a2_b2_c2","tri.pyth.solve_missing_side","tri.pyth.square_area_intuition","tri.pyth.square_numbers_refresher",
  "tri.app.mixed_mastery_test","tri.app.real_life_modeling","tri.app.word_problems"
]);

export function validateQuestionSpec(spec: QuestionSpec, allowedInteractionTypes: string[]): string[] {
  const errors: string[] = [];
  if (spec.schema_version !== "m3.question_spec.v1") errors.push("schema");
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

  if (spec.interaction_type === "multiple_choice" && spec.answer.kind !== "option_id") errors.push("answer_mismatch");
  if (spec.interaction_type === "numeric_input" && (spec.answer.kind !== "number" || Number.isNaN(Number(spec.answer.value)))) errors.push("answer_mismatch");
  if (spec.interaction_type === "highlight" && !(spec.answer.kind === "point_set" || spec.answer.kind === "segment")) errors.push("answer_mismatch");
  return errors;
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
}): Promise<QuestionSpec> {
  const fallback = makeFallbackSpec(input.conceptId, input.allowedInteractionTypes[0] ?? "highlight", input.targetBand?.min ?? 2);
  if (!process.env.OPENAI_API_KEY) return fallback;
  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const prompt = `You are SmartTutor's Grade-6 K12 geometry tutor.\nReturn strict JSON only.\nTopic scope: Triangles up to Pythagoras.\nNo trig, no formal proofs, no surds/irrational roots.\nUse concept_id=${input.conceptId}, grade=${input.grade}.\nAllowed interaction types: ${input.allowedInteractionTypes.join(",")}.\nTarget band: ${JSON.stringify(input.targetBand ?? null)}. Target direction: ${input.targetDirection ?? "null"}.\nSchema keys required: schema_version,question_id,concept_id,grade,interaction_type,difficulty_metadata,diagram_spec,prompt,answer,hint,explanation,real_world_connection.`;

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
    interaction_answer_mismatch: (spec.interaction_type === "multiple_choice" && spec.answer.kind !== "option_id") ||
      (spec.interaction_type === "numeric_input" && spec.answer.kind !== "number") ||
      (spec.interaction_type === "highlight" && !(spec.answer.kind === "point_set" || spec.answer.kind === "segment"))
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
  const answerKind = interactionType === "multiple_choice" ? "option_id" : interactionType === "numeric_input" ? "number" : "segment";
  const answerValue = interactionType === "numeric_input" ? "5" : "AB";
  return {
    schema_version: "m3.question_spec.v1",
    question_id: `fallback.${conceptId}.${Date.now()}`,
    concept_id: conceptId,
    grade: 6,
    interaction_type: (interactionType as QuestionSpec["interaction_type"]) || "highlight",
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
    prompt: "Find the hypotenuse of this right triangle.",
    answer: { kind: answerKind, value: answerValue },
    hint: "The hypotenuse is opposite the right angle.",
    explanation: "In a right triangle, the hypotenuse is the side across from the right angle.",
    real_world_connection: "A ladder leaning on a wall forms a right triangle."
  };
}
