import OpenAI from "openai";
import crypto from "crypto";

const PROMPT = `You are SmartTutor’s AI geometry checker.

You will be given:
1) An image of a triangle diagram with labeled vertices A, B, C.
2) A student’s drawing over the triangle (arc/loop/circle).

Your task is to analyze the combined image and return exactly strict JSON with no extra text.

Hard rules:
- You must determine detected_segment ONLY from the ink on the image.
- Do NOT assume the student circled the correct answer.
- Report what was circled even if incorrect.

Determine:
- "detected_segment": which side the student circled ("AB", "BC", "CA"), or null if you cannot confidently determine a single side.
- "ambiguity_score": a float between 0 and 1 indicating how ambiguous the circle is (0 = very clear, 1 = completely ambiguous).
- "confidence": a float between 0 and 1 indicating your confidence that the detected side is correct.
- "reason_codes": an array of zero or more of these exact strings:
  ["NO_CLOSED_LOOP","MULTIPLE_SIDES_ENCLOSED","CIRCLE_NOT_NEAR_ANY_SIDE","INK_TOO_MESSY","UNCLEAR_DIAGRAM","OTHER"]
- "student_feedback": a concise feedback message appropriate for a Grade 4–6 student.

Interpretation rules:
- If there is no clear closed loop around a side, return detected_segment = null and include "NO_CLOSED_LOOP".
- If more than one side is enclosed by the loop, return detected_segment = null and include "MULTIPLE_SIDES_ENCLOSED".
- If the loop does not appear close to any side, include "CIRCLE_NOT_NEAR_ANY_SIDE".
- If the drawing is too messy to decide, include "INK_TOO_MESSY".
- If the triangle diagram itself is unclear or unlabeled, include "UNCLEAR_DIAGRAM".
- Only choose a detected_segment if a single side is enclosed clearly with low ambiguity.
- Never guess if ambiguous; return null.

Output must be strictly JSON with this exact object shape and nothing else:

{
  "detected_segment": "AB" | "BC" | "CA" | null,
  "ambiguity_score": number,
  "confidence": number,
  "reason_codes": [string],
  "student_feedback": string
}`;

const FEEDBACK_PROMPT = `You are SmartTutor’s AI geometry tutor. You are a fun high school math teacher who helps kids remember ideas.

You will be given:
- detected_segment: which side the student circled (or null).
- expected_answer_value: the expected answer value.
- ambiguity_score.
- prompt/context about the triangle.

Write a single short feedback message for a Grade 4–6 student.

Rules:
- If detected_segment is null OR ambiguity_score >= 0.6: ask the student to re-circle just ONE side clearly.
- If detected_segment is wrong:
  - Explicitly say their choice is not correct for the current question.
  - Mention the detected_segment (e.g., "You circled CA").
  - Provide layered hints in two short sentences aligned with the prompt/context.
  - Do NOT reveal the correct side label directly.
- If detected_segment is correct:
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

const ERROR_MISCONFIGURED = {
  detected_segment: null,
  ambiguity_score: 1,
  confidence: 0,
  reason_codes: ["OTHER"],
  student_feedback: "Server misconfigured (missing API key)."
};

const ERROR_AI_FAILED = {
  detected_segment: null,
  ambiguity_score: 1,
  confidence: 0,
  reason_codes: ["OTHER"],
  student_feedback: "(AI check failed) Please try again."
};

export const runtime = "nodejs";

export async function OPTIONS() {
  return new Response(null, { status: 204, headers: CORS_HEADERS });
}

export async function POST(request: Request) {
  if (!process.env.OPENAI_API_KEY) {
    return jsonResponse(ERROR_MISCONFIGURED, 500);
  }

  let body: {
    concept_id?: string;
    prompt_text?: string;
    interaction_type?: string;
    response_mode?: string;
    right_angle_at?: "A" | "B" | "C" | null;
    merged_image_path?: string;
    combined_png_base64?: string;
    expected_answer_value?: string;
  };

  try {
    body = await request.json();
  } catch {
    return jsonResponse(ERROR_AI_FAILED, 200);
  }

  const conceptId = body.concept_id ?? "";
  const promptText = body.prompt_text ?? "";
  const interactionType = body.interaction_type ?? "highlight";
  const responseMode = body.response_mode ?? interactionType;
  const rightAngleAt = body.right_angle_at ?? null;
  const mergedImagePath = body.merged_image_path ?? null;
  const combinedBase64 = body.combined_png_base64 ?? "";
  const expectedAnswerValue = body.expected_answer_value ?? "AB";

  const header = `Concept: ${conceptId}\nPrompt: ${promptText}\nInteractionType: ${interactionType}\nResponseMode: ${responseMode}\nRightAngleAt: ${rightAngleAt ?? "null"}`;
  const fullPrompt = `${header}\n\n${PROMPT}`;
  const imageHash = crypto.createHash("sha256").update(combinedBase64).digest("hex").slice(0, 12);
  console.log("[API][Check][Request]", JSON.stringify({
    concept_id: conceptId,
    interaction_type: interactionType,
    response_mode: responseMode,
    right_angle_at: rightAngleAt,
    merged_image_path: mergedImagePath,
    expected_answer_value: expectedAnswerValue,
    combined_png_base64_length: combinedBase64.length,
    combined_png_sha256_prefix: imageHash
  }));

  try {
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
              image_url: `data:image/png;base64,${combinedBase64}`,
              detail: "high"
            }
          ]
        }
      ]
    });

    const detectText = detectResponse.output_text || "";
    console.log("[API][Check][LLMDetectRaw]", detectText);
    const parsed = safeParseJson(detectText);
    if (!parsed) {
      console.log("[API][Check][LLMDetectParseFailed]");
      return jsonResponse(ERROR_AI_FAILED, 200);
    }

    const validated = validateResponse(parsed, expectedAnswerValue);
    const feedback = await generateFeedback(client, validated, expectedAnswerValue, promptText);
    const finalResponse = {
      ...validated,
      student_feedback: feedback
    };

    console.log("[API][Check][Response]", JSON.stringify(finalResponse));

    return jsonResponse(finalResponse, 200);
  } catch (err: unknown) {
    console.error("OpenAI error:", err);
    if (err && typeof err === "object" && "response" in err) {
      console.error("OpenAI error response:", (err as { response?: unknown }).response);
    }
    return jsonResponse(ERROR_AI_FAILED, 200);
  }
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

function validateResponse(parsed: any, expected: string) {
  const detected: string | null = parsed?.detected_segment ?? null;
  const ambiguity = typeof parsed?.ambiguity_score === "number" ? parsed.ambiguity_score : 1;
  const confidence = typeof parsed?.confidence === "number" ? parsed.confidence : 0;
  const reasonCodes = Array.isArray(parsed?.reason_codes) ? parsed.reason_codes : ["OTHER"];

  let finalDetected = normalizeSegment(detected);
  const normalizedExpected = normalizeSegment(expected);
  let overridden = false;

  if (ambiguity >= 0.6) {
    finalDetected = null;
  }

  if (finalDetected && !["AB", "BC", "CA"].includes(finalDetected)) {
    finalDetected = null;
  }

  console.log(`expected=${normalizedExpected ?? expected} ai_detected=${finalDetected ?? "null"} amb=${ambiguity} conf=${confidence} overridden_feedback=${overridden}`);

  return {
    detected_segment: finalDetected,
    ambiguity_score: ambiguity,
    confidence,
    reason_codes: reasonCodes,
    student_feedback: ""
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

async function generateFeedback(
  client: OpenAI,
  validated: { detected_segment: string | null; ambiguity_score: number },
  expected: string,
  promptText: string
) {
  try {
    const payload = {
      detected_segment: validated.detected_segment,
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

    const text = response.output_text || "";
    console.log("[API][Check][LLMFeedbackRaw]", text);
    const parsed = safeParseJson(text);
    if (parsed && typeof parsed.student_feedback === "string") {
      return parsed.student_feedback;
    }
  } catch (err) {
    console.error("OpenAI feedback error:", err);
  }

  if (validated.detected_segment == null || validated.ambiguity_score >= 0.6) {
    return "I can't tell which side you circled—try circling just ONE side clearly.";
  }
  if (normalizeSegment(validated.detected_segment) !== normalizeSegment(expected)) {
    const detected = validated.detected_segment ?? "that side";
    return `You circled ${detected}, but that's not correct for this question. Hint 1: use the right-angle marker and labels carefully. Hint 2: match your choice to what the prompt asks.`;
  }
  return "Great work—you matched the diagram to the prompt correctly. This skill helps with maps, building plans, and design sketches.";
}
