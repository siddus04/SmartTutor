import { generateWithLLM, validateQuestionSpec } from "../../../lib/m3";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization"
};

export const runtime = "nodejs";

export async function OPTIONS() {
  return new Response(null, { status: 204, headers: CORS_HEADERS });
}

export async function POST(request: Request) {
  try {
    const body = await request.json() as {
      concept_id?: string;
      grade?: number;
      target_band?: { min?: number; max?: number };
      target_direction?: string;
      allowed_interaction_types?: string[];
    };

    const conceptId = body.concept_id ?? "tri.structure.hypotenuse";
    const grade = body.grade ?? 6;
    const allowed = body.allowed_interaction_types ?? ["highlight", "multiple_choice"];
    const targetBand = body.target_band?.min != null && body.target_band?.max != null
      ? { min: body.target_band.min, max: body.target_band.max }
      : undefined;

    const questionSpec = await generateWithLLM({
      conceptId,
      grade,
      allowedInteractionTypes: allowed,
      targetBand,
      targetDirection: body.target_direction
    });

    const errors = validateQuestionSpec(questionSpec, allowed);
    if (errors.length > 0) {
      return jsonResponse({ error: "invalid_question_spec", reasons: errors }, 422);
    }

    return jsonResponse({ question_spec: questionSpec }, 200);
  } catch {
    return jsonResponse({ error: "generation_failed" }, 500);
  }
}

function jsonResponse(payload: unknown, status: number) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      ...CORS_HEADERS
    }
  });
}
