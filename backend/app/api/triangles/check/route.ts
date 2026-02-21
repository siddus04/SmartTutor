import OpenAI from "openai";

const PROMPT = `You are SmartTutor’s AI geometry checker.

You will be given:
1) An image of a triangle diagram with labeled vertices A, B, C.
2) A student’s drawing over the triangle (arc/loop/circle).

Your task is to analyze the combined image and return exactly strict JSON with no extra text.

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

  const header = `Concept: ${concept}\nTask: ${task}\nRightAngleAt: ${rightAngleAt ?? "null"}`;
  const fullPrompt = `${header}\n\n${PROMPT}`;

  try {
    const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
    const response = await client.responses.create({
      model: "gpt-4.1-mini",
      input: [
        {
          role: "user",
          content: [
            { type: "input_text", text: fullPrompt },
            {
              type: "input_image",
              image_url: `data:image/png;base64,${combinedBase64}`,
              detail: "auto"
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

    return jsonResponse(parsed, 200);
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

function jsonResponse(payload: unknown, status: number) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...CORS_HEADERS
    }
  });
}
