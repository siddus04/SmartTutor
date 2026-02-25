import { InvalidQuestionSpecError, generateWithLLM, normalizeLearnerContext, validateNovelty, validateQuestionSpec } from "../../../lib/m3";

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
      learner_context?: Record<string, unknown>;
    };

    const conceptId = body.concept_id ?? "tri.structure.hypotenuse";
    const grade = body.grade ?? 6;
    const allowed = body.allowed_interaction_types ?? ["highlight", "multiple_choice"];
    const learnerContext = normalizeLearnerContext(body.learner_context);
    const targetBand = body.target_band?.min != null && body.target_band?.max != null
      ? { min: body.target_band.min, max: body.target_band.max }
      : undefined;

    console.log("[API][Generate][Request]", JSON.stringify({
      concept_id: conceptId,
      grade,
      target_band: targetBand ?? null,
      target_direction: body.target_direction ?? null,
      allowed_interaction_types: allowed,
      learner_context: learnerContext
    }));

    const questionSpec = await generateWithLLM({
      conceptId,
      grade,
      allowedInteractionTypes: allowed,
      targetBand,
      targetDirection: body.target_direction,
      learnerContext
    });

    const errors = validateQuestionSpec(questionSpec, allowed);
    const noveltyErrors = validateNovelty(questionSpec, learnerContext);
    const allErrors = [...errors, ...noveltyErrors];
    if (allErrors.length > 0) {
      console.log("[API][Generate][ValidationFailed]", JSON.stringify({ concept_id: conceptId, reasons: allErrors }));
      return jsonResponse({ error: "invalid_question_spec", reasons: allErrors }, 422);
    }

    console.log("[API][Generate][Response]", JSON.stringify({
      question_id: questionSpec.question_id,
      concept_id: questionSpec.concept_id,
      interaction_type: questionSpec.interaction_type,
      difficulty: questionSpec.difficulty_metadata?.generator_self_rating,
      response_mode: questionSpec.response_contract?.mode
    }));

    return jsonResponse({ question_spec: questionSpec }, 200);
  } catch (error: unknown) {
    if (error instanceof InvalidQuestionSpecError) {
      console.log("[API][Generate][SemanticValidationFailed]", JSON.stringify({ reasons: error.reasons }));
      return jsonResponse({ error: "invalid_question_spec", reasons: error.reasons }, 422);
    }
    console.error("[API][Generate][Error]", error);
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
