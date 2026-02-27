import OpenAI from "openai";
import crypto from "crypto";
import { GradingResultEnvelope, gradeWithRouter } from "../../../lib/gradingRouter";
import { DIAGRAM_TARGET_CLASSES, DiagramTargetClass, normalizeDiagramTargetClass } from "../../../lib/diagramTargets";

const DIAGRAM_TARGET_LABELS = DIAGRAM_TARGET_CLASSES.join(", ");

const PROMPT = `You are SmartTutor’s AI geometry checker.

You will be given:
1) An image of a triangle diagram with labeled vertices A, B, C.
2) A student’s drawing over the triangle (arc/loop/circle).

Your task is to analyze the combined image and return exactly strict JSON with no extra text.

Hard rules:
- You must determine detected_target ONLY from the ink on the image.
- Do NOT assume the student circled the correct answer.
- Report what was circled even if incorrect.

Determine:
- "detected_target_class": one of [${DIAGRAM_TARGET_LABELS}] indicating what category of item the learner targeted.
- "detected_target": the concrete target value that was highlighted/circled (for example "AB", "A", "∠ABC", "region_1"), or null if you cannot confidently determine one target.
- "ambiguity_score": a float between 0 and 1 indicating how ambiguous the circle is (0 = very clear, 1 = completely ambiguous).
- "confidence": a float between 0 and 1 indicating your confidence that the detected side is correct.
- "reason_codes": an array of zero or more of these exact strings:
  ["NO_CLOSED_LOOP","MULTIPLE_SIDES_ENCLOSED","CIRCLE_NOT_NEAR_ANY_SIDE","INK_TOO_MESSY","UNCLEAR_DIAGRAM","OTHER"]
- "student_feedback": a concise feedback message appropriate for a Grade 4–6 student.

Interpretation rules:
- If there is no clear closed loop around a target, return detected_target = null and include "NO_CLOSED_LOOP".
- If more than one target is enclosed by the loop, return detected_target = null and include "MULTIPLE_SIDES_ENCLOSED".
- If the loop does not appear close to any known target, include "CIRCLE_NOT_NEAR_ANY_SIDE".
- If the drawing is too messy to decide, include "INK_TOO_MESSY".
- If the triangle diagram itself is unclear or unlabeled, include "UNCLEAR_DIAGRAM".
- Only choose a detected_target if a single target is enclosed clearly with low ambiguity.
- Never guess if ambiguous; return null.

Output must be strictly JSON with this exact object shape and nothing else:

{
  "detected_target_class": "vertices" | "segments" | "angles" | "enclosed_regions" | "symbolic_marks" | null,
  "detected_target": string | null,
  "ambiguity_score": number,
  "confidence": number,
  "reason_codes": [string],
  "student_feedback": string
}`;

const FEEDBACK_PROMPT = `You are SmartTutor’s AI geometry tutor. You are a fun high school math teacher who helps kids remember ideas.

You will be given:
- detected_target_class: what kind of diagram object was targeted.
- detected_target: what the student circled/tapped (or null).
- expected_answer_value: the expected answer value.
- ambiguity_score.
- prompt/context about the triangle.

Write a single short feedback message for a Grade 4–6 student.

Rules:
- If detected_target is null OR ambiguity_score >= 0.6: ask the student to re-circle just ONE target clearly.
- If detected_target is wrong:
  - Explicitly say their choice is not correct for the current question.
  - Mention the detected_target (e.g., "You circled CA").
  - Provide layered hints in two short sentences aligned with the prompt/context.
  - Do NOT reveal the correct side label directly.
- If detected_target is correct:
  - Praise briefly.
  - Include one short memorable fact or practical application that is DIFFERENT from the wrong-answer hints (e.g., ladders, roofs, ramps).
- Never reveal the correct side label directly if the student was wrong.
- Keep it concise.

Return ONLY strict JSON:
{
  "student_feedback": string
}`;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization"
};

const OBJECTIVE_VOCAB: Record<string, { targetType: string; boundedHints: [string, string]; reinforcement: string }> = {
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

type FeedbackNextAction = "retry" | "proceed" | "scaffold";

type FeedbackMetadata = {
  message: string;
  hint_level: 0 | 1 | 2;
  remediation_tag: string;
  next_action: FeedbackNextAction;
};

type FeedbackContext = {
  conceptId: string;
  objectiveType: string;
  expectedAnswer: string;
  detectedAnswer: string | null;
  noAnswerLeakage: boolean;
};

export const runtime = "nodejs";

export async function OPTIONS() {
  return new Response(null, { status: 204, headers: CORS_HEADERS });
}

export async function POST(request: Request) {
  let body: {
    concept_id?: string;
    prompt_text?: string;
    interaction_type?: string;
    response_mode?: string;
    right_angle_at?: "A" | "B" | "C" | null;
    merged_image_path?: string;
    combined_png_base64?: string;
    expected_answer_value?: string;
    submitted_choice_id?: string;
    submitted_numeric_value?: string;
    submitted_expression?: string;
    submitted_text?: string;
    assessment_contract?: {
      schema_version?: string;
      concept_id?: string;
      interaction_type?: string;
      objective_type?: string;
      answer_schema?: string;
      grading_strategy_id?: string;
      feedback_policy_id?: string;
      expected_answer?: {
        kind?: string;
        value?: string;
      };
      options?: Array<{ id?: string; text?: string }>;
      numeric_rule?: {
        tolerance?: number;
        min_value?: number;
        max_value?: number;
        unit?: string;
      };
    };
  };

  try {
    body = await request.json();
  } catch {
    return jsonResponse(errorEnvelope("INVALID_REQUEST_BODY", "Request body is not valid JSON."), 400);
  }

  const conceptId = body.concept_id ?? "";
  const promptText = body.prompt_text ?? "";
  const interactionType = body.interaction_type ?? "highlight";
  const responseMode = body.assessment_contract?.interaction_type ?? body.response_mode ?? interactionType;
  const rightAngleAt = body.right_angle_at ?? null;
  const mergedImagePath = body.merged_image_path ?? null;
  const combinedBase64 = body.combined_png_base64 ?? "";
  const expectedAnswerValue = body.assessment_contract?.expected_answer?.value ?? body.expected_answer_value ?? "AB";
  const expectedAnswerKind = body.assessment_contract?.expected_answer?.kind ?? null;
  const objectiveType = body.assessment_contract?.objective_type ?? "";
  const feedbackPolicyId = body.assessment_contract?.feedback_policy_id ?? "";

  const imageHash = crypto.createHash("sha256").update(combinedBase64).digest("hex").slice(0, 12);
  console.log("[API][Check][Request]", JSON.stringify({
    concept_id: conceptId,
    interaction_type: interactionType,
    response_mode: responseMode,
    right_angle_at: rightAngleAt,
    merged_image_path: mergedImagePath,
    expected_answer_value: expectedAnswerValue,
    submitted_choice_id: body.submitted_choice_id ?? null,
    submitted_numeric_value: body.submitted_numeric_value ?? null,
    submitted_expression: body.submitted_expression ?? null,
    objective_type: objectiveType,
    answer_schema: body.assessment_contract?.answer_schema ?? null,
    grading_strategy_id: body.assessment_contract?.grading_strategy_id ?? null,
    feedback_policy_id: feedbackPolicyId,
    numeric_rule: body.assessment_contract?.numeric_rule ?? null,
    combined_png_base64_length: combinedBase64.length,
    combined_png_sha256_prefix: imageHash
  }));

  const gradingEnvelope = await gradeWithRouter({
    concept_id: conceptId,
    grading_strategy_id: body.assessment_contract?.grading_strategy_id,
    answer_schema: body.assessment_contract?.answer_schema,
    expected_answer_kind: expectedAnswerKind,
    expected_answer_value: expectedAnswerValue,
    submitted_choice_id: body.submitted_choice_id,
    submitted_numeric_value: body.submitted_numeric_value,
    submitted_expression: body.submitted_expression,
    submitted_text: body.submitted_text,
    numeric_rule: body.assessment_contract?.numeric_rule,
    visual_target_evaluator: async () => evaluateVisualTarget({
      conceptId,
      promptText,
      interactionType,
      responseMode,
      rightAngleAt,
      combinedBase64,
      expectedAnswerValue,
      expectedAnswerKind
    }),
    rubric_evaluator: async () => evaluateRubricLLM({
      submittedText: body.submitted_text,
      expectedAnswerValue
    })
  });

  const response = toLegacyResponse(gradingEnvelope, {
    conceptId,
    objectiveType,
    expectedAnswer: expectedAnswerValue,
    noAnswerLeakage: !/allow_answer_leak/i.test(feedbackPolicyId)
  });
  console.log("[API][Check][Response]", JSON.stringify(response));
  return jsonResponse(response, 200);
}

function toLegacyResponse(
  envelope: GradingResultEnvelope,
  config: { conceptId: string; objectiveType: string; expectedAnswer: string; noAnswerLeakage: boolean }
) {
  const detected = envelope.detected_answer.value == null ? null : String(envelope.detected_answer.value);
  const correctness = envelope.correctness === "correct";
  const feedback = buildStudentFeedback(envelope, {
    conceptId: config.conceptId,
    objectiveType: config.objectiveType,
    expectedAnswer: config.expectedAnswer,
    detectedAnswer: detected,
    noAnswerLeakage: config.noAnswerLeakage
  });

  return {
    detected_segment: detected,
    detected_target: detected,
    ambiguity_score: envelope.correctness === "ambiguous" ? 1 : 0,
    confidence: envelope.confidence,
    reason_codes: envelope.ambiguity_codes,
    student_feedback: feedback.message,
    feedback_metadata: feedback,
    grading_result: envelope,
    correctness
  };
}

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

function buildStudentFeedback(envelope: GradingResultEnvelope, context: FeedbackContext): FeedbackMetadata {
  const vocab = resolveObjectiveVocabulary(context.objectiveType, envelope.detected_answer.kind);
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

  const detected = context.detectedAnswer ?? "no clear answer";
  const mismatchText = `I detected ${detected}. The prompt asks for a ${vocab.targetType}, so this does not match the prompt intent.`;
  const hints = `${vocab.boundedHints[0]} ${vocab.boundedHints[1]}`;
  const answerLeak = context.noAnswerLeakage ? "" : ` The correct answer is ${context.expectedAnswer}.`;

  return {
    message: `${mismatchText} ${hints}${answerLeak}`,
    hint_level: 2,
    remediation_tag: "incorrect_with_bounded_hints",
    next_action: envelope.correctness === "error" ? "scaffold" : "retry"
  };
}

async function evaluateVisualTarget(input: {
  conceptId: string;
  promptText: string;
  interactionType: string;
  responseMode: string;
  rightAngleAt: "A" | "B" | "C" | null;
  combinedBase64: string;
  expectedAnswerValue: string;
  expectedAnswerKind: string | null;
}): Promise<GradingResultEnvelope> {
  if (!process.env.OPENAI_API_KEY) {
    return errorEnvelope("MISSING_OPENAI_API_KEY", "Server misconfigured (missing API key).", "visual_target_locator");
  }

  try {
    const header = `Concept: ${input.conceptId}\nPrompt: ${input.promptText}\nInteractionType: ${input.interactionType}\nResponseMode: ${input.responseMode}\nRightAngleAt: ${input.rightAngleAt ?? "null"}`;
    const fullPrompt = `${header}\n\n${PROMPT}`;

    const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
    const detectResponse = await client.responses.create({
      model: "gpt-4.1",
      input: [
        {
          role: "user",
          content: [
            { type: "input_text", text: fullPrompt },
            {
              type: "input_image",
              image_url: `data:image/png;base64,${input.combinedBase64}`,
              detail: "high"
            }
          ]
        }
      ]
    });

    const parsed = safeParseJson(detectResponse.output_text || "");
    if (!parsed) {
      return errorEnvelope("VISION_PARSE_FAILED", "Vision model returned invalid JSON.", "visual_target_locator");
    }

    const detectedTargetClass = normalizeDiagramTargetClass(parsed?.detected_target_class ?? null) ?? "segments";
    const detected = normalizeDiagramTargetValue(detectedTargetClass, parsed?.detected_target ?? null);
    const ambiguity = typeof parsed?.ambiguity_score === "number" ? parsed.ambiguity_score : 1;
    const confidence = typeof parsed?.confidence === "number" ? parsed.confidence : 0;
    const reasonCodes = Array.isArray(parsed?.reason_codes) ? parsed.reason_codes : [];
    const expectedClass = expectedDiagramTargetClass(input.expectedAnswerKind, input.expectedAnswerValue);
    const expected = normalizeDiagramTargetValue(expectedClass, input.expectedAnswerValue);
    const sameClass = detectedTargetClass === expectedClass;

    const correctness = ambiguity >= 0.6
      ? "ambiguous"
      : detected && expected && sameClass && detected === expected
        ? "correct"
        : "incorrect";

    const feedback = await generateFeedback(client, {
      detected_target_class: detectedTargetClass,
      detected_target: detected,
      ambiguity_score: ambiguity
    }, expectedClass, input.expectedAnswerValue, input.promptText);

    return {
      strategy_family: "visual_target_locator",
      detected_answer: { kind: expectedClass === "segments" ? "segment" : "point_set", value: detected },
      correctness,
      confidence,
      ambiguity_codes: reasonCodes,
      evidence_summary: `visual_detection_class=${detectedTargetClass}; visual_detection_target=${detected ?? "null"}; expected_class=${expectedClass}; expected=${expected ?? "null"}; llm_feedback=${feedback}`
    };
  } catch (error) {
    console.error("[API][Check][VisualTargetError]", error);
    return errorEnvelope("VISION_GRADING_FAILED", "Visual grading failed.", "visual_target_locator");
  }
}

async function evaluateRubricLLM(input: {
  submittedText?: string;
  expectedAnswerValue: string;
}): Promise<GradingResultEnvelope> {
  const text = input.submittedText?.trim() ?? "";
  if (!text) {
    return {
      strategy_family: "rubric_llm",
      detected_answer: { kind: "text", value: null },
      correctness: "ambiguous",
      confidence: 0,
      ambiguity_codes: ["MISSING_TEXT_RESPONSE"],
      evidence_summary: "Rubric grading requires short-text input, but none was provided."
    };
  }

  const expected = input.expectedAnswerValue.toLowerCase();
  const normalized = text.toLowerCase();
  const hasExpectedSignal = normalized.includes(expected.replace(/\s+/g, "")) || normalized.includes(expected);

  return {
    strategy_family: "rubric_llm",
    detected_answer: { kind: "text", value: text },
    correctness: hasExpectedSignal ? "correct" : "incorrect",
    confidence: hasExpectedSignal ? 0.75 : 0.55,
    ambiguity_codes: [],
    evidence_summary: hasExpectedSignal
      ? "Strict rubric keyword match passed against expected answer signal."
      : "Strict rubric keyword match did not find expected answer signal."
  };
}

function errorEnvelope(code: string, summary: string, strategy_family: GradingResultEnvelope["strategy_family"] = "rubric_llm"): GradingResultEnvelope {
  return {
    strategy_family,
    detected_answer: { kind: "unknown", value: null },
    correctness: "error",
    confidence: 0,
    ambiguity_codes: [code],
    evidence_summary: summary
  };
}

function safeParseJson(text: string) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function normalizeSegment(value: string | null | undefined): string | null {
  if (!value) return null;
  const cleaned = value.toUpperCase().trim();
  if (!/^[ABC]{2}$/.test(cleaned)) return cleaned;
  const sorted = cleaned.split("").sort().join("");
  if (sorted === "AB") return "AB";
  if (sorted === "AC") return "CA";
  if (sorted === "BC") return "BC";
  return cleaned;
}

function expectedDiagramTargetClass(expectedAnswerKind: string | null, expectedAnswerValue: string): DiagramTargetClass {
  const normalizedKind = expectedAnswerKind?.trim().toLowerCase() ?? "";
  if (normalizedKind === "segment") return "segments";
  if (normalizedKind === "point_set" || normalizedKind === "vertex") return "vertices";
  if (normalizedKind === "angle") return "angles";
  if (normalizedKind === "region" || normalizedKind === "enclosed_region") return "enclosed_regions";
  if (normalizedKind === "symbolic_mark") return "symbolic_marks";
  const normalized = expectedAnswerValue.trim();
  if (/^[ABC]$/i.test(normalized)) return "vertices";
  if (/^[ABC]{2}$/i.test(normalized)) return "segments";
  if (normalized.startsWith("∠") || /^angle/i.test(normalized)) return "angles";
  if (/^region_/i.test(normalized)) return "enclosed_regions";
  if (/^mark_/i.test(normalized)) return "symbolic_marks";
  return "segments";
}

function normalizeDiagramTargetValue(targetClass: DiagramTargetClass, value: string | null | undefined): string | null {
  if (!value) return null;
  const cleaned = value.trim();
  if (!cleaned) return null;
  if (targetClass === "segments") return normalizeSegment(cleaned);
  if (targetClass === "vertices") return cleaned.toUpperCase();
  return cleaned;
}

function jsonResponse(payload: unknown, status: number) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "Pragma": "no-cache",
      ...CORS_HEADERS
    }
  });
}

async function generateFeedback(
  client: OpenAI,
  validated: { detected_target_class: DiagramTargetClass; detected_target: string | null; ambiguity_score: number },
  expectedClass: DiagramTargetClass,
  expected: string,
  promptText: string
) {
  try {
    const payload = {
      detected_target_class: validated.detected_target_class,
      detected_target: validated.detected_target,
      expected_target_class: expectedClass,
      expected_answer_value: expected,
      ambiguity_score: validated.ambiguity_score,
      prompt_text: promptText
    };

    const response = await client.responses.create({
      model: "gpt-4.1-mini",
      input: [
        {
          role: "user",
          content: [
            { type: "input_text", text: FEEDBACK_PROMPT },
            { type: "input_text", text: JSON.stringify(payload) }
          ]
        }
      ]
    });

    const parsed = safeParseJson(response.output_text || "");
    if (parsed && typeof parsed.student_feedback === "string") {
      return parsed.student_feedback;
    }
  } catch (err) {
    console.error("OpenAI feedback error:", err);
  }

  if (validated.detected_target == null || validated.ambiguity_score >= 0.6) {
    return "I can't tell which target you selected—try marking just ONE target clearly.";
  }
  if (validated.detected_target_class !== expectedClass || normalizeDiagramTargetValue(validated.detected_target_class, validated.detected_target) !== normalizeDiagramTargetValue(expectedClass, expected)) {
    const detected = validated.detected_target ?? "that target";
    return `You selected ${detected}, but that's not correct for this question. Hint 1: use the right-angle marker and labels carefully. Hint 2: match your choice to what the prompt asks.`;
  }
  return "Great work—you matched the diagram to the prompt correctly. This skill helps with maps, building plans, and design sketches.";
}
