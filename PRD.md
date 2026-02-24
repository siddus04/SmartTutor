//
//  PRD.md
//  SmartTutor
//
//  Created by Abhinav Gupta on 22/02/26.
//

SmartTutor MVP – Product Requirements Document
Topic: Geometry → Triangles (Grade 6 Focus)

1. Product Vision
SmartTutor is an AI-native, adaptive learning system that:
Teaches a complete topic end-to-end


Adapts to student mastery in real time


Uses dynamic LLM-generated instruction and assessment


Combines canvas-based interaction with conceptual tutoring


Tracks mastery via gamified progress metrics


The MVP focuses on:
Geometry → Triangles → Right-Angled Triangles → (Grade 6 appropriate ceiling e.g. Pythrogram theorem)

2. Target User
Grade 6 student


Onboarding includes:


Grade selection


Topic selection (Geometry → Triangles)


No prior assumption of triangle mastery
System initializes:
Concept graph limited to Grade 6 ceiling
Mastery tracking state
Difficulty cap appropriate for grade

3. Core Goals of MVP
Teach right-angled triangles end-to-end.


Gradually increase difficulty within grade constraints.


Require mastery before progression.


Provide conceptual + real-world explanations.


Track progress visually through gamification.



4. Scope of Content (Grade 6 – Right Triangles)
The system must teach the topic end-to-end within grade constraints.
Concept Graph (MVP Scope)
Level 1: Triangle & Angle Basics
  - Vertices, sides, angles
  - Identify right angle
  - Identify right-angled triangle

Objective:
Build structural awareness before introducing right triangle properties.

Level 2: Right Triangle Structure
  - Hypotenuse
  - Legs
  - Opposite / Adjacent (relative to angle)

Objective:
Build relational understanding inside right triangles.


Level 3: Properties & Reasoning
  - Hypotenuse is longest
  - Compare side lengths
  - Informal reasoning about side relationships

Objective:
Prepare cognitive bridge to Pythagorean relationship without formula.

Level 4: Pythagorean Theorem
  - Square numbers refresher
  - a² + b² = c²
  - Solve for missing side
  - Area-of-square intuition (conceptual setup)
  - Check if triangle is right-angled

Objective:
Develop computational and verification fluency.

Level 5: Applications
  - Word problems
  - Real-life modeling
  - Mixed mastery test

Objective:
Ensure transfer beyond isolated problem solving.



5. Adaptive Mastery Engine
5.1 Mastery Rule
For each concept:
Student must answer N correct questions (configurable, e.g., N = 3)


Questions must increase in difficulty


Confidence / ambiguity score must be above threshold


If student fails:


Difficulty lowers


Remedial explanation triggered


Progression only occurs when:
Correct_count >= N
AND
Difficulty_level >= required_level

Students must master a defined percentage of sub-concepts within a level before unlocking the next level.

5.2 Difficulty Levels (Per Concept)
Example for Hypotenuse:
Example: Hypotenuse
Level 1 – Clear right angle marker, labeled
Level 2 – Rotated triangle
Level 3 – Lengths shown
Level 4 – No right-angle marker; infer from lengths
Difficulty capped at Grade 6 ceiling.

6. LLM Role
6.1 LLM Responsibilities
The LLM acts as:
An enthusiastic high school tutor focused on conceptual clarity.
For each question it generates:
Diagram specification


Question prompt


Correct answer


Teaching explanation


Real-life application


Hint scaffolding


Tone:
Encouraging


Conceptual


Not rote-based


Builds reasoning


Age-appropriate



6.2 LLM Constraints
The LLM must:
Respect grade difficulty cap


Stay within ontology of triangles


Generate structured JSON


Avoid jumping ahead conceptually


Follow allowed interaction types


All outputs validated before rendering.

7. Interaction Types (Canvas-Supported)
MVP supports 2–3 modes:
Draw/highlight


Multiple choice (tap/select/draw or highlight)


Numeric or formulae input (for Pythagoras)


Combination of above


Future modes expandable.
Each interaction type must integrate with:
Deterministic rendering


Vision or input-based grading


Mastery tracking

8. Experience Flow
8.1 Onboarding
User selects:
Grade (e.g., Grade 6)


Topic (Geometry → Triangles)


System initializes:
Concept graph


Mastery tracking object


Difficulty ceiling



8.2 Lesson Loop
For each question:
LLM generates question (within constraints)


Diagram or equation along with options rendered on canvas deterministically


Student responds via canvas


Vision engine evaluates


AI tutor responds with:


The user’s answer and whether it is right or wrong


Encouragement


Concept explanation


Helpful hints in case of wrong answer


Real-world connection


Mastery updated


Either:


Next question (higher difficulty)


Remediation


Next concept unlocked



9. Gamification & Progress Tracking
9.1 Concept Mastery Bar
For each concept:
Progress indicator (0 → N mastery)


Color-coded strength (Red / Yellow / Green)


9.2 Topic Completion Graph
Visual:
Concept nodes connected in progression


Locked/unlocked indicators


Percentage completion


9.3 Rewards
XP per correct answer


Bonus for streak


“Concept Mastered” badge



10. System Architecture (MVP-Level)
Three Engines:
Learning Graph Engine


Determines next concept


Tracks mastery


Applies difficulty rules


LLM Planning Engine


Generates question + explanation


Returns structured JSON


Rendering + Grading Engine


Deterministic diagram render


Vision arbitration


Confidence scoring


Feedback



11. Constraints for MVP
Single topic only (Triangles)


Grade 6 only


2–3 interaction types


No multi-topic branching


No spaced repetition yet


No teacher dashboard yet



12. Success Metrics (MVP)
Product-level:
≥70% of students complete topic


≤15% ambiguity grading errors


≥80% concept mastery progression without churn


Learning-level:
Student can correctly solve Pythagoras problems after completion


Transfer success rate ≥60% on application problems



13. MVP Deliverables Checklist
✔ Grade + Topic onboarding
 ✔ Concept graph (Right triangle → Pythagoras)
 ✔ Mastery threshold logic
 ✔ LLM question generator with constraints
 ✔ Deterministic diagram rendering
 ✔ 2–3 interaction types
 ✔ Vision-based grading
 ✔ Tutor-style explanation
 ✔ Progress graph + gamification

Strategic Positioning
This MVP proves:
End-to-end adaptive AI teaching


LLM-guided but system-governed pedagogy


True mastery progression, not random question generation


Canvas-native conceptual assessment

---Updated PRD----
            
            LLM-Powered Difficulty Engine (MVP)

            For MVP, difficulty assignment is delegated to the LLM tutor using a structured rubric.

            The generation pipeline includes:

            LLM Question Generator

            Produces a QuestionSpec for a given concept_id, grade, and target direction (easier/same/harder).

            LLM Difficulty Rater (separate function)

            Rates the generated QuestionSpec using a rubric.

            Outputs structured difficulty scores:

            overall (1–4)

            dimensions: visual, language, reasoning_steps, numeric

            grade_fit (ok / not ok + notes)

            System Accept/Retry Policy

            If rated difficulty falls within requested band → accept.

            Otherwise → retry generation (max N attempts).

            Fallback to stub provider if invalid after retries.

            Deterministic Safety Constraints

            Grade 6 cap enforced (no trig, no proofs, bounded numeric complexity).

            Concept must exist in ontology.

            Interaction type must be supported.

            Diagram spec must be renderable.

            Progression Remains Deterministic

            MasteryEngine decides concept and difficulty direction.

            LLM does NOT decide progression or unlock concepts.

            Empirical Calibration

            Out of scope for MVP.

            Telemetry logged for future calibration phase.
