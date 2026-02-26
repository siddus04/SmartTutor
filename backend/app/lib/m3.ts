import OpenAI from "openai";
import { createHash } from "crypto";

export type QuestionSpec = {
  schema_version: "m3.question_spec.v2";
  question_id: string;
  question_family?: string;
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
  assessment_contract?: {
    objective_type: string;
    answer_schema: string;
    grading_strategy_id: string;
    feedback_policy_id: string;
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

type ConceptSemanticRule = {
  requiredSignalGroups: string[][];
  forbiddenSignals: string[];
};

export class InvalidQuestionSpecError extends Error {
  readonly reasons: string[];

  constructor(reasons: string[]) {
    super("invalid_question_spec");
    this.name = "InvalidQuestionSpecError";
    this.reasons = reasons;
  }
}
export type LearnerContext = {
  recentConceptIds: string[];
  recentPromptHashes: string[];
  recentInteractionTypes: string[];
  recentExpectedAnswers: string[];
  recentQuestionFamilies: string[];
};

export type NoveltyConfig = {
  promptHashWindow: number;
  expectedAnswerRepeatLimit: number;
  familyRepeatLimit: number;
};

const DEFAULT_NOVELTY_CONFIG: NoveltyConfig = {
  promptHashWindow: 3,
  expectedAnswerRepeatLimit: 2,
  familyRepeatLimit: 2
};

const ontology = new Set([
  "tri.basics.identify_right_angle","tri.basics.identify_right_triangle","tri.basics.vertices_sides_angles",
  "tri.structure.hypotenuse","tri.structure.legs","tri.structure.opposite_adjacent_relative",
  "tri.reasoning.compare_side_lengths","tri.reasoning.hypotenuse_longest","tri.reasoning.informal_side_relationships",
  "tri.pyth.check_if_right_triangle","tri.pyth.equation_a2_b2_c2","tri.pyth.solve_missing_side","tri.pyth.square_area_intuition","tri.pyth.square_numbers_refresher",
  "tri.app.mixed_mastery_test","tri.app.real_life_modeling","tri.app.word_problems"
]);

type ConceptContract = {
  requiredSkillObjective: string;
  allowedAnswerKinds: string[];
  allowedInteractionTypes: QuestionSpec["interaction_type"][];
  prohibitedGenericPhrasing: string[];
  minimumVariationRequirements: {
    wording: string;
    diagram: string;
    answerTarget: string;
  };
};

const baseProhibitedGenericPhrasing = [
  "answer the question",
  "look at the triangle",
  "use the diagram",
  "choose the correct answer",
  "solve this"
];

const conceptContractTable: Record<string, ConceptContract> = {
  "tri.basics.identify_right_angle": {
    requiredSkillObjective: "Identify the right angle in a labeled triangle.",
    allowedAnswerKinds: ["point_set", "option_id"],
    allowedInteractionTypes: ["highlight", "multiple_choice"],
    prohibitedGenericPhrasing: baseProhibitedGenericPhrasing,
    minimumVariationRequirements: {
      wording: "Rotate sentence stems and angle naming format (e.g., ∠ABC vs right-angle marker).",
      diagram: "Change the right-angle vertex and orientation across attempts.",
      answerTarget: "Alternate target among vertices while keeping one unique correct right angle."
    }
  },
  "tri.basics.identify_right_triangle": {
    requiredSkillObjective: "Determine whether a shown triangle is a right triangle.",
    allowedAnswerKinds: ["option_id"],
    allowedInteractionTypes: ["multiple_choice"],
    prohibitedGenericPhrasing: baseProhibitedGenericPhrasing,
    minimumVariationRequirements: {
      wording: "Vary prompt language between identify/classify/justify-lite forms.",
      diagram: "Mix right and non-right triangles with different orientations.",
      answerTarget: "Switch which option is correct between yes/no style choices."
    }
  },
  "tri.basics.vertices_sides_angles": {
    requiredSkillObjective: "Map between named vertices, sides, and angles in a triangle.",
    allowedAnswerKinds: ["segment", "point_set", "option_id"],
    allowedInteractionTypes: ["highlight", "multiple_choice"],
    prohibitedGenericPhrasing: baseProhibitedGenericPhrasing,
    minimumVariationRequirements: {
      wording: "Alternate whether prompt asks for vertex, side, or angle identification.",
      diagram: "Re-label triangle points and orientation while staying renderable.",
      answerTarget: "Cycle target between AB/BC/CA and A/B/C references."
    }
  },
  "tri.structure.hypotenuse": {
    requiredSkillObjective: "Identify the hypotenuse as the side opposite the right angle.",
    allowedAnswerKinds: ["segment", "option_id"],
    allowedInteractionTypes: ["highlight", "multiple_choice"],
    prohibitedGenericPhrasing: [...baseProhibitedGenericPhrasing, "find the longest side"],
    minimumVariationRequirements: {
      wording: "Use both structural wording (opposite right angle) and constrained comparative wording.",
      diagram: "Vary right-angle location and segment labels.",
      answerTarget: "Ensure the hypotenuse label differs across attempts."
    }
  },
  "tri.structure.legs": {
    requiredSkillObjective: "Identify the two legs that form the right angle.",
    allowedAnswerKinds: ["segment", "point_set", "option_id"],
    allowedInteractionTypes: ["highlight", "multiple_choice"],
    prohibitedGenericPhrasing: [...baseProhibitedGenericPhrasing, "pick any two sides"],
    minimumVariationRequirements: {
      wording: "Vary wording between 'legs', 'sides forming right angle', and 'perpendicular sides'.",
      diagram: "Change right-angle vertex and keep leg pairs explicit.",
      answerTarget: "Alternate whether one leg or both-leg set is the required answer."
    }
  },
  "tri.structure.opposite_adjacent_relative": {
    requiredSkillObjective: "Determine opposite/adjacent sides relative to a referenced acute angle.",
    allowedAnswerKinds: ["segment", "option_id"],
    allowedInteractionTypes: ["highlight", "multiple_choice"],
    prohibitedGenericPhrasing: [...baseProhibitedGenericPhrasing, "opposite means across"],
    minimumVariationRequirements: {
      wording: "Alternate reference-angle naming conventions and relation requested (opposite vs adjacent).",
      diagram: "Change the reference acute angle and side labels each attempt.",
      answerTarget: "Switch correct segment target between opposite and adjacent roles."
    }
  },
  "tri.reasoning.compare_side_lengths": {
    requiredSkillObjective: "Compare side lengths using right-triangle structure and provided measures.",
    allowedAnswerKinds: ["option_id", "number"],
    allowedInteractionTypes: ["multiple_choice", "numeric_input"],
    prohibitedGenericPhrasing: [...baseProhibitedGenericPhrasing, "just compare visually"],
    minimumVariationRequirements: {
      wording: "Mix prompts asking for greater/less/equal or ordering.",
      diagram: "Vary value placement and side labels without ambiguity.",
      answerTarget: "Alternate correct target between segment labels and computed numeric comparisons."
    }
  },
  "tri.reasoning.hypotenuse_longest": {
    requiredSkillObjective: "Reason that hypotenuse is the longest side in a right triangle.",
    allowedAnswerKinds: ["segment", "option_id"],
    allowedInteractionTypes: ["highlight", "multiple_choice"],
    prohibitedGenericPhrasing: [...baseProhibitedGenericPhrasing, "because it looks longest"],
    minimumVariationRequirements: {
      wording: "Rotate between identify/explain-lite/true-false style stems.",
      diagram: "Use distinct scalings and orientations with clear right-angle marking.",
      answerTarget: "Change which segment is hypotenuse across attempts."
    }
  },
  "tri.reasoning.informal_side_relationships": {
    requiredSkillObjective: "Use informal side relationships to evaluate triangle statements.",
    allowedAnswerKinds: ["option_id"],
    allowedInteractionTypes: ["multiple_choice"],
    prohibitedGenericPhrasing: [...baseProhibitedGenericPhrasing, "pick what seems right"],
    minimumVariationRequirements: {
      wording: "Alternate between statement validation and completion prompts.",
      diagram: "Vary given side values and right-angle placement.",
      answerTarget: "Move correctness among options each attempt."
    }
  },
  "tri.pyth.check_if_right_triangle": {
    requiredSkillObjective: "Check if side lengths satisfy the Pythagorean relationship.",
    allowedAnswerKinds: ["option_id"],
    allowedInteractionTypes: ["multiple_choice"],
    prohibitedGenericPhrasing: [...baseProhibitedGenericPhrasing, "use the formula"],
    minimumVariationRequirements: {
      wording: "Vary between yes/no judgment and choose-valid-statement forms.",
      diagram: "Change side-length triplets including both valid and invalid sets.",
      answerTarget: "Alternate which option corresponds to 'is right triangle'."
    }
  },
  "tri.pyth.equation_a2_b2_c2": {
    requiredSkillObjective: "Write or select the correct equation a² + b² = c² for a right triangle.",
    allowedAnswerKinds: ["option_id"],
    allowedInteractionTypes: ["multiple_choice"],
    prohibitedGenericPhrasing: [...baseProhibitedGenericPhrasing, "memorize the equation"],
    minimumVariationRequirements: {
      wording: "Vary between fill-the-equation and identify-correct-equation phrasing.",
      diagram: "Change which side is marked as hypotenuse and corresponding labels.",
      answerTarget: "Rotate correct option placement and variable mapping."
    }
  },
  "tri.pyth.solve_missing_side": {
    requiredSkillObjective: "Solve for a missing side in a right triangle using a² + b² = c².",
    allowedAnswerKinds: ["number", "option_id"],
    allowedInteractionTypes: ["numeric_input", "multiple_choice"],
    prohibitedGenericPhrasing: [...baseProhibitedGenericPhrasing, "do the calculation"],
    minimumVariationRequirements: {
      wording: "Alternate between direct compute prompts and contextualized short scenarios.",
      diagram: "Vary known-side pairs and whether missing side is leg or hypotenuse.",
      answerTarget: "Switch answer target among different missing sides and values."
    }
  },
  "tri.pyth.square_area_intuition": {
    requiredSkillObjective: "Connect squares on sides to the Pythagorean area relationship.",
    allowedAnswerKinds: ["option_id", "number"],
    allowedInteractionTypes: ["multiple_choice", "numeric_input"],
    prohibitedGenericPhrasing: [...baseProhibitedGenericPhrasing, "area always adds"],
    minimumVariationRequirements: {
      wording: "Vary statement-check and compute-area-intuition wording.",
      diagram: "Change side lengths and square annotations deterministically.",
      answerTarget: "Alternate between selecting valid statement and entering area-based value."
    }
  },
  "tri.pyth.square_numbers_refresher": {
    requiredSkillObjective: "Recall square numbers needed for Pythagorean computations.",
    allowedAnswerKinds: ["number", "option_id"],
    allowedInteractionTypes: ["numeric_input", "multiple_choice"],
    prohibitedGenericPhrasing: [...baseProhibitedGenericPhrasing, "just square it"],
    minimumVariationRequirements: {
      wording: "Mix direct square lookup, reverse-square, and missing-value stems.",
      diagram: "If diagram used, vary which side receives the square value focus.",
      answerTarget: "Change target value and numeric result each attempt."
    }
  },
  "tri.app.mixed_mastery_test": {
    requiredSkillObjective: "Apply multiple triangle skills in a single mixed mastery prompt.",
    allowedAnswerKinds: ["option_id", "number", "segment"],
    allowedInteractionTypes: ["highlight", "multiple_choice", "numeric_input"],
    prohibitedGenericPhrasing: [...baseProhibitedGenericPhrasing, "use any method"],
    minimumVariationRequirements: {
      wording: "Vary dominant sub-skill and context framing each attempt.",
      diagram: "Change which triangle feature carries the key clue.",
      answerTarget: "Rotate between structural, numeric, and validation outcomes."
    }
  },
  "tri.app.real_life_modeling": {
    requiredSkillObjective: "Model real-life right-triangle situations and infer unknowns.",
    allowedAnswerKinds: ["number", "option_id"],
    allowedInteractionTypes: ["numeric_input", "multiple_choice"],
    prohibitedGenericPhrasing: [...baseProhibitedGenericPhrasing, "in real life"],
    minimumVariationRequirements: {
      wording: "Rotate scenario domain (ladder, ramp, path, roof) and ask variant.",
      diagram: "Change contextual labels and known measures while keeping triangle deterministic.",
      answerTarget: "Alternate missing quantity (height/base/hypotenuse) across attempts."
    }
  },
  "tri.app.word_problems": {
    requiredSkillObjective: "Interpret triangle word problems and produce correct triangle-based answer.",
    allowedAnswerKinds: ["number", "option_id"],
    allowedInteractionTypes: ["numeric_input", "multiple_choice"],
    prohibitedGenericPhrasing: [...baseProhibitedGenericPhrasing, "read carefully"],
    minimumVariationRequirements: {
      wording: "Vary sentence structure and what must be inferred from text.",
      diagram: "Alter supporting diagram orientation/labels or omit when appropriate.",
      answerTarget: "Change which unknown is solved and final answer form."
    }
  }
};

function buildConceptContractText(input: { conceptId: string; allowedInteractionTypes: string[] }): string {
  const selected = conceptContractTable[input.conceptId];
  if (!selected) return "No concept-specific contract found. Keep response strictly in schema and scope.";

  const interactionTypes = selected.allowedInteractionTypes.filter((interactionType) => input.allowedInteractionTypes.includes(interactionType));
  const effectiveInteractionTypes = interactionTypes.length > 0 ? interactionTypes : input.allowedInteractionTypes;
  return [
    `Concept contract for ${input.conceptId}:`,
    `- Required skill objective: ${selected.requiredSkillObjective}`,
    `- Allowed answer kinds: ${selected.allowedAnswerKinds.join(", ")}`,
    `- Allowed interaction types for this concept: ${effectiveInteractionTypes.join(", ")}`,
    `- Prohibited generic phrasing: ${selected.prohibitedGenericPhrasing.join(" | ")}`,
    `- Minimum variation requirements: wording=${selected.minimumVariationRequirements.wording}; diagram=${selected.minimumVariationRequirements.diagram}; answer_target=${selected.minimumVariationRequirements.answerTarget}`,
    "- Across repeated attempts for the same concept and difficulty, explicitly vary question family (e.g., diagram labeling, statement validation, scenario-based prompt, equation completion, numerical solve)."
  ].join("\n");
}

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

  if (!spec.assessment_contract) {
    errors.push("assessment_contract_missing");
  } else {
    if (!spec.assessment_contract.objective_type || !spec.assessment_contract.answer_schema || !spec.assessment_contract.grading_strategy_id || !spec.assessment_contract.feedback_policy_id) {
      errors.push("assessment_contract_invalid");
    }
  }

  errors.push(...validateConceptSemantics(spec));
  return errors;
}

export function normalizeLearnerContext(raw: unknown): LearnerContext {
  if (!raw || typeof raw !== "object") {
    return {
      recentConceptIds: [],
      recentPromptHashes: [],
      recentInteractionTypes: [],
      recentExpectedAnswers: [],
      recentQuestionFamilies: []
    };
  }

  const payload = raw as Record<string, unknown>;
  return {
    recentConceptIds: readStringArray(payload.recent_concept_ids),
    recentPromptHashes: readStringArray(payload.recent_prompt_hashes),
    recentInteractionTypes: readStringArray(payload.recent_interaction_types),
    recentExpectedAnswers: readStringArray(payload.recent_expected_answers),
    recentQuestionFamilies: readStringArray(payload.recent_question_families)
  };
}

export function validateNovelty(spec: QuestionSpec, learnerContext: LearnerContext, config: NoveltyConfig = DEFAULT_NOVELTY_CONFIG): string[] {
  const violations: string[] = [];
  const promptHash = promptTemplateHash(spec.prompt);
  const expectedTarget = expectedAnswerKey(spec);
  const family = effectiveQuestionFamily(spec);

  if (learnerContext.recentPromptHashes.slice(-config.promptHashWindow).includes(promptHash)) {
    violations.push("novelty_violation");
  }

  const repeats = learnerContext.recentExpectedAnswers.filter((value) => value === expectedTarget).length;
  if (repeats >= config.expectedAnswerRepeatLimit) {
    violations.push("novelty_violation");
  }

  const familyRepeats = learnerContext.recentQuestionFamilies.filter((value) => value === family).length;
  if (familyRepeats >= config.familyRepeatLimit) {
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
    recentExpectedAnswers: [],
    recentQuestionFamilies: []
  };
  const prioritizedInteractions = prioritizeInteractionTypes(input.allowedInteractionTypes, learnerContext);
  const fallback = makeFallbackSpec(input.conceptId, prioritizedInteractions[0] ?? "highlight", input.targetBand?.min ?? 2);
  if (!process.env.OPENAI_API_KEY) return fallback;
  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const conceptContractText = buildConceptContractText(input);
  const prompt = `You are SmartTutor's Grade-6 K12 geometry tutor.\nReturn strict JSON only.\nTopic scope: Triangles up to Pythagoras.\nNo trig, no formal proofs, no surds/irrational roots.\nUse concept_id=${input.conceptId}, grade=${input.grade}.\nAllowed interaction types: ${input.allowedInteractionTypes.join(",")}.\nTarget band: ${JSON.stringify(input.targetBand ?? null)}. Target direction: ${input.targetDirection ?? "null"}.\n${conceptContractText}\nSchema keys required: schema_version,question_id,question_family,concept_id,grade,interaction_type,difficulty_metadata,diagram_spec,prompt,response_contract,assessment_contract,hint,explanation,real_world_connection.`;

  try {
    const response = await client.responses.create({
      model: "gpt-4.1-mini",
      input: [{ role: "user", content: [{ type: "input_text", text: prompt }] }]
    });
    const text = response.output_text || "";
    const parsed = JSON.parse(text) as QuestionSpec;
    const semanticErrors = validateConceptSemantics(parsed);
    if (semanticErrors.length > 0) {
      throw new InvalidQuestionSpecError(semanticErrors);
    }
    return parsed;
  } catch (error) {
    if (error instanceof InvalidQuestionSpecError) {
      throw error;
    }
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

function effectiveQuestionFamily(spec: QuestionSpec): string {
  if (spec.question_family && spec.question_family.trim().length > 0) {
    return spec.question_family.trim().toLowerCase();
  }
  return fallbackQuestionFamily(spec.concept_id, spec.interaction_type);
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

const conceptSemanticRules: Record<string, ConceptSemanticRule> = {
  "tri.basics.identify_right_angle": {
    requiredSignalGroups: [["right angle", "90"]],
    forbiddenSignals: ["hypotenuse", "a2+b2", "a²+b²", "pythag"]
  },
  "tri.basics.identify_right_triangle": {
    requiredSignalGroups: [["right triangle", "right-angled triangle", "right angle"]],
    forbiddenSignals: ["a2+b2", "a²+b²", "pythag"]
  },
  "tri.basics.vertices_sides_angles": {
    requiredSignalGroups: [["vertex", "vertices"], ["side"], ["angle"]],
    forbiddenSignals: ["a2+b2", "a²+b²", "pythag"]
  },
  "tri.structure.hypotenuse": {
    requiredSignalGroups: [["hypotenuse"], ["right angle", "right triangle"]],
    forbiddenSignals: ["a2+b2", "a²+b²", "pythag"]
  },
  "tri.structure.legs": {
    requiredSignalGroups: [["leg", "legs", "perpendicular sides"]],
    forbiddenSignals: ["hypotenuse only", "a2+b2", "a²+b²"]
  },
  "tri.structure.opposite_adjacent_relative": {
    requiredSignalGroups: [["opposite"], ["adjacent"]],
    forbiddenSignals: ["sin", "cos", "tan"]
  },
  "tri.reasoning.compare_side_lengths": {
    requiredSignalGroups: [["compare", "order", "longer", "shorter"], ["side", "length"]],
    forbiddenSignals: ["sin", "cos", "tan"]
  },
  "tri.reasoning.hypotenuse_longest": {
    requiredSignalGroups: [["hypotenuse"], ["longest"]],
    forbiddenSignals: ["a2+b2", "a²+b²", "pythag"]
  },
  "tri.reasoning.informal_side_relationships": {
    requiredSignalGroups: [["side relationship", "statement", "always", "sometimes", "never"]],
    forbiddenSignals: ["formal proof", "sin", "cos", "tan"]
  },
  "tri.pyth.check_if_right_triangle": {
    requiredSignalGroups: [["right triangle", "right-angle triangle"], ["a2+b2", "a²+b²", "pythag"]],
    forbiddenSignals: ["sin", "cos", "tan"]
  },
  "tri.pyth.equation_a2_b2_c2": {
    requiredSignalGroups: [["a2+b2", "a²+b²", "c2", "c²", "pythag"]],
    forbiddenSignals: ["sin", "cos", "tan"]
  },
  "tri.pyth.solve_missing_side": {
    requiredSignalGroups: [["missing side", "unknown side", "find side", "solve"], ["a2+b2", "a²+b²", "pythag"]],
    forbiddenSignals: ["sin", "cos", "tan"]
  },
  "tri.pyth.square_area_intuition": {
    requiredSignalGroups: [["square", "area"], ["a2+b2", "a²+b²", "c2", "c²"]],
    forbiddenSignals: ["sin", "cos", "tan"]
  },
  "tri.pyth.square_numbers_refresher": {
    requiredSignalGroups: [["square number", "squared", "perfect square"]],
    forbiddenSignals: ["sin", "cos", "tan"]
  },
  "tri.app.mixed_mastery_test": {
    requiredSignalGroups: [["mixed", "review", "mastery"], ["triangle", "right triangle"]],
    forbiddenSignals: ["sin", "cos", "tan"]
  },
  "tri.app.real_life_modeling": {
    requiredSignalGroups: [["real-life", "model", "ramp", "ladder", "roof"]],
    forbiddenSignals: ["sin", "cos", "tan"]
  },
  "tri.app.word_problems": {
    requiredSignalGroups: [["word problem", "story", "situation"], ["triangle", "right triangle"]],
    forbiddenSignals: ["sin", "cos", "tan"]
  }
};

export function validateConceptSemantics(spec: QuestionSpec): string[] {
  const errors: string[] = [];
  const textPool = buildSemanticTextPool(spec);
  const rule = conceptSemanticRules[spec.concept_id];

  if (rule) {
    const missingRequired = rule.requiredSignalGroups.some((group) => !group.some((signal) => textPool.includes(normalizeSignal(signal))));
    const hasForbidden = rule.forbiddenSignals.some((signal) => textPool.includes(normalizeSignal(signal)));
    if (missingRequired || hasForbidden) {
      errors.push("concept_mismatch");
    }
  }

  if (isGenericRepetition(spec)) {
    errors.push("generic_repetition");
  }

  return errors;
}

function buildSemanticTextPool(spec: QuestionSpec): string {
  const optionText = spec.response_contract.options?.map((option) => option.text).join(" ") ?? "";
  const combined = [
    spec.prompt,
    spec.hint,
    spec.explanation,
    spec.real_world_connection,
    spec.response_contract.answer.value,
    optionText
  ].join(" ");
  return normalizeSignal(combined);
}

function normalizeSignal(input: string): string {
  return input.toLowerCase().replace(/\s+/g, " ").replace(/[^a-z0-9²+ ]/g, "").trim();
}

function isGenericRepetition(spec: QuestionSpec): boolean {
  const normalizedBlocks = [spec.prompt, spec.hint, spec.explanation].map((value) => normalizeSignal(value));
  const uniqueBlocks = new Set(normalizedBlocks.filter((value) => value.length > 0));
  if (uniqueBlocks.size <= 1) {
    return true;
  }

  const uniqueWords = new Set(normalizedBlocks.join(" ").split(" ").filter((word) => word.length > 2));
  return uniqueWords.size < 8;
}

function fallbackQuestionFamily(conceptId: string, interactionType: string): string {
  if (conceptId.startsWith("tri.basics.")) return interactionType === "multiple_choice" ? "basics_mcq" : "basics_highlight";
  if (conceptId.startsWith("tri.structure.")) return interactionType === "multiple_choice" ? "structure_mcq" : "structure_identify";
  if (conceptId.startsWith("tri.reasoning.")) return interactionType === "numeric_input" ? "reasoning_numeric" : "reasoning_compare";
  if (conceptId.startsWith("tri.pyth.")) return interactionType === "numeric_input" ? "pyth_numeric" : "pyth_relation";
  if (conceptId.startsWith("tri.app.")) return interactionType === "numeric_input" ? "application_numeric" : "application_scenario";
  return `generic_${interactionType}`;
}

function makeFallbackSpec(conceptId: string, interactionType: string, difficulty: number): QuestionSpec {
  const safeType: QuestionSpec["interaction_type"] = ["highlight", "multiple_choice", "numeric_input"].includes(interactionType)
    ? interactionType as QuestionSpec["interaction_type"]
    : "highlight";

  const family = fallbackQuestionFamily(conceptId, safeType);
  const answerKind = safeType === "multiple_choice" ? "option_id" : safeType === "numeric_input" ? "number" : "segment";
  const options = safeType === "multiple_choice"
    ? [
      { id: "opt_a", text: "A" },
      { id: "opt_b", text: "B" },
      { id: "opt_c", text: "C" },
      { id: "opt_ab", text: "AB" },
      { id: "opt_bc", text: "BC" },
      { id: "opt_ca", text: "CA" }
    ]
    : undefined;

  let prompt = "Identify the segment that matches the prompt for this triangle concept.";
  let answerValue = safeType === "numeric_input" ? "5" : (safeType === "multiple_choice" ? "opt_ab" : "AB");
  let hint = "Use labels and the right-angle marker.";
  let explanation = "Use triangle structure and labels to justify your answer.";
  let realWorld = "Triangles are used in maps, roof trusses, and design sketches.";

  if (conceptId.startsWith("tri.basics.")) {
    prompt = safeType === "multiple_choice"
      ? "Which label names the right-angle vertex in this triangle?"
      : "Highlight the right-angle vertex in the triangle.";
    answerValue = safeType === "multiple_choice" ? "opt_c" : "C";
    hint = "A right angle is exactly 90° and is usually marked with a small square.";
    explanation = "The marked square shows the right angle, so that vertex is the correct target.";
    realWorld = "Builders check 90° corners so walls and floors align correctly.";
  } else if (conceptId.startsWith("tri.structure.")) {
    prompt = safeType === "multiple_choice"
      ? "Which side is opposite the right angle (the hypotenuse)?"
      : "Highlight the side opposite the right angle.";
    answerValue = safeType === "multiple_choice" ? "opt_ab" : "AB";
    hint = "The hypotenuse is across from the right-angle marker.";
    explanation = "In a right triangle, the side opposite the 90° angle is the hypotenuse.";
    realWorld = "Ramp length is often the hypotenuse in right-triangle models.";
  } else if (conceptId.startsWith("tri.reasoning.")) {
    prompt = safeType === "numeric_input"
      ? "In a right triangle with side lengths 6, 8, and 10, enter the longest side length."
      : "Which side should be longest in a right triangle?";
    answerValue = safeType === "numeric_input" ? "10" : "opt_ab";
    hint = "The side opposite the right angle is always the longest.";
    explanation = "Reasoning about side roles helps compare lengths even before using formulas.";
    realWorld = "Engineers compare triangle side lengths when checking supports.";
  } else if (conceptId.startsWith("tri.pyth.")) {
    prompt = safeType === "numeric_input"
      ? "A right triangle has legs 5 and 12. Enter the hypotenuse length."
      : "Which equation matches the Pythagorean relationship for right triangles?";
    answerValue = safeType === "numeric_input" ? "13" : "opt_a";
    hint = "Use a² + b² = c² for right triangles.";
    explanation = "The sum of squares of the legs equals the square of the hypotenuse.";
    realWorld = "Pythagorean checks help measure diagonals for ladders and ramps.";
  } else if (conceptId.startsWith("tri.app.")) {
    prompt = safeType === "numeric_input"
      ? "A ladder is 13 m long and reaches 12 m high. Enter the distance of the ladder base from the wall."
      : "A ladder, wall, and ground form a triangle. Which side is the hypotenuse?";
    answerValue = safeType === "numeric_input" ? "5" : "opt_ab";
    hint = "Convert the story to a right-triangle model before solving.";
    explanation = "Modeling word problems as right triangles reveals which side or value is needed.";
    realWorld = "Carpenters and firefighters use this triangle model in real situations.";
  }

  const assessmentContract = {
    objective_type: conceptId.startsWith("tri.pyth.")
      ? (safeType === "numeric_input" ? "solve_pythagorean_numeric" : "select_pythagorean_relation")
      : (safeType === "highlight" ? "highlight_triangle_target" : "select_triangle_statement"),
    answer_schema: safeType === "multiple_choice" ? "option_id" : safeType === "numeric_input" ? "numeric_value" : "visual_target",
    grading_strategy_id: safeType === "highlight" ? "vision_locator" : safeType === "numeric_input" ? "numeric_rule" : "deterministic_choice",
    feedback_policy_id: "triangles_grade6_guided_feedback"
  };

  return {
    schema_version: "m3.question_spec.v2",
    question_id: `fallback.${conceptId}.${Date.now()}`,
    question_family: family,
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
        value: answerValue
      },
      options,
      numeric_rule: safeType === "numeric_input" ? { tolerance: 0 } : undefined
    },
    assessment_contract: assessmentContract,
    hint,
    explanation,
    real_world_connection: realWorld
  };
}
