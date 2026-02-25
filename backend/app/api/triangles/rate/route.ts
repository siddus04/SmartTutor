import { rateWithLLM, validateDifficultyRating, validateQuestionSpec, type QuestionSpec } from "../../../lib/m3";

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
      question_spec?: QuestionSpec;
      grade?: number;
    };
    const questionSpec = body.question_spec;
    if (!questionSpec) {
      return jsonResponse({ error: "missing_question_spec" }, 400);
    }

    console.log("[API][Rate][Request]", JSON.stringify({
      grade: body.grade ?? 6,
      question_id: questionSpec.question_id,
      concept_id: questionSpec.concept_id,
      interaction_type: questionSpec.interaction_type
    }));

    const questionErrors = validateQuestionSpec(questionSpec, ["highlight", "multiple_choice", "numeric_input"]);
    if (questionErrors.length > 0) {
      console.log("[API][Rate][ValidationFailed]", JSON.stringify({ reasons: questionErrors }));
      return jsonResponse({ error: "invalid_question_spec", reasons: questionErrors }, 422);
    }

    const rating = await rateWithLLM(questionSpec, body.grade ?? 6);
    const ratingErrors = validateDifficultyRating(rating);
    if (ratingErrors.length > 0) {
      console.log("[API][Rate][RatingValidationFailed]", JSON.stringify({ reasons: ratingErrors }));
      return jsonResponse({ error: "invalid_difficulty_rating", reasons: ratingErrors }, 422);
    }

    console.log("[API][Rate][Response]", JSON.stringify({
      overall: rating.overall,
      grade_fit_ok: rating.grade_fit.ok,
      flags: rating.flags
    }));

    return jsonResponse(rating, 200);
  } catch (error: unknown) {
    console.error("[API][Rate][Error]", error);
    return jsonResponse({ error: "rating_failed" }, 500);
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
