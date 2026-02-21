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
- student_feedback must be consistent with detected_segment and expected_answer_segment.
- If detected_segment is wrong, provide a hint but do NOT give the answer directly.
- Never reveal the correct side explicitly, even if you know expected_answer_segment.
- If ambiguous (detected_segment = null or ambiguity_score >= 0.6), ask to re-circle just ONE side clearly.
- If detected_segment equals expected_answer_segment, give positive feedback and include one brief, memorable fact about the concept.

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
    concept?: string;
    task?: string;
    right_angle_at?: "A" | "B" | "C" | null;
    combined_png_base64?: string;
    expected_answer_segment?: "AB" | "BC" | "CA";
  };

  try {
    body = await request.json();
  } catch {
    return jsonResponse(ERROR_AI_FAILED, 200);
  }

  const concept = body.concept ?? "";
  const task = body.task ?? "";
  const rightAngleAt = body.right_angle_at ?? null;
  const combinedBase64 = body.combined_png_base64 ?? "";
  const expectedAnswerSegment = body.expected_answer_segment ?? "AB";

  const header = `Concept: ${concept}\nTask: ${task}\nRightAngleAt: ${rightAngleAt ?? "null"}\nExpectedAnswerSegment: ${expectedAnswerSegment}`;
  const fullPrompt = `${header}\n\n${PROMPT}`;
  const imageHash = crypto.createHash("sha256").update(combinedBase64).digest("hex").slice(0, 12);
  console.log(`AI check request hash=${imageHash}`);

  try {
    const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
    const response = await client.responses.create({
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

    const text = response.output_text || "";
    const parsed = safeParseJson(text);
    if (!parsed) {
      return jsonResponse(ERROR_AI_FAILED, 200);
    }

    const validated = validateResponse(parsed, expectedAnswerSegment);
    return jsonResponse(validated, 200);
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

function validateResponse(parsed: any, expected: "AB" | "BC" | "CA") {
  const detected: string | null = parsed?.detected_segment ?? null;
  const ambiguity = typeof parsed?.ambiguity_score === "number" ? parsed.ambiguity_score : 1;
  const confidence = typeof parsed?.confidence === "number" ? parsed.confidence : 0;
  const reasonCodes = Array.isArray(parsed?.reason_codes) ? parsed.reason_codes : ["OTHER"];
  let feedback = typeof parsed?.student_feedback === "string" ? parsed.student_feedback : "";

  let finalDetected = detected;
  let overridden = false;

  if (ambiguity >= 0.6) {
    finalDetected = null;
  }

  if (!finalDetected) {
    const lower = feedback.toLowerCase();
    if (!lower.includes("circle") && !lower.includes("circled")) {
      feedback = "I can’t tell which side you circled—try circling just ONE side clearly.";
      overridden = true;
    }
  } else {
    const lower = feedback.toLowerCase();
    if (finalDetected === expected) {
      const looksNegative = lower.includes("try") || lower.includes("not quite") || lower.includes("make sure") || lower.includes("re-circle") || lower.includes("recircle");
      const hasPositive = lower.includes("good") || lower.includes("great") || lower.includes("nice") || lower.includes("correct") || lower.includes("well done");
      if (looksNegative || !hasPositive) {
        feedback = "Good job! The hypotenuse is always the longest side, opposite the right angle.";
        overridden = true;
      }
    } else {
      const looksPositive = lower.includes("good job") || lower.includes("correct") || lower.includes("well done");
      if (looksPositive || !lower.includes("opposite")) {
        feedback = "Good try. Make sure you circle the side opposite the right angle.";
        overridden = true;
      }
    }
  }

  console.log(
    `expected=${expected} ai_detected=${finalDetected ?? "null"} amb=${ambiguity} conf=${confidence} overridden_feedback=${overridden}`
  );

  return {
    detected_segment: finalDetected,
    ambiguity_score: ambiguity,
    confidence,
    reason_codes: reasonCodes,
    student_feedback: feedback
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
