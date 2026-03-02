# PLANS.md — SmartTutor MVP Execution Plan

## Scope Guardrails (from PRD)
- MVP topic scope: **Geometry → Triangles (Grade 6)** up to **Pythagoras** only.
- Deterministic rendering is mandatory for diagrams/text/equations.
- LLM must output structured specs only; invalid output never reaches rendering.

---

## Milestone List

### M1 — Onboarding + Learner Session Initialization
**Status:** Implemented

**Goal:** Implement learner entry flow and initialize bounded Grade 6 triangle learning state.

**Build:**
- Grade selection flow (MVP constrained to Grade 6).
- Topic selection flow (Geometry → Triangles).
- Session initialization for:
  - concept graph state handle,
  - mastery state object,
  - difficulty ceiling.
- Deterministic default/restart session behavior.

**Files touched (planned):**
- `Features/Exercises/ExercisesHomeView.swift`
- `App/RootView.swift`
- `App/AppConfig.swift`
- `Features/Canvas/TriangleModels.swift` (only if state model extension is needed)

**Manual test steps:**
1. Launch app; confirm onboarding prompts for Grade + Topic.
2. Select Grade 6 + Triangles; verify session initializes without crash.
3. Force app restart; verify expected resume/reset behavior is deterministic.
4. Confirm no topic outside MVP scope is selectable.

**Acceptance criteria:**
- Grade/topic onboarding works end-to-end.
- Session state initializes required objects (concept/mastery/difficulty cap).
- Scope guardrail (Grade 6 triangles only) is enforced in UI and state.

---
**Implementation notes (2026-02-22):**
- Files touched:
  - `App/Session/LearnerSession.swift`
  - `App/Session/LearnerSessionStore.swift`
  - `Features/Onboarding/OnboardingFlowView.swift`
  - `Features/Onboarding/GradeSelectionView.swift`
  - `Features/Onboarding/TopicSelectionView.swift`
  - `App/SmartTutorApp.swift`
  - `App/RootView.swift`
  - `App/AppConfig.swift`
  - `Features/Exercises/ExercisesHomeView.swift`
  - `Features/Canvas/CanvasSandboxView.swift`
- UX direction updates (M1-scoped):
  - Post-onboarding and session-restore default route now lands directly on the learning canvas.
  - Learning Hub is now treated as a secondary screen that is reachable from the canvas.
- Manual test steps:
  1. Launch app with empty session data; verify onboarding appears and enforces Grade 6 + Geometry → Triangles.
  2. Complete onboarding; verify learner session is initialized and app routes directly to canvas by default.
  3. Relaunch app; verify session restores deterministically to canvas without returning to onboarding.
  4. Tap Reset in root toolbar; verify session clears and onboarding is shown again.
  5. From canvas, open Learning Hub via its secondary entry point; verify hub is reachable but not the default landing screen.

**Implementation notes (2026-02-22 — Learning Hub reframing):**
- Files touched:
  - `Features/Exercises/ExercisesHomeView.swift`
  - `Features/Canvas/CanvasSandboxView.swift`
  - `App/RootView.swift`
- Manual test steps:
  1. Launch with an existing learner session; verify canvas is now the first post-onboarding screen.
  2. From canvas toolbar, tap **Learning Hub** and verify navigation opens the repurposed hub screen.
  3. In Learning Hub, verify learner-facing sections and compact diagnostics (grade/topic/concept graph) are visible.
  4. Tap **Continue Learning** and verify it returns to canvas.
  5. Confirm hub only shows Grade 6 + Geometry → Triangles scope text with no out-of-scope options.

**Implementation notes (2026-02-22 — Learning Hub reframing):**
- Files touched:
  - `Features/Exercises/ExercisesHomeView.swift`
  - `Features/Canvas/CanvasSandboxView.swift`
  - `App/RootView.swift`
- Manual test steps:
  1. Launch with an existing learner session; verify canvas is now the first post-onboarding screen.
  2. From canvas toolbar, tap **Learning Hub** and verify navigation opens the repurposed hub screen.
  3. In Learning Hub, verify learner-facing sections and compact diagnostics (grade/topic/concept graph) are visible.
  4. Tap **Continue Learning** and verify it returns to canvas.
  5. Confirm hub only shows Grade 6 + Geometry → Triangles scope text with no out-of-scope options.


**Implementation notes (2026-02-22 — Canvas navigation drawer cleanup):**
- Files touched:
  - `App/RootView.swift`
  - `Features/Canvas/CanvasSandboxView.swift`
- Manual test steps:
  1. Launch with an existing learner session and verify the screen title reads **Smart Tutor** (not Canvas).
  2. Confirm the chat pane no longer shows the **AI Math Tutor** heading above the chat area.
  3. Tap the hamburger icon in the top-right and verify a right-side navigation drawer appears.
  4. In the drawer, open **Learning Hub** and verify navigation works.
  5. In the drawer, toggle **Show Logs/Hide Logs** and verify the log overlay visibility updates.
  6. Use **Reset Session** from the drawer and verify onboarding is shown again.

**Implementation notes (2026-02-22 — Canvas menu consolidation):**
- Files touched:
  - `Features/Canvas/CanvasSandboxView.swift`
  - `App/RootView.swift`
- Manual test steps:
  1. Launch with an existing learner session and verify canvas layout has no duplicate top-level Learning Hub/Logs actions.
  2. Tap the hamburger menu in canvas toolbar and verify **Learning Hub** and **Show Logs/Hide Logs** are available there.
  3. Open **Learning Hub** from hamburger menu; verify hub navigation still works.
  4. Open logs from hamburger menu; verify overlay appears and can be closed via the overlay **Close** action.
  5. Confirm chat and canvas visible area is increased by removing always-visible Logs pill and extra title action.

---

---
**Implementation notes (2026-02-22, direct-to-canvas routing):**
- Files touched:
  - `App/RootView.swift`
  - `Features/Canvas/CanvasSandboxView.swift`
- Manual test steps:
  1. Launch with no persisted learner session; verify onboarding is shown.
  2. Complete onboarding; verify root routes directly to `CanvasSandboxView`.
  3. Relaunch app with persisted session; verify it opens directly on canvas again.
  4. Use canvas Reset toolbar button; verify `sessionStore.resetSession()` returns to onboarding deterministically.
  5. In canvas, load a question and run check-answer flow; verify tutor + grading interactions still work.

### M2 — Curriculum Graph + Mastery Engine (Deterministic Rails)
**Goal:** Implement concept progression and mastery as one integrated deterministic system.

**Build:**
- Encode Level 1–5 concept graph from PRD:
  1. Triangle & Angle Basics
  2. Right Triangle Structure
  3. Properties & Reasoning
  4. Pythagorean Theorem
  5. Applications
- Per-concept mastery rule:
  - `correct_count >= N` (configurable, default 3), and
  - required difficulty achieved.
- Difficulty adaptation:
  - increase on success,
  - lower on failure,
  - trigger remediation.
- Level unlock threshold by mastered sub-concept percentage.
- Hard cap at Grade 6 difficulty ceiling.

**Files touched (planned):**
- `Features/Canvas/TriangleModels.swift`
- `Features/Canvas/CanvasSandboxView.swift`
- `App/AppConfig.swift`
- `SmartTutorTests/SmartTutorTests.swift`

**Manual test steps:**
1. Complete repeated attempts on one concept; verify mastery increments only under rule.
2. Answer incorrectly; verify difficulty lowers and remediation path appears.
3. Reach mastery threshold; verify next concept unlocks deterministically.
4. Attempt to exceed grade ceiling; verify cap is enforced.

**Acceptance criteria:**
- Concept graph traversal is deterministic and prerequisite-gated.
- Mastery logic and progression are inseparable and implemented in one flow.
- Unlocking and adaptation behavior match PRD rules.

---

### M3 — LLM Question Planner + Validation Layer
**Status:** Implemented

**Goal:** Add a validated LLM-driven question pipeline (generate + independently rate + accept/retry + fallback) while preserving M2 progression behavior.

**Build:**
- Added strict M3 JSON contracts in app/backend:
  - `QuestionSpec` (generator output)
  - `DifficultyRating` (independent rater output)
- Added `ValidatedLLMQuestionProvider` that orchestrates:
  1) generate candidate,
  2) deterministic validation,
  3) independent difficulty rating,
  4) accept/retry,
  5) fallback to `StubQuestionProvider`.
- Enforced deterministic hard gates:
  - ontology concept check (Triangles MVP only),
  - allowed interaction type,
  - Grade 6 cap checks,
  - diagram renderability checks,
  - answer/interaction compatibility checks.
- Added minimal telemetry logs for attempt/rating/reject/fallback.
- Preserved M2 rules: MasteryEngine progression/unlock logic unchanged.

**Files touched:**
- `Features/Canvas/TriangleModels.swift`
- `Features/Canvas/TriangleAPI.swift`
- `Features/Canvas/ValidatedLLMQuestionProvider.swift`
- `Features/Canvas/CanvasSandboxView.swift`
- `backend/app/lib/m3.ts`
- `backend/app/api/triangles/generate/route.ts`
- `backend/app/api/triangles/rate/route.ts`
- `SmartTutorTests/M3ValidationTests.swift`
- `PLANS.md`

**Manual test steps:**
1. Disable stub mode (`AppConfig.useStubQuestionProvider = false`) and generate a question; verify accepted candidate renders and grading flow still works.
2. Force malformed/invalid `QuestionSpec` from backend; verify retries occur and final fallback returns stub question with no crash.
3. Force out-of-scope concept or disallowed interaction type in generated payload; verify deterministic rejection and no renderer exposure.
4. Force difficulty mismatch (outside target band); verify reject/retry then accept or fallback.
5. Verify logs include: attempt index, rater overall/dimensions, reject reason, retries count, fallback flag.
6. Verify progression and unlocking behavior remains unchanged by completing mastery steps (M2 expectations still pass).

**Acceptance criteria:**
- Generator and rater outputs are strict-schema validated.
- Rater output is the source of truth for accept/retry decisions.
- Invalid/unsafe LLM outputs are blocked before renderer/grader.
- Retries and fallback are deterministic and bounded.
- M2 progression/unlock logic remains unchanged.

---

### M4 — Deterministic Rendering + MVP Interaction Modes
**Goal:** Deliver stable deterministic question rendering and complete 2–3 MVP interaction types.

**Build:**
- Deterministic diagram/equation renderer from validated spec.
- MVP interaction modes:
  - draw/highlight,
  - multiple choice,
  - numeric/formula input for Pythagoras.
- Input normalization for grading pipeline.

**Files touched (planned):**
- `Features/Canvas/TriangleDiagramView.swift`
- `Features/Canvas/CanvasSandboxView.swift`
- `Features/Canvas/ChatMessage.swift`
- `SmartTutorUITests/SmartTutorUITests.swift`

**Manual test steps:**
1. Render same spec multiple times; confirm identical output.
2. Solve one question in each interaction mode; ensure response capture works.
3. Rotate device/sim and re-open question; verify deterministic rendering persists.
4. Confirm unsupported interaction mode is rejected gracefully.

**Acceptance criteria:**
- At least 2 interaction modes complete;get 3 including numeric/formula.
- Rendering is deterministic and stable.
- Inputs are captured in grading-ready normalized format.

---

### M3.1 — Dynamic Contract + AI-First Grading Corrections (M3 scope hardening)
**Status:** In progress

**Goal:** Fix M3 experience regressions while staying within M3 scope: dynamic generation verification, concept-aligned feedback, canonical grading, and schema clean-cut to v2 contracts.

**Build:**
- M3.1a:
  - Switch default runtime to validated LLM question provider (stub disabled by default).
  - Remove hardcoded hypotenuse context in AI check request path; pass dynamic concept/prompt/interaction metadata.
  - Make fallback feedback language concept-agnostic.
- M3.1b:
  - Canonical segment normalization (`AB == BA`, `BC == CB`, `CA == AC`) before correctness checks.
  - Keep AI-first grading decision; deterministic local signal remains telemetry/debug only.
- M3.1c:
  - Clean-cut schema migration to `m3.question_spec.v2` with `response_contract`.
  - Add mode-specific validation rails for highlight/multiple_choice/numeric_input.
  - Keep current canvas runtime constrained to highlight interaction until M4 UI modes are implemented.
- M3.1d:
  - Add per-concept contract table in backend LLM generator (objective, answer kinds, interaction types, phrasing bans, variation minimums).
  - Inject selected concept contract into the `generateWithLLM` prompt before OpenAI call.
  - Require question-family rotation across repeated attempts (diagram labeling/statement validation/scenario-based/etc.).

**Files touched:**
- `App/AppConfig.swift`
- `Features/Canvas/TriangleModels.swift`
- `Features/Canvas/ValidatedLLMQuestionProvider.swift`
- `Features/Canvas/CanvasSandboxView.swift`
- `Features/Canvas/TriangleAIChecker.swift`
- `backend/app/lib/m3.ts`
- `backend/app/api/triangles/check/route.ts`
- `SmartTutorTests/M3ValidationTests.swift`
- `backend/README.md`
- `PLANS.md`

**Manual test steps:**
1. Launch app with API configured; generate multiple questions and verify validated LLM pipeline is active by default.
2. Check answer on a non-hypotenuse prompt and verify tutor feedback aligns with prompt context (no fixed hypotenuse language).
3. Validate `expected=BC` and AI `detected=CB` is graded as correct after canonical normalization.
4. Force malformed v2 payload (`response_contract` mismatch) and confirm deterministic validator rejection before render.
5. Confirm app still operates in highlight mode only (M3 scope), with schema v2 accepted end-to-end.
6. For the same concept+difficulty over multiple attempts, verify prompt logs/specs show varied question family and no prohibited generic phrasing.

**Acceptance criteria:**
- Dynamic question generation path is active by default in app runtime.
- AI feedback is context-aware and no longer hardcoded to hypotenuse.
- Canonical segment labels prevent false negatives (`CB` vs `BC`).
- Schema v2 (`response_contract`) is enforced in app and backend validators.
- M3 scope preserved; deferred UI modes are captured as TODO.

**TODO (deferred to M4):**
- Implement first-class UI capture/rendering for `multiple_choice` and `numeric_input` in canvas tutor flow.
- Add deterministic grading paths for non-highlight interactions in-app.
- Add equation-input interaction mode once M4 renderer/input layer is live.

---

### M5 — Grading Arbitration + Tutor Feedback Loop
**Goal:** Provide robust grading outcomes with confidence/ambiguity control and age-appropriate feedback.

**Build:**
- Vision grading path for draw/highlight.
- Deterministic grading paths for MCQ/numeric.
- Ambiguity/confidence arbitration policy.
- Feedback response contract includes:
  - correctness,
  - encouragement,
  - conceptual explanation,
  - hints on incorrect/ambiguous responses,
  - real-world tie-in.

**Files touched (planned):**
- `Features/Canvas/VisionPipeline.swift`
- `Features/Canvas/TriangleAIChecker.swift`
- `backend/app/api/triangles/check/route.ts`
- `SmartTutorTests/VisionPipelineTests.swift`

**Manual test steps:**
1. Submit clean highlight; verify correct detection and confidence handling.
2. Submit ambiguous ink; verify re-attempt guidance is returned.
3. Submit wrong answer in each mode; vefy hinting style and no answer leakage policy.
4. Submit correct answer; verify concise praise + practical real-world context.

**Acceptance criteria:**
- Grading is reliable across supported input modes.
- Ambiguity policy prevents overconfident misgrading.
- Feedback tone and structure match PRD tutor constraints.

---

### M6 — Lesson Loop Orchestration + Progress/Gamification
**Goal:** Close the end-to-end adaptive loop and expose learner progress.

**Build:**
- End-to-end cycle:
  1. generate question,
  2. render,
  3. collect response,
  4. grade,
  5. tutor feedback,
  6. mastery update,
  7. branch (harder/remedial/unlock).
- Progress UI:
  - concept mastery bar (0→N, red/yellow/green),
  - topic completion graph (locked/unlocked, % completion).
- Rewards:
  - XP,
  - streak bonus,
  - concept mastered badge.
- Completion and transitiontes for topic end.

**Files touched (planned):**
- `Features/Exercises/ExercisesHomeView.swift`
- `Features/Canvas/CanvasSandboxView.swift`
- `App/RootView.swift`
- `SmartTutorUITests/SmartTutorUITests.swift`

**Manual test steps:**
1. Complete a concept and verify mastery bar and XP increment.
2. Maintain streak and verify bonus behavior.
3. Cross unlock threshold and verify completion graph node transitions.
4. Complete topic path and verify final state is shown.

**Acceptance criteria:**
- Full adaptive lesson loop runs without dead ends.
- Progress and gamification reflect real mastery state.
- Unlock/remediation branching follows deterministic rules.

---

### M7 — MVP Hardening + Success Metrics Readiness
**Goal:** Validate MVP behavior against PRD outcomes and prepare release baseline.

**Build:**
- Instrument events for:
  - completion funnel,
  - ambiguity/grading errors,
  - coept progression and churn.
- Add QA checklist for all milestone acceptance criteria.
- Publish readiness report against PRD success metrics.

**Files touched (planned):**
- `backend/README.md`
- `SmartTutorTests/SmartTutorTests.swift`
- `SmartTutorUITests/SmartTutorUITestsLaunchTests.swift`
- `todo.md` (only if used as execution checklist mirror)

**Manual test steps:**
1. Run scripted happy-path from onboarding to topic completion.
2. Run ambiguity-heavy path and confirm grading error handling.
3. Export/log metric counters and verify expected fields exist.
4. Validate no out-of-scope topic/grade path is reachable.

**Acceptance criteria:**
- Metrics instrumentation can evaluate PRD success thresholds.
- QA checklist passes for all in-scope MVP behaviors.
- MVP is release-ready for constrained pilot.

---

## Requirement → Milestone Traceability

| PRD Requirement | Milestone(s) |
|---|---|
| Grade/topic onboarding + init state | M1 |
| Concept graph Levels 1–5 | M2 |
| Mastery threshold + adaptive difficulty + unlock gating | M2, M6 |
| LLM structured JSON constraints + validation | M3 |
| Deterministic rendering (diagram/text/equation) | M3, M4 |
| 2–3 interaction typ4 |
| Vision/input-based grading + confidence/ambiguity | M5 |
| Tutor-style explanation/hints/real-world context | M3, M5 |
| Lesson loop progression/remediation/unlock | M6 |
| Progress graph + gamification | M6 |
| MVP constraints (single topic, grade 6, no extra modules) | M1, M2, M7 |
| Success metrics readiness | M7 |

---

## Current Status (Repo-Based)

### Present foundations
- Basic app shell navigation exists (`Exercises`, `Canvas Sandbox`).
- Canvas and triangle diagram rendering components exist.
- Triangle payload models exist.
- Vision pipeline implementation and unit tests exist.
- Backend AI triangle check endpoint exists with structured response behavior.

### Gaps to close
- Onboarding flow is not yet implemented as full Grade/topic initialization.
- Integrated concept graph + mastery engine is not fully implemented.
- Strict LLM question-bundle contract/validator gate is not yet clearly centralized.
- Multi-mode interactions beyond draw/highlight are incomplete.
- End-to-end lesson orchestration with unlock/remediation is incomplete.
- Gamification/progress graph implementation is incomplete.
- Metrics instrumentation for PRD success thresholds is incomplete.

### Status estimate
- Current repo appears to be **foundation stage with partial M4/M5 building blocks**; sequence-critical work is M1 → M2 → M3 next.

---
**Implementation notes (2026-02-24, M2 deterministic mastery + stub/simulator):**
- Files touched:
  - `App/AppConfig.swift`
  - `App/Session/LearnerSession.swift`
  - `App/Session/LearnerSessionStore.swift`
  - `Features/Canvas/TriangleModels.swift`
  - `Features/Canvas/CanvasSandboxView.swift`
  - `Features/Canvas/CurriculumGraph.swift` (new)
  - `Features/Canvas/MasteryEngine.swift` (new)
  - `Features/Canvas/StubQuestionProvider.swift` (new)
  - `SmartTutorTests/MasteryEngineTests.swift` (new)
- Manual test steps:
  1. Launch app, complete onboarding with Grade 6 + Triangles, tap **New Question** and confirm a deterministic stub question is shown with concept + difficulty text.
  2. Draw/circle the expected side and tap **Check Answer** repeatedly; verify log overlay shows mastery counters and difficulty ramp.
  3. Answer incorrectly once; verify difficulty decreases and remediation is logged/selected next.
  4. Open hamburger menu and run **Run Mastery Simulator**; verify logs show scripted deterministic transitions and progression updates.
  5. Continue attempts until completion and verify completion message is displayed deterministically.

**Implementation notes (2026-02-25, logging observability for generate/check/rate pipeline):**
- Files touched:
  - `Features/Canvas/TriangleAPI.swift`
  - `Features/Canvas/TriangleAIChecker.swift`
  - `Features/Canvas/CanvasSandboxView.swift`
  - `backend/app/api/triangles/generate/route.ts`
  - `backend/app/api/triangles/check/route.ts`
  - `backend/app/api/triangles/rate/route.ts`
- Manual test steps:
  1. Generate a new question and verify client logs include full `/api/triangles/generate` request payload (concept, grade, target band/direction, allowed interaction types) and response JSON.
  2. Submit a highlighted answer and verify client logs include `/api/triangles/check` request payload with `merged_image_path` and redacted base64 length.
  3. Confirm server logs include check request metadata (hash/length/path), raw LLM detect output, raw LLM feedback output, and final response JSON.
  4. Trigger rating flow and verify client + server logs include `/api/triangles/rate` request and response summaries.
  5. Intentionally cause malformed payload in local testing and verify validation/error logs clearly identify failure stage and reasons.

**Implementation notes (2026-02-26, concept-to-interaction policy mapping for M3 generation):**
- Files touched:
  - `Features/Canvas/ValidatedLLMQuestionProvider.swift`
  - `SmartTutorTests/InteractionPolicyTests.swift` (new)
- Manual test steps:
  1. Run `xcodebuild test -scheme SmartTutor -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SmartTutorTests/InteractionPolicyTests` and verify policy mapping tests pass.
  2. Trigger question generation for a basics concept and inspect logs/request payload to confirm `allowed_interaction_types` includes `highlight` + `multiple_choice`.
  3. Trigger question generation for a Pythagoras concept and inspect logs/request payload to confirm `numeric_input` is included (with `highlight` only for relevant concepts).

**Implementation notes (2026-02-26 — M3.1 pipeline hardening for concept relevance & diversity):**
- Files touched:
  - `backend/app/lib/m3.ts`
  - `Features/Canvas/TriangleAPI.swift`
  - `Features/Canvas/TriangleModels.swift`
  - `Features/Canvas/ValidatedLLMQuestionProvider.swift`
  - `Features/Canvas/StubQuestionProvider.swift`
  - `Features/Canvas/CanvasSandboxView.swift`
  - `SmartTutorTests/InteractionPolicyTests.swift`
- Manual test steps:
  1. Launch app and generate questions across 3+ different concept IDs; verify prompt style changes by concept family (not only side selection).
  2. Force server fallback (disable API key) and confirm fallback questions still vary by concept and interaction mode.
  3. Answer several questions repeatedly in same concept; verify novelty rejects repeated families and rotates interaction types when possible.
  4. Relaunch app and generate a new question; verify learner context history persists and is sent in request payload.
  5. Run unit tests to confirm difficulty tolerance accepts near-target ratings and prevents avoidable fallback.

**Implementation notes (2026-02-26 — build break fixes):**
- Files touched:
  - `Features/Canvas/InteractionPolicy.swift`
  - `Features/Canvas/ValidatedLLMQuestionProvider.swift`
  - `Features/Canvas/VisionPipeline.swift`
  - `PLANS.md`
- Manual test steps:
  1. Build the app target and verify `StubQuestionProvider` resolves `InteractionPolicy` without compile errors.
  2. Trigger M3 telemetry logging path and verify the pipeline log string compiles and prints normally.
  3. Build non-iOS targets and verify `VisionPipeline` no longer emits a main-actor default-argument isolation error.

**Implementation notes (2026-02-26 — Assessment contract v1 end-to-end):**
- Files touched:
  - `Features/Canvas/TriangleModels.swift`
  - `Features/Canvas/ValidatedLLMQuestionProvider.swift`
  - `Features/Canvas/StubQuestionProvider.swift`
  - `Features/Canvas/TriangleAIChecker.swift`
  - `Features/Canvas/CanvasSandboxView.swift`
  - `Features/Canvas/TriangleAPI.swift`
  - `backend/app/lib/m3.ts`
  - `backend/app/api/triangles/generate/route.ts`
  - `backend/app/api/triangles/check/route.ts`
  - `SmartTutorTests/M3ValidationTests.swift`
- Manual test steps:
  1. Generate a question from `/api/triangles/generate` and verify `assessment_contract` is present with schema/objective/answer/grading/feedback fields.
  2. Trigger fallback question generation (e.g., disable API key) and verify fallback payload still includes `assessment_contract` plus mirrored `response_contract`.
  3. Submit multiple-choice and numeric answers via `/api/triangles/check`; verify deterministic grading reads `assessment_contract.expected_answer` and numeric tolerance from `assessment_contract.numeric_rule`.
  4. Submit a highlight answer with drawing; verify check payload includes full `assessment_contract` and feedback/correctness in app uses contract values.
  5. Run M3 validation tests and confirm answer/interaction validation gates now enforce assessment contract consistency.

**Implementation notes (2026-02-26 — VisionPipeline non-iOS compile guard fix):**
- Files touched:
  - `Features/Canvas/VisionPipeline.swift`
  - `PLANS.md`
- Manual test steps:
  1. Build SmartTutor target on macOS/iOS and verify `VisionPipeline.swift` no longer fails with “Missing return in static method expected to return 'VisionResult'`.
  2. Build non-iOS target path (or Swift typecheck in CI) and verify fallback `prepareAndSubmitVisionRequest` returns deterministic `UNSUPPORTED_PLATFORM` `VisionResult`.

**Implementation notes (2026-02-26 — Xcode target membership hardening for Canvas sources):**
- Files touched:
  - `SmartTutor.xcodeproj/project.pbxproj`
  - `scripts/check_xcodeproj_sources.sh`
  - `PLANS.md`
- Manual test steps:
  1. Open project in Xcode and verify `Features/Canvas/InteractionPolicy.swift` appears under the Canvas group with SmartTutor target membership.
  2. Build SmartTutor target and verify `ValidatedLLMQuestionProvider.swift` compiles without `Cannot find 'InteractionPolicy' in scope`.
  3. Run `scripts/check_xcodeproj_sources.sh` and verify the script reports success for file-reference and sources-build-phase coverage.

**Implementation notes (2026-02-26 — Backend central grading router + concept policy registry):**
- Files touched:
  - `backend/app/lib/gradingRouter.ts` (new)
  - `backend/app/api/triangles/check/route.ts`
  - `PLANS.md`
- Manual test steps:
  1. POST `/api/triangles/check` with `assessment_contract.grading_strategy_id="deterministic_rule"` + `answer_schema="enum"` and verify router selects `deterministic_choice` with normalized `grading_result` envelope.
  2. POST `/api/triangles/check` with numeric payload + `numeric_rule` (`tolerance`, optional range/unit) and verify `grading_result.detected_answer.kind="number"`, correctness, and evidence summary values.
  3. POST `/api/triangles/check` for `concept_id="tri.pyth.equation_a2_b2_c2"` and verify concept-policy fallback order prefers `symbolic_equivalence` then `deterministic_choice` then `rubric_llm`.
  4. POST `/api/triangles/check` with highlight payload and image to verify `visual_target_locator` strategy returns normalized envelope and legacy compatibility fields.

**Implementation notes (2026-02-26 — Two-stage grading interpretation/evaluation + shared diagram target taxonomy):**
- Files touched:
  - `backend/app/lib/gradingRouter.ts`
  - `backend/app/lib/diagramTargets.ts` (new)
  - `backend/app/api/triangles/check/route.ts`
  - `backend/app/lib/m3.ts`
  - `PLANS.md`
- Manual test steps:
  1. POST `/api/triangles/check` with `assessment_contract.grading_strategy_id="deterministic_rule"`, `answer_schema="enum"`, and `submitted_choice_id`; verify grading uses interpretation stage (`selected_option_id`) and deterministic evaluation result envelope remains stable.
  2. POST `/api/triangles/check` with numeric payload + tolerance; verify interpretation stage parses `submitted_numeric_value` and evaluation stage applies tolerance/range contract checks.
  3. POST `/api/triangles/check` with symbolic expression input and `answer_schema="expression_equivalence"`; verify interpretation stage parses equation string and evaluation stage canonicalizes before compare.
  4. POST `/api/triangles/check` with highlight payload where vision returns `detected_target_class` for each class (`vertices`, `segments`, `angles`, `enclosed_regions`, `symbolic_marks`) and verify normalized class labels flow through detection + grading evidence summary.
  5. Call `/api/triangles/generate` and inspect prompt construction logs to confirm diagram target taxonomy comes from shared `diagramTargets` definition.

**Implementation notes (2026-02-26 — Feedback policy mapping + structured feedback metadata):**
- Files touched:
  - `backend/app/api/triangles/check/route.ts`
  - `PLANS.md`
- Manual test steps:
  1. POST `/api/triangles/check` with incorrect multiple-choice/numeric submissions and verify feedback message states detected answer, explains mismatch with prompt intent, and includes bounded hints without answer leakage by default.
  2. POST `/api/triangles/check` with ambiguous submission (e.g., missing numeric/choice input) and verify feedback message requests a retry aligned to objective vocabulary (vertex/equation/number/segment/etc.).
  3. POST `/api/triangles/check` with correct submission and verify feedback gives concept-relevant reinforcement and `next_action="proceed"`.
  4. Verify response now includes `feedback_metadata` object with `message`, `hint_level`, `remediation_tag`, and `next_action` fields for all grading outcomes.
  5. Run backend build to confirm TypeScript compiles with no new errors.

**Implementation notes (2026-02-27 — Generation-time contract compatibility checks + grading benchmark harness):**
- Files touched:
  - `Features/Canvas/ValidatedLLMQuestionProvider.swift`
  - `SmartTutorTests/M3ValidationTests.swift`
  - `backend/app/lib/gradingRouter.ts`
  - `backend/app/lib/m3.ts`
  - `backend/app/lib/gradingBenchmark.ts`
  - `PLANS.md`
- Manual test steps:
  1. Trigger question generation with `objective_type="compute_value"` + `interaction_type="highlight"` and verify validation rejects with `objective_interaction_mismatch`/interaction mismatch.
  2. Trigger generation with `answer_schema="enum"` + `grading_strategy_id="symbolic_equivalence"` and verify validation rejects with `strategy_schema_mismatch`.
  3. Trigger generation for `tri.pyth.equation_a2_b2_c2` with disallowed strategy (for example `vision_locator`) and verify validation rejects with `concept_policy_strategy_mismatch`.
  4. Run benchmark harness against labeled cases (correct/incorrect/ambiguous/adversarial), including symbolic equation variants, numeric tolerance boundaries, and visual target classes; verify metrics output includes accuracy by concept/objective, ambiguity FP/FN, feedback quality flags, and strategy regression alerts.
