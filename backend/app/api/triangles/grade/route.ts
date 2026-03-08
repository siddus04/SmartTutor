import OpenAI from "openai";
import crypto from "crypto";
import { getIncorrectAttempts, recordOutcome } from "../../../lib/attemptStore";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization"
};

export const runtime = "nodejs";

export async function OPTIONS() {
  return new Response(null, { status: 204, headers: CORS_HEADERS });
}

const GRADE_PROMPT = `You are SmartTutor's AI grader + tutor for Grade 4–6 geometry.

You will receive structured JSON plus an optional image of the student's marked diagram.
Return ONLY strict JSON, with no extra text.

Tasks:
1) Identify what the student selected (detected_target, detected_target_class).
2) Decide correctness: "correct", "incorrect", or "ambiguous".
3) Provide short, contextual feedback and up to max_hints hints.
4) Only reveal the correct answer when reveal_answer=true.

Rules:
- Use the image to detect selections for highlight questions.
- Use submitted_choice_id / submitted_numeric_value / submitted_text for non-visual questions.
- If you cannot confidently detect a single target, set correctness="ambiguous".
- Do not reveal the correct answer unless reveal_answer=true.

Output JSON shape (exact keys, no extras):
{
  "detected_target_class": string | null,
  "detected_target": string | null,
  "ambiguity_score": number,
  "confidence": number,
  "correctness": "correct" | "incorrect" | "ambiguous",
  "student_feedback": string,
  "hints": [string],
  "reveal_answer": boolean,
  "correct_answer_explain": string | null
}`;

export async function POST(request: Request) {
  let body: {
    learner_id?: string;
    question_id?: string;
    concept_id?: string;
    prompt_text?: string;
    interaction_type?: string;
    diagram_spec?: Record<string, unknown>;
    diagram_cues?: Array<Record<string, unknown>>;
    assessment_contract?: {
      schema_version?: string;
      concept_id?: string;
      interaction_type?: string;
      objective_type?: string;
      answer_schema?: string;
      grading_strategy_id?: string;
      feedback_policy_id?: string;
      feedback_contract?: {
        skill_focus?: string;
        cue_types?: string[];
        hint_templates?: string[];
        feedback_style?: string;
        reveal_policy?: string;
      };
      expected_answer?: { kind?: string; value?: string };
      options?: Array<{ id?: string; text?: string }>;
      numeric_rule?: { tolerance?: number };
    };
    student_response?: {
      combined_png_base64?: string;
      submitted_choice_id?: string;
      submitted_numeric_value?: string;
      submitted_text?: string;
    };
  };

  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "invalid_request_body" }, 400);
  }

  const learnerId = (body.learner_id ?? "").trim();
  const questionId = (body.question_id ?? "").trim();
  if (!learnerId || !questionId) {
    return jsonResponse({ error: "missing_learner_or_question_id" }, 400);
  }

  if (!process.env.OPENAI_API_KEY) {
    return jsonResponse({ error: "missing_openai_api_key" }, 500);
  }

  const attemptCount = getIncorrectAttempts(learnerId, questionId);
  const allowAnswerReveal = true;
  const revealAfterAttempts = 2;
  const maxHints = 2;

  const promptText = body.prompt_text ?? "";
  const interactionType = body.interaction_type ?? body.assessment_contract?.interaction_type ?? "highlight";
  const expectedAnswerValue = body.assessment_contract?.expected_answer?.value ?? "";
  const expectedAnswerKind = body.assessment_contract?.expected_answer?.kind ?? "";

  const combinedBase64 = body.student_response?.combined_png_base64 ?? "";
  const imageHash = combinedBase64
    ? crypto.createHash("sha256").update(combinedBase64).digest("hex").slice(0, 12)
    : "none";

  console.log("[API][Grade][Request]", JSON.stringify({
    learner_id: learnerId,
    question_id: questionId,
    concept_id: body.concept_id ?? body.assessment_contract?.concept_id ?? null,
    interaction_type: interactionType,
    expected_answer_value: expectedAnswerValue,
    combined_png_base64_length: combinedBase64.length,
    combined_png_sha256_prefix: imageHash,
    attempt_count: attemptCount
  }));

  const payload = {
    question: {
      concept_id: body.concept_id ?? body.assessment_contract?.concept_id ?? "",
      prompt_text: promptText,
      interaction_type: interactionType,
      assessment_contract: body.assessment_contract ?? {},
      diagram_spec: body.diagram_spec ?? null,
      diagram_cues: body.diagram_cues ?? []
    },
    student_response: {
      submitted_choice_id: body.student_response?.submitted_choice_id ?? null,
      submitted_numeric_value: body.student_response?.submitted_numeric_value ?? null,
      submitted_text: body.student_response?.submitted_text ?? null
    },
    policy: {
      max_hints: maxHints,
      allow_answer_reveal: allowAnswerReveal,
      reveal_after_attempts: revealAfterAttempts,
      attempts_so_far: attemptCount
    },
    expected_answer: {
      kind: expectedAnswerKind,
      value: expectedAnswerValue
    }
  };

  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  let parsed: any = null;
  try {
    const content: Array<{ type: "input_text" | "input_image"; text?: string; image_url?: string; detail?: "low" | "high" }> = [
      { type: "input_text", text: GRADE_PROMPT },
      { type: "input_text", text: JSON.stringify(payload) }
    ];
    if (combinedBase64) {
      content.push({ type: "input_image", image_url: `data:image/png;base64,${combinedBase64}`, detail: "high" });
    }

    const response = await client.responses.create({
      model: "gpt-4.1",
      input: [{ role: "user", content }]
    });

    parsed = safeParseJson(response.output_text || "");
  } catch (error) {
    console.error("[API][Grade][LLMError]", error);
  }

  const normalized = normalizeGradeResponse(parsed);
  const shouldReveal = allowAnswerReveal
    && normalized.correctness !== "correct"
    && attemptCount + 1 >= revealAfterAttempts;

  const revealAnswer = shouldReveal;
  const correctExplain = revealAnswer
    ? (normalized.correct_answer_explain ?? `The correct answer is ${expectedAnswerValue}.`)
    : null;

  const hints = normalized.hints.slice(0, maxHints);

  const finalResponse = {
    detected_segment: normalized.detected_target,
    detected_target_class: normalized.detected_target_class,
    detected_target: normalized.detected_target,
    ambiguity_score: normalized.ambiguity_score,
    confidence: normalized.confidence,
    reason_codes: [],
    correctness: normalized.correctness,
    student_feedback: normalized.student_feedback,
    hints,
    reveal_answer: revealAnswer,
    correct_answer_explain: correctExplain
  };

  recordOutcome(learnerId, questionId, normalized.correctness);

  console.log("[API][Grade][Response]", JSON.stringify(finalResponse));
  return jsonResponse(finalResponse, 200);
}

function safeParseJson(text: string) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function normalizeGradeResponse(parsed: any): {
  detected_target_class: string | null;
  detected_target: string | null;
  ambiguity_score: number;
  confidence: number;
  correctness: "correct" | "incorrect" | "ambiguous";
  student_feedback: string;
  hints: string[];
  correct_answer_explain: string | null;
} {
  const detectedTarget = typeof parsed?.detected_target === "string" ? parsed.detected_target : null;
  const detectedClass = typeof parsed?.detected_target_class === "string" ? parsed.detected_target_class : null;
  const ambiguity = typeof parsed?.ambiguity_score === "number" ? parsed.ambiguity_score : 1;
  const confidence = typeof parsed?.confidence === "number" ? parsed.confidence : 0;
  const correctness: "correct" | "incorrect" | "ambiguous" =
    parsed?.correctness === "correct" || parsed?.correctness === "incorrect" || parsed?.correctness === "ambiguous"
      ? parsed.correctness
      : "ambiguous";
  const studentFeedback = typeof parsed?.student_feedback === "string"
    ? parsed.student_feedback
    : "I couldn't read a clear response yet. Try again with one clear answer.";
  const hints = Array.isArray(parsed?.hints)
    ? parsed.hints.filter((value: unknown): value is string => typeof value === "string")
    : [];
  const explain = typeof parsed?.correct_answer_explain === "string" ? parsed.correct_answer_explain : null;

  return {
    detected_target_class: detectedClass,
    detected_target: detectedTarget,
    ambiguity_score: ambiguity,
    confidence,
    correctness,
    student_feedback: studentFeedback,
    hints,
    correct_answer_explain: explain
  };
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
