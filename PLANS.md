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
  - trigger remediat unlock threshold by mastered sub-concept percentage.
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

### M3 — LLM Contract + Validation Gate (Before Interaction Expansion)
**Goal:** Lock strict LLM schema/validation so only safe, in-scope structured specs can drive UX.

**Build:**
- Definstrict JSON contracts for question bundle:
  - diagram spec,
  - question prompt,
  - answer key,
  - hints,
  - explanation,
  - real-world application,
  - interaction mode.
- Add schema validation + sanitization + fallback policy.
- Add ontology guardrails (triangles-only, no conceptual leap beyond current concept/grade).
- Ensure invalid LLM output is rejected before rendering/grading.

**Files touched (planned):**
- `backend/app/api/triangles/check/route.ts`
- `Features/Canvas/TriangleAPI.swift`
- `Features/Canvas/TriangleModels.swift`
- `SmartTutorTests/SmartTutorTests.swift`

**Manual test steps:**
1. Send valid schema payload; verify render pipeline accepts it.
2. Send malformed JSON/missing fields; verify fallback response and no crash.
3. Send out-of-scope concept prompt; verify block/rewrite behavior.
4. Confirm deterministic mapping from validated spec to rendered output.

**Acceptance criteria:**
- Strict schema gate exists and is enforced.
- No unvalidated LLM output reaches UI rendering.
- Out-of-scope concepts are blocked per PRD scope.

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
