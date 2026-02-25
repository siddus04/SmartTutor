import SwiftUI
import Combine
import CryptoKit
#if os(iOS)
import UIKit
#endif
#if os(iOS)
import UIKit
import PencilKit
#endif

struct CanvasSandboxView: View {
    @EnvironmentObject private var sessionStore: LearnerSessionStore
    private let accentColor = Color(red: 0.32, green: 0.64, blue: 0.66)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var latestBase: TriangleBase?
    @State private var canvasResetID = UUID()
    @State private var selectedSegment: String?
    @State private var messages: [ChatMessage] = []
    @State private var selectionDebugInfo: SelectionDebugInfo?
    @StateObject private var canvasController = CanvasController()
    @State private var isCheckingAI = false
    @State private var thinkingMessageID: UUID?
    @State private var thinkingTask: Task<Void, Never>?
    @State private var debugLog: String = ""
    @State private var isLogExpanded = false
    @State private var isShowingLearningHub = false
    @State private var isShowingNavigationMenu = false
    private let curriculumGraph = CurriculumGraph.trianglesGrade6
    private let questionProvider: TriangleQuestionProviding = AppConfig.useStubQuestionProvider ? StubQuestionProvider() : ValidatedLLMQuestionProvider()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.92, green: 0.96, blue: 0.98),
                    Color(red: 0.93, green: 0.97, blue: 0.94),
                    Color(red: 0.95, green: 0.94, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Group {
                if #available(iOS 16.0, *) {
                    NavigationSplitView(columnVisibility: $columnVisibility) {
                        TutorPane(
                            accentColor: accentColor,
                            latestBase: $latestBase,
                            messages: $messages,
                            onGenerateQuestion: { await generateDeterministicQuestion() },
                            onRunMasterySimulation: { runMasterySimulator() },
                            onQuestionLoaded: {
                                canvasResetID = UUID()
                                selectedSegment = nil
                                selectionDebugInfo = nil
                            }
                        )
                            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 360)
                    } detail: {
                        CanvasPane(
                            accentColor: accentColor,
                            diagramSpec: latestBase?.diagramSpec,
                            resetID: canvasResetID,
                            selectedSegment: selectedSegment,
                            onSegmentSelected: { segment in
                                selectedSegment = segment
                            },
                            onCheckAnswer: {
                                handleCheckAnswer()
                            },
                            onAmbiguousSelection: {
                                messages.append(ChatMessage(text: "I can’t tell which side you circled — try circling one side properly.", isAssistant: true))
                            },
                            onDebugUpdate: { info in
                                selectionDebugInfo = info
                            },
                            canvasController: canvasController,
                            isCheckingAI: isCheckingAI,
                            debugInfo: selectionDebugInfo
                        )
                    }
                    .navigationSplitViewStyle(.balanced)
                } else {
                    HStack(spacing: 0) {
                        TutorPane(
                            accentColor: accentColor,
                            latestBase: $latestBase,
                            messages: $messages,
                            onGenerateQuestion: { await generateDeterministicQuestion() },
                            onRunMasterySimulation: { runMasterySimulator() },
                            onQuestionLoaded: {
                                canvasResetID = UUID()
                                selectedSegment = nil
                                selectionDebugInfo = nil
                            }
                        )
                            .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
                        Divider()
                        CanvasPane(
                            accentColor: accentColor,
                            diagramSpec: latestBase?.diagramSpec,
                            resetID: canvasResetID,
                            selectedSegment: selectedSegment,
                            onSegmentSelected: { segment in
                                selectedSegment = segment
                            },
                            onCheckAnswer: {
                                handleCheckAnswer()
                            },
                            onAmbiguousSelection: {
                                messages.append(ChatMessage(text: "I can’t tell which side you circled — try circling one side properly.", isAssistant: true))
                            },
                            onDebugUpdate: { info in
                                selectionDebugInfo = info
                            },
                            canvasController: canvasController,
                            isCheckingAI: isCheckingAI,
                            debugInfo: selectionDebugInfo
                        )
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .overlay(alignment: .bottomTrailing) {
            if DebugFlags.showLogOverlay && isLogExpanded {
                LogOverlay(
                    logText: debugLog,
                    onCopy: {
                        #if os(iOS)
                        UIPasteboard.general.string = debugLog
                        #endif
                    },
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLogExpanded = false
                        }
                    }
                )
                .padding(10)
            }
        }
        .onAppear {
            if messages.isEmpty {
                messages = [ChatMessage(text: "Tap “New Question” to start.", isAssistant: true)]
            }
        }
        .navigationTitle("Smart Tutor")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowingNavigationMenu = true
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                }
                .accessibilityLabel("Open Navigation Menu")
            }
            #else
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Learning Hub") {
                        isShowingLearningHub = true
                    }
                    if DebugFlags.showLogOverlay {
                        Button(isLogExpanded ? "Hide Logs" : "Show Logs") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isLogExpanded.toggle()
                            }
                        }
                    }
                    Divider()
                    Button("Reset Session", role: .destructive) {
                        sessionStore.resetSession()
                    }
                } label: {
                    Label("Menu", systemImage: "line.3.horizontal")
                }
            }
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $isShowingNavigationMenu) {
            NavigationDrawer(
                isPresented: $isShowingNavigationMenu,
                isShowingLearningHub: $isShowingLearningHub,
                isLogExpanded: $isLogExpanded,
                onRunMasterySimulation: { runMasterySimulator() },
                onReset: {
                    sessionStore.resetSession()
                }
            )
            .presentationDetents([.fraction(1.0)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(.clear)
        }
        #endif
        .navigationDestination(isPresented: $isShowingLearningHub) {
            ExercisesHomeView()
        }
    }



    private func generateDeterministicQuestion() async -> TriangleResponse? {
        guard let session = sessionStore.session else {
            appendLog("No learner session found.")
            return nil
        }

        let step = MasteryEngine.nextLearningStep(state: session.progression, graph: curriculumGraph)
        if step.isComplete {
            await MainActor.run {
                messages = [ChatMessage(text: "🎉 You completed Triangles M2 progression.", isAssistant: true)]
                latestBase = nil
            }
            appendLog("Progression completed: no further concepts.")
            return nil
        }

        guard let conceptId = step.conceptId, let difficulty = step.difficulty else {
            appendLog("Missing concept/difficulty in next learning step.")
            return nil
        }

        do {
            let response = try await questionProvider.generateQuestion(conceptId: conceptId, difficulty: difficulty, intent: step.intent)
            appendLog("Loaded concept=\(conceptId) difficulty=\(difficulty) intent=\(step.intent.rawValue)")
            return response
        } catch {
            appendLog("Question generation failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func updateMasteryAfterCheck(expected: String, detected: String?, ambiguity: Double) {
        guard let session = sessionStore.session else { return }
        let conceptId = latestBase?.conceptId ?? session.progression.currentConceptId
        guard let conceptId else { return }

        let normalizedExpected = normalizeSegmentLabel(expected)
        let normalizedDetected = normalizeSegmentLabel(detected)

        let outcome: MasteryOutcome
        if ambiguity >= 0.6 || detected == nil {
            outcome = .ambiguous
        } else if normalizedDetected == normalizedExpected {
            outcome = .correct
        } else {
            outcome = .incorrect
        }

        sessionStore.updateProgression { progression in
            MasteryEngine.applyOutcome(state: &progression, graph: curriculumGraph, conceptId: conceptId, outcome: outcome)
        }

        if let mastery = sessionStore.session?.progression.masteryByConcept[conceptId] {
            appendLog("Mastery \(conceptId): c=\(mastery.correctCount) i=\(mastery.incorrectCount) d=\(mastery.currentDifficulty) mastered=\(mastery.mastered) remediation=\(mastery.needsRemediation)")
        }
    }

    private func runMasterySimulator() {
        guard DebugFlags.showMasterySimulator else { return }
        guard let session = sessionStore.session else {
            appendLog("Simulator aborted: no session")
            return
        }
        var progression = session.progression
        let script: [MasteryOutcome] = [.correct, .correct, .incorrect, .correct, .correct, .correct, .ambiguous, .correct]

        appendLog("Simulator start: script=\(script.count) steps")
        for (index, outcome) in script.enumerated() {
            let step = MasteryEngine.nextLearningStep(state: progression, graph: curriculumGraph)
            guard let conceptId = step.conceptId else {
                appendLog("Simulator complete at step \(index + 1)")
                break
            }
            MasteryEngine.applyOutcome(state: &progression, graph: curriculumGraph, conceptId: conceptId, outcome: outcome)
            let mastery = progression.masteryByConcept[conceptId]
            appendLog("Sim#\(index + 1) concept=\(conceptId) outcome=\(String(describing: outcome)) d=\(mastery?.currentDifficulty ?? 0) mastered=\(mastery?.mastered ?? false)")
        }

        sessionStore.updateProgression { state in
            state = progression
        }
    }
    private func handleCheckAnswer() {
        guard !isCheckingAI else { return }
        guard let base = latestBase else {
            messages.append(ChatMessage(text: "No question to check yet.", isAssistant: true))
            return
        }
        if canvasController.canvasView == nil {
            messages.append(ChatMessage(text: "No question to check yet.", isAssistant: true))
            return
        }
        isCheckingAI = true

        let thinking = ChatMessage(text: "Thinking.", isAssistant: true)
        thinkingMessageID = thinking.id
        messages.append(thinking)
        startThinkingAnimation()

        Task {
            let envelope = await runAICheck(base: base)
            await MainActor.run {
                stopThinkingAnimation()
                removeThinkingMessage()
            }

            guard let envelope, !envelope.didFallback else {
                await MainActor.run {
                    messages.append(ChatMessage(text: "(AI check failed) Please try again.", isAssistant: true))
                    isCheckingAI = false
                }
                appendLog("AI check failed or fallback used.")
                return
            }

            let result = envelope.result
            await streamAssistantMessage(result.studentFeedback)

            if let detected = result.detectedSegment, result.ambiguityScore < 0.6 {
                let expected = base.answer?.value ?? "AB"
                let isCorrect = normalizeSegmentLabel(detected) == normalizeSegmentLabel(expected)
                let followUp = isCorrect ? "✅ Correct" : "❌ Try again"
                await MainActor.run {
                    messages.append(ChatMessage(text: followUp, isAssistant: true))
                    if !isCorrect {
                        canvasController.clear()
                        selectedSegment = nil
                    }
                }
                await MainActor.run {
                    updateMasteryAfterCheck(expected: expected, detected: detected, ambiguity: result.ambiguityScore)
                }
            } else {
                await MainActor.run {
                    messages.append(ChatMessage(text: "I can’t tell which side you circled—try circling just ONE side clearly.", isAssistant: true))
                    canvasController.clear()
                    selectedSegment = nil
                    let expected = base.answer?.value ?? "AB"
                    updateMasteryAfterCheck(expected: expected, detected: result.detectedSegment, ambiguity: result.ambiguityScore)
                }
            }

            if let status = envelope.statusCode {
                print("[AICheck] HTTP \(status)")
                appendLog("HTTP \(status)")
            }
            let deterministic = selectedSegment ?? "nil"
            print("[AICheck] Deterministic=\(deterministic) AI=\(result.detectedSegment ?? "nil") amb=\(String(format: "%.2f", result.ambiguityScore)) conf=\(String(format: "%.2f", result.confidence))")
            appendLog("Deterministic=\(deterministic) AI=\(result.detectedSegment ?? "nil") amb=\(String(format: "%.2f", result.ambiguityScore)) conf=\(String(format: "%.2f", result.confidence))")

            await MainActor.run {
                isCheckingAI = false
            }
        }
    }

    private func runAICheck(base: TriangleBase) async -> TriangleAIChecker.ResultEnvelope? {
#if os(iOS)
        guard let canvasView = canvasController.canvasView else {
            print("[AICheck] Warning: canvas view unavailable")
            return nil
        }
        let scale = UIScreen.main.scale
        let size = canvasView.bounds.size
        let backgroundImage: UIImage? = await MainActor.run { baseDiagramImage(size: size, scale: scale, base: base) }
        let submission = await MainActor.run {
            VisionPipeline.renderSubmissionImage(canvasView: canvasView, background: backgroundImage)
        }
        let flattened = await MainActor.run {
            VisionPipeline.flattenOnWhite(submission)
        }

        let gate = VisionPipeline.shouldCallVision(inkDrawing: canvasView.drawing, renderedImage: flattened)
        if !gate.ok {
            return TriangleAIChecker.ResultEnvelope(
                result: TriangleAICheckResult(
                    detectedSegment: nil,
                    ambiguityScore: 1.0,
                    confidence: 0.0,
                    reasonCodes: gate.reasons,
                    studentFeedback: "I can’t see a clear mark yet. Try circling or marking more clearly."
                ),
                statusCode: nil,
                didFallback: false
            )
        }

        let ts = TriangleSnapshotter.timestampString()
        let basePath = TriangleSnapshotter.savePNG(data: backgroundImage?.pngData() ?? Data(), filename: "base_\(ts).png")
        let inkPath = TriangleSnapshotter.savePNG(data: canvasView.drawing.image(from: canvasView.bounds, scale: scale).pngData() ?? Data(), filename: "ink_\(ts).png")
        let combinedPath = TriangleSnapshotter.savePNG(data: flattened.pngData() ?? Data(), filename: "combined_\(ts).png")
        appendLog("Snapshot base: \(basePath ?? "nil")")
        appendLog("Snapshot ink: \(inkPath ?? "nil")")
        appendLog("Snapshot combined: \(combinedPath ?? "nil")")
        appendLog("combined_hash=\(sha256Prefix(flattened.pngData() ?? Data()))")

        var imageForVision = flattened
        let config = VisionRequestConfig()
        if config.enableCropping {
            imageForVision = await MainActor.run {
                VisionPipeline.cropToContentBounds(
                    imageForVision,
                    paddingPct: config.paddingPct,
                    minSize: config.minCropSize,
                    inkDrawing: canvasView.drawing,
                    canvasSize: canvasView.bounds.size,
                    minKeepAreaFraction: config.minKeepAreaFraction
                )
            }
        }
        imageForVision = await MainActor.run {
            VisionPipeline.resizeForVision(imageForVision, longEdge: config.longEdge)
        }
        appendLog("Sizes px: submission=\(intSize(flattened.size)) cropped=\(intSize(imageForVision.size))")

        let encoded = await MainActor.run {
            VisionPipeline.encodeForAPIPayload(
                imageForVision,
                maxPNGBytes: config.maxPNGBytes,
                jpegQuality: config.jpegFallbackQuality
            )
        }
        guard let encoded else {
            print("[AICheck] Warning: encoding failed")
            return nil
        }
        appendLog("Payload mime=\(encoded.mime) bytes=\(encoded.byteCount)")
        let combinedBase64 = encoded.base64

        let checker = TriangleAIChecker()
        let expectedSegment = base.answer?.value ?? "AB"
        let envelope = await checker.check(
            conceptId: base.conceptId ?? "tri.basics.identify_right_triangle",
            promptText: base.promptText ?? base.tutorMessages.first?.text ?? "",
            interactionType: base.interactionType ?? "highlight",
            responseMode: base.responseMode ?? "highlight",
            rightAngleAt: base.diagramSpec?.rightAngleAt,
            expectedAnswerValue: expectedSegment,
            combinedPNGBase64: combinedBase64
        )
        return envelope
#else
        print("[AICheck] Warning: AI check unsupported on this platform")
        return nil
#endif
    }

    private func normalizeSegmentLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count == 2 else { return cleaned }
        let chars = cleaned.map { String($0) }.sorted().joined()
        switch chars {
        case "AB": return "AB"
        case "AC": return "CA"
        case "BC": return "BC"
        default: return cleaned
        }
    }

    private func startThinkingAnimation() {
        thinkingTask?.cancel()
        guard let thinkingID = thinkingMessageID else { return }
        thinkingTask = Task {
            var dotCount = 1
            while !Task.isCancelled {
                let text = "Thinking" + String(repeating: ".", count: dotCount)
                await MainActor.run {
                    updateMessage(id: thinkingID, text: text)
                }
                dotCount = dotCount % 3 + 1
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func stopThinkingAnimation() {
        thinkingTask?.cancel()
        thinkingTask = nil
    }

    private func removeThinkingMessage() {
        guard let id = thinkingMessageID else { return }
        messages.removeAll { $0.id == id }
        thinkingMessageID = nil
    }

    @MainActor
    private func updateMessage(id: UUID, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = text
    }

    private func streamAssistantMessage(_ text: String) async {
        let message = ChatMessage(text: "", isAssistant: true)
        let id = message.id
        await MainActor.run {
            messages.append(message)
        }
        let characters = Array(text)
        let total = max(characters.count, 1)
        let minDelay: UInt64 = 10_000_000
        let maxDelay: UInt64 = 40_000_000
        let targetTotal: UInt64 = 900_000_000
        let perChar = min(max(targetTotal / UInt64(total), minDelay), maxDelay)

        var current = ""
        for char in characters {
            current.append(char)
            await MainActor.run {
                updateMessage(id: id, text: current)
            }
            try? await Task.sleep(nanoseconds: perChar)
        }
    }

    private func appendLog(_ line: String) {
        Task { @MainActor in
            let timestamp = TriangleSnapshotter.timestampString()
            let entry = "[\(timestamp)] \(line)"
            if debugLog.isEmpty {
                debugLog = entry
            } else {
                debugLog.append("\n\(entry)")
            }
        }
    }

    private func sha256Prefix(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(12).lowercased()
    }

    #if os(iOS)
    private func baseDiagramImage(size: CGSize, scale: CGFloat, base: TriangleBase) -> UIImage? {
        guard let spec = base.diagramSpec else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let f = UIGraphicsImageRendererFormat()
            f.scale = scale
            f.opaque = true
            return f
        }())
        return renderer.image { context in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            let padding = min(size.width, size.height) * 0.12
            let drawSize = CGSize(width: max(size.width - padding * 2, 1), height: max(size.height - padding * 2, 1))

            func point(_ key: String) -> CGPoint? {
                guard let p = spec.points[key] else { return nil }
                return CGPoint(
                    x: padding + CGFloat(p.x) * drawSize.width,
                    y: padding + CGFloat(p.y) * drawSize.height
                )
            }

            context.cgContext.setStrokeColor(UIColor.black.cgColor)
            context.cgContext.setLineWidth(2)
            for segment in spec.segments {
                let chars = Array(segment)
                guard chars.count == 2 else { continue }
                let aKey = String(chars[0])
                let bKey = String(chars[1])
                guard let a = point(aKey), let b = point(bKey) else { continue }
                context.cgContext.beginPath()
                context.cgContext.move(to: a)
                context.cgContext.addLine(to: b)
                context.cgContext.strokePath()
            }

            for (key, label) in spec.vertexLabels {
                guard let pt = point(key) else { continue }
                let centroid = triangleCentroid(spec: spec, padding: padding, drawSize: drawSize)
                let direction = normalized(CGPoint(x: pt.x - centroid.x, y: pt.y - centroid.y))
                let labelPoint = CGPoint(x: pt.x + direction.x * 20, y: pt.y + direction.y * 20)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                    .foregroundColor: UIColor.black
                ]
                let text = NSAttributedString(string: label, attributes: attributes)
                text.draw(at: CGPoint(x: labelPoint.x - 6, y: labelPoint.y - 9))
            }

            if let rightKey = spec.rightAngleAt,
               let vertex = point(rightKey) {
                let neighbors = neighborKeys(spec: spec, for: rightKey)
                if neighbors.count >= 2,
                   let p1 = point(neighbors[0]),
                   let p2 = point(neighbors[1]) {
                    let marker = min(drawSize.width, drawSize.height) * 0.08
                    let u = normalized(CGPoint(x: p1.x - vertex.x, y: p1.y - vertex.y))
                    let v = normalized(CGPoint(x: p2.x - vertex.x, y: p2.y - vertex.y))
                    let a = CGPoint(x: vertex.x + u.x * marker, y: vertex.y + u.y * marker)
                    let b = CGPoint(x: a.x + v.x * marker, y: a.y + v.y * marker)
                    let c = CGPoint(x: vertex.x + v.x * marker, y: vertex.y + v.y * marker)
                    context.cgContext.beginPath()
                    context.cgContext.move(to: a)
                    context.cgContext.addLine(to: b)
                    context.cgContext.addLine(to: c)
                    context.cgContext.strokePath()
                }
            }
        }
    }

    private func triangleCentroid(spec: TriangleDiagramSpec, padding: CGFloat, drawSize: CGSize) -> CGPoint {
        let keys = ["A", "B", "C"]
        let points = keys.compactMap { spec.points[$0] }
        let source = points.isEmpty ? Array(spec.points.values) : points
        let count = CGFloat(max(source.count, 1))
        let sum = source.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + CGFloat(point.x), y: partial.y + CGFloat(point.y))
        }
        let avg = CGPoint(x: sum.x / count, y: sum.y / count)
        return CGPoint(
            x: padding + avg.x * drawSize.width,
            y: padding + avg.y * drawSize.height
        )
    }

    private func neighborKeys(spec: TriangleDiagramSpec, for vertexKey: String) -> [String] {
        var neighbors: [String] = []
        for segment in spec.segments {
            let chars = Array(segment)
            guard chars.count == 2 else { continue }
            let a = String(chars[0])
            let b = String(chars[1])
            if a == vertexKey {
                neighbors.append(b)
            } else if b == vertexKey {
                neighbors.append(a)
            }
        }
        if neighbors.count >= 2 {
            return neighbors
        }
        let fallback = spec.points.keys.filter { $0 != vertexKey }
        return neighbors + fallback
    }

    private func normalized(_ vector: CGPoint) -> CGPoint {
        let length = max(sqrt(vector.x * vector.x + vector.y * vector.y), 0.0001)
        return CGPoint(x: vector.x / length, y: vector.y / length)
    }
    #endif

    private func intSize(_ size: CGSize) -> String {
        "\(Int(size.width))x\(Int(size.height))"
    }
}

private struct TutorPane: View {
    @State private var draftMessage = ""
    @State private var isGenerating = false
    @State private var didFailToGenerate = false
    let accentColor: Color
    @Binding var latestBase: TriangleBase?
    @Binding var messages: [ChatMessage]
    let onGenerateQuestion: () async -> TriangleResponse?
    let onRunMasterySimulation: () -> Void
    let onQuestionLoaded: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            header
            chatArea
            inputBar
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
        .padding(4)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green.opacity(0.6))
                        .frame(width: 8, height: 8)
                    Text("Online · Ready to help")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.secondary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                if DebugFlags.showMasterySimulator {
                    Button("Sim") {
                        onRunMasterySimulation()
                    }
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(accentColor.opacity(0.12)))
                    .foregroundStyle(accentColor)
                }

                Button(action: {
                    Task { await generateQuestion() }
                }) {
                    Group {
                        if isGenerating {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(accentColor)
                        } else {
                            Text("New Question")
                                .font(.callout.weight(.semibold))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(accentColor.opacity(0.15))
                    )
                }
                .foregroundStyle(accentColor)
                .disabled(isGenerating)
                .opacity(isGenerating ? 0.6 : 1.0)
            }
        }
    }

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(messages) { message in
                        MessageBubble(text: message.text, isAssistant: message.isAssistant)
                            .id(message.id)
                    }
                    if didFailToGenerate {
                        Button(action: {
                            Task { await generateQuestion() }
                        }) {
                            Text("Retry")
                                .font(.callout.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(accentColor.opacity(0.15))
                                )
                        }
                        .foregroundStyle(accentColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
            .frame(maxHeight: .infinity)
            .onChange(of: messages.count) { _, _ in
                guard let lastID = messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            GrowingTextEditor(text: $draftMessage, minHeight: 48, maxHeight: 130)
                .padding(.horizontal, 6)
            Button(action: {}) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.appBackground)
                    )
            }
            Button(action: {}) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(accentColor)
                    )
            }
            .disabled(true)
            .opacity(0.5)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    @MainActor
    private func generateQuestion() async {
        isGenerating = true
        didFailToGenerate = false
        messages = [ChatMessage(text: "Generating a new question...", isAssistant: true)]
        if let response = await onGenerateQuestion() {
            messages = response.base.tutorMessages.map {
                ChatMessage(text: $0.text, isAssistant: $0.role != "user")
            }
            latestBase = response.base
            onQuestionLoaded()
        } else {
            if latestBase == nil {
                messages = [ChatMessage(text: "I couldn't load a new question. Try again.", isAssistant: true)]
                didFailToGenerate = true
            }
        }
        isGenerating = false
    }
}

private struct CanvasPane: View {
    let accentColor: Color
    let diagramSpec: TriangleDiagramSpec?
    let resetID: UUID
    let selectedSegment: String?
    let onSegmentSelected: (String?) -> Void
    let onCheckAnswer: () -> Void
    let onAmbiguousSelection: () -> Void
    let onDebugUpdate: (SelectionDebugInfo?) -> Void
    let canvasController: CanvasController
    let isCheckingAI: Bool
    let debugInfo: SelectionDebugInfo?

    var body: some View {
        VStack(spacing: 6) {
            CanvasBoard(
                accentColor: accentColor,
                diagramSpec: diagramSpec,
                resetID: resetID,
                selectedSegment: selectedSegment,
                onSegmentSelected: onSegmentSelected,
                onCheckAnswer: onCheckAnswer,
                onAmbiguousSelection: onAmbiguousSelection,
                onDebugUpdate: onDebugUpdate,
                canvasController: canvasController,
                isCheckingAI: isCheckingAI,
                debugInfo: debugInfo
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct MessageBubble: View {
    let text: String
    let isAssistant: Bool

    var body: some View {
        HStack {
            if isAssistant {
                bubble
                Spacer(minLength: 30)
            } else {
                Spacer(minLength: 30)
                bubble
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bubble: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(isAssistant ? Color.primary : Color.white)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(isAssistant ? Color.secondary.opacity(0.3) : Color.accentColor)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
            .frame(maxWidth: 260, alignment: isAssistant ? .leading : .trailing)
    }
}

private struct CanvasBoard: View {
    let accentColor: Color
    let diagramSpec: TriangleDiagramSpec?
    let resetID: UUID
    let selectedSegment: String?
    let onSegmentSelected: (String?) -> Void
    let onCheckAnswer: () -> Void
    let onAmbiguousSelection: () -> Void
    let onDebugUpdate: (SelectionDebugInfo?) -> Void
    let canvasController: CanvasController
    let isCheckingAI: Bool
    let debugInfo: SelectionDebugInfo?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.appBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 10)
            GridBackground()
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .opacity(0.28)
            if let diagramSpec {
                TriangleDiagramView(spec: diagramSpec, selectedSegment: selectedSegment)
                    .padding(18)
                    .allowsHitTesting(false)
            }
            DrawingLayer(
                resetID: resetID,
                diagramSpec: diagramSpec,
                onSegmentSelected: onSegmentSelected,
                onAmbiguousSelection: onAmbiguousSelection,
                onDebugUpdate: onDebugUpdate,
                canvasController: canvasController
            )
            if DebugFlags.showSelectionDebug, let debugInfo {
                SelectionDebugOverlay(debugInfo: debugInfo)
                    .padding(18)
                    .allowsHitTesting(false)
            }
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 10) {
                OverlayIconButton(systemName: "arrow.uturn.backward") {
                    canvasController.undo()
                }
                OverlayIconButton(systemName: "arrow.uturn.forward") {
                    canvasController.redo()
                }
            }
            .padding(14)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                OverlayPillIconButton(systemName: "lightbulb.fill", tint: accentColor) { }
                OverlayPillIconButton(systemName: "eraser.fill", tint: Color.secondary) {
                    canvasController.clear()
                }
            }
            .padding(14)
        }
        .overlay(alignment: .bottomLeading) {
            Button("Check Answer") {
                onCheckAnswer()
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(accentColor.opacity(0.9))
            )
            .foregroundStyle(Color.white)
            .shadow(color: accentColor.opacity(0.35), radius: 12, x: 0, y: 6)
            .padding(14)
            .disabled(isCheckingAI)
            .opacity(isCheckingAI ? 0.6 : 1.0)
        }
        .overlay(alignment: .bottom) {
            if UIFlags.showBottomPrompt {
                Text("Circle the hypotenuse of the triangle")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.thinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .padding(.bottom, 14)
            }
        }
    }
}

private struct DrawingLayer: View {
    let resetID: UUID
    let diagramSpec: TriangleDiagramSpec?
    let onSegmentSelected: (String?) -> Void
    let onAmbiguousSelection: () -> Void
    let onDebugUpdate: (SelectionDebugInfo?) -> Void
    let canvasController: CanvasController

    var body: some View {
        ZStack {
            PKCanvasViewRepresentable(
                diagramSpec: diagramSpec,
                onSegmentSelected: onSegmentSelected,
                onAmbiguousSelection: onAmbiguousSelection,
                onDebugUpdate: onDebugUpdate,
                canvasController: canvasController
            )
        }
        .padding(18)
        .id(resetID)
    }
}

#if os(iOS)
private struct SelectionDebugOverlay: View {
    let debugInfo: SelectionDebugInfo

    var body: some View {
        Canvas { context, size in
            var bboxPath = Path()
            bboxPath.addRect(debugInfo.loopBoundingBox)
            context.stroke(bboxPath, with: .color(.red), lineWidth: 1.5)

            let segmentColors: [String: Color] = ["AB": .blue, "BC": .green, "CA": .orange]
            for sample in debugInfo.segmentSamples {
                let color = segmentColors[sample.segment] ?? .purple
                for point in sample.points {
                    let rect = CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }

            let label = debugLabelText(debugInfo)
            let text = Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary)
            context.draw(text, at: CGPoint(x: size.width - 6, y: 10), anchor: .topTrailing)
        }
    }

    private func debugLabelText(_ info: SelectionDebugInfo) -> String {
        let fractions = info.fractions
            .map { "\($0.segment)=\(String(format: "%.2f", Double($0.insideFraction)))" }
            .joined(separator: " ")
        let selected = info.selectedSegment ?? "none"
        return "\(fractions) sel=\(selected) amb=\(info.ambiguous) \(info.status)"
    }
}
#else
private struct SelectionDebugOverlay: View {
    let debugInfo: SelectionDebugInfo
    var body: some View { EmptyView() }
}
#endif

private struct SelectionDebugInfo {
    let loopBoundingBox: CGRect
    let segmentSamples: [(segment: String, points: [CGPoint])]
    let fractions: [(segment: String, insideFraction: CGFloat)]
    let selectedSegment: String?
    let ambiguous: Bool
    let status: String
}

#if os(iOS)
private struct PKCanvasViewRepresentable: UIViewRepresentable {
    let diagramSpec: TriangleDiagramSpec?
    let onSegmentSelected: (String?) -> Void
    let onAmbiguousSelection: () -> Void
    let onDebugUpdate: (SelectionDebugInfo?) -> Void
    let canvasController: CanvasController

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSegmentSelected: onSegmentSelected,
            onAmbiguousSelection: onAmbiguousSelection,
            onDebugUpdate: onDebugUpdate
        )
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.alwaysBounceVertical = false
        canvasView.alwaysBounceHorizontal = false
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 5)
        canvasView.isUserInteractionEnabled = true
        canvasView.delegate = context.coordinator
        canvasController.canvasView = canvasView
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.diagramSpec = diagramSpec
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var diagramSpec: TriangleDiagramSpec?
        let onSegmentSelected: (String?) -> Void
        let onAmbiguousSelection: () -> Void
        let onDebugUpdate: (SelectionDebugInfo?) -> Void
        private var lastSelectionAmbiguous = false

        init(
            onSegmentSelected: @escaping (String?) -> Void,
            onAmbiguousSelection: @escaping () -> Void,
            onDebugUpdate: @escaping (SelectionDebugInfo?) -> Void
        ) {
            self.onSegmentSelected = onSegmentSelected
            self.onAmbiguousSelection = onAmbiguousSelection
            self.onDebugUpdate = onDebugUpdate
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            handleDrawingChange(canvasView)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            handleDrawingChange(canvasView)
        }

        private func handleDrawingChange(_ canvasView: PKCanvasView) {
            guard let lastStroke = canvasView.drawing.strokes.last else { return }
            let path = lastStroke.path
            let count = path.count
            guard count > 0 else { return }

            var points: [CGPoint] = []
            points.reserveCapacity(count)
            for index in 0..<count {
                points.append(path[index].location)
            }

            guard let first = points.first, let last = points.last else { return }
            let closeDistance = hypot(first.x - last.x, first.y - last.y)
            let bbox = boundingBox(for: points)

            if count <= 20 {
                emitDebug(
                    pointCount: count,
                    closeDistance: closeDistance,
                    bbox: bbox,
                    triangleArea: 0,
                    areaRatio: 0,
                    fractions: [],
                    samples: [],
                    selected: nil,
                    ambiguous: false,
                    status: "reject: not enough points"
                )
                onSegmentSelected(nil)
                lastSelectionAmbiguous = false
                return
            }

            let perimeterEstimate = 2 * (bbox.width + bbox.height)
            let closeThreshold = max(60, perimeterEstimate * 0.15)
            if closeDistance >= closeThreshold {
                emitDebug(
                    pointCount: count,
                    closeDistance: closeDistance,
                    bbox: bbox,
                    triangleArea: 0,
                    areaRatio: 0,
                    fractions: [],
                    samples: [],
                    selected: nil,
                    ambiguous: false,
                    status: "reject: loop not closed"
                )
                onSegmentSelected(nil)
                lastSelectionAmbiguous = false
                return
            }

            var minX = CGFloat.greatestFiniteMagnitude
            var maxX = -CGFloat.greatestFiniteMagnitude
            var minY = CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude
            for pt in points {
                minX = min(minX, pt.x)
                maxX = max(maxX, pt.x)
                minY = min(minY, pt.y)
                maxY = max(maxY, pt.y)
            }
            let width = maxX - minX
            let height = maxY - minY
            guard width > 40, height > 40 else {
                emitDebug(
                    pointCount: count,
                    closeDistance: closeDistance,
                    bbox: bbox,
                    triangleArea: 0,
                    areaRatio: 0,
                    fractions: [],
                    samples: [],
                    selected: nil,
                    ambiguous: false,
                    status: "reject: bbox too small"
                )
                onSegmentSelected(nil)
                lastSelectionAmbiguous = false
                return
            }
            let ratio = width / height
            guard ratio >= 0.2, ratio <= 5.0 else {
                emitDebug(
                    pointCount: count,
                    closeDistance: closeDistance,
                    bbox: bbox,
                    triangleArea: 0,
                    areaRatio: 0,
                    fractions: [],
                    samples: [],
                    selected: nil,
                    ambiguous: false,
                    status: "reject: bbox aspect"
                )
                onSegmentSelected(nil)
                lastSelectionAmbiguous = false
                return
            }

            guard let diagramSpec else {
                emitDebug(
                    pointCount: count,
                    closeDistance: closeDistance,
                    bbox: bbox,
                    triangleArea: 0,
                    areaRatio: 0,
                    fractions: [],
                    samples: [],
                    selected: nil,
                    ambiguous: false,
                    status: "reject: no diagram"
                )
                onSegmentSelected(nil)
                lastSelectionAmbiguous = false
                return
            }

            let triangleBounds = triangleBoundingBox(spec: diagramSpec, in: canvasView.bounds)
            var areaRatio: CGFloat = 0
            var triangleArea: CGFloat = 0
            if triangleBounds.width > 0, triangleBounds.height > 0 {
                let bboxArea = bbox.width * bbox.height
                triangleArea = triangleBounds.width * triangleBounds.height
                areaRatio = triangleArea > 0 ? bboxArea / triangleArea : 0
            }

            let loopPath = UIBezierPath()
            if let firstPoint = points.first {
                loopPath.move(to: firstPoint)
                for point in points.dropFirst() {
                    loopPath.addLine(to: point)
                }
                loopPath.close()
            }

            let sampleCount = 15
            let samples = segmentSamples(spec: diagramSpec, in: canvasView.bounds, count: sampleCount)
            var fractions: [(segment: String, insideFraction: CGFloat)] = []
            fractions.reserveCapacity(samples.count)
            for sample in samples {
                var insideCount = 0
                for point in sample.points {
                    if loopPath.contains(point) {
                        insideCount += 1
                    }
                }
                let fraction = CGFloat(insideCount) / CGFloat(sampleCount)
                fractions.append((segment: sample.segment, insideFraction: fraction))
            }

            guard let maxEntry = fractions.max(by: { $0.insideFraction < $1.insideFraction }) else { return }
            if maxEntry.insideFraction < 0.2 {
                emitDebug(
                    pointCount: count,
                    closeDistance: closeDistance,
                    bbox: bbox,
                    triangleArea: triangleArea,
                    areaRatio: areaRatio,
                    fractions: fractions,
                    samples: samples,
                    selected: nil,
                    ambiguous: false,
                    status: "reject: low coverage"
                )
                onSegmentSelected(nil)
                lastSelectionAmbiguous = false
                return
            }

            let sorted = fractions.sorted { $0.insideFraction > $1.insideFraction }
            if sorted.count >= 2, (sorted[0].insideFraction - sorted[1].insideFraction) <= 0.15 {
                onSegmentSelected(nil)
                if !lastSelectionAmbiguous {
                    onAmbiguousSelection()
                }
                lastSelectionAmbiguous = true
                emitDebug(
                    pointCount: count,
                    closeDistance: closeDistance,
                    bbox: bbox,
                    triangleArea: triangleArea,
                    areaRatio: areaRatio,
                    fractions: fractions,
                    samples: samples,
                    selected: nil,
                    ambiguous: true,
                    status: "ambiguous"
                )
                return
            }

            onSegmentSelected(maxEntry.segment)
            lastSelectionAmbiguous = false
            emitDebug(
                pointCount: count,
                closeDistance: closeDistance,
                bbox: bbox,
                triangleArea: triangleArea,
                areaRatio: areaRatio,
                fractions: fractions,
                samples: samples,
                selected: maxEntry.segment,
                ambiguous: false,
                status: "selected"
            )
        }

        private func segmentSamples(spec: TriangleDiagramSpec, in bounds: CGRect, count: Int) -> [(segment: String, points: [CGPoint])] {
            let size = bounds.size
            let padding = min(size.width, size.height) * 0.12
            let drawSize = CGSize(
                width: max(size.width - padding * 2, 1),
                height: max(size.height - padding * 2, 1)
            )
            func point(_ key: String) -> CGPoint? {
                guard let p = spec.points[key] else { return nil }
                return CGPoint(
                    x: padding + CGFloat(p.x) * drawSize.width,
                    y: padding + CGFloat(p.y) * drawSize.height
                )
            }
            return spec.segments.compactMap { segment in
                let chars = Array(segment)
                guard chars.count == 2 else { return nil }
                let aKey = String(chars[0])
                let bKey = String(chars[1])
                guard let a = point(aKey), let b = point(bKey) else { return nil }
                var points: [CGPoint] = []
                points.reserveCapacity(count)
                for idx in 0..<count {
                    let t = CGFloat(idx) / CGFloat(max(count - 1, 1))
                    let x = a.x + (b.x - a.x) * t
                    let y = a.y + (b.y - a.y) * t
                    points.append(CGPoint(x: x, y: y))
                }
                return (segment, points)
            }
        }

        private func triangleBoundingBox(spec: TriangleDiagramSpec, in bounds: CGRect) -> CGRect {
            let size = bounds.size
            let padding = min(size.width, size.height) * 0.12
            let drawSize = CGSize(
                width: max(size.width - padding * 2, 1),
                height: max(size.height - padding * 2, 1)
            )
            var minX = CGFloat.greatestFiniteMagnitude
            var maxX = -CGFloat.greatestFiniteMagnitude
            var minY = CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude
            for point in spec.points.values {
                let x = padding + CGFloat(point.x) * drawSize.width
                let y = padding + CGFloat(point.y) * drawSize.height
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
            if minX == CGFloat.greatestFiniteMagnitude {
                return .zero
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        private func boundingBox(for points: [CGPoint]) -> CGRect {
            var minX = CGFloat.greatestFiniteMagnitude
            var maxX = -CGFloat.greatestFiniteMagnitude
            var minY = CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude
            for point in points {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            if minX == CGFloat.greatestFiniteMagnitude {
                return .zero
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        private func emitDebug(
            pointCount: Int,
            closeDistance: CGFloat,
            bbox: CGRect,
            triangleArea: CGFloat,
            areaRatio: CGFloat,
            fractions: [(segment: String, insideFraction: CGFloat)],
            samples: [(segment: String, points: [CGPoint])],
            selected: String?,
            ambiguous: Bool,
            status: String
        ) {
            let fractionText = fractions
                .map { "\($0.segment)=\(String(format: "%.2f", Double($0.insideFraction)))" }
                .joined(separator: " ")
            let selectedText = selected ?? "nil"
            print("""
            [CircleSelect] points=\(pointCount) close=\(String(format: "%.2f", Double(closeDistance))) bbox=(\(String(format: "%.1f", Double(bbox.minX))),\(String(format: "%.1f", Double(bbox.minY))),\(String(format: "%.1f", Double(bbox.width))),\(String(format: "%.1f", Double(bbox.height)))) triangleArea=\(String(format: "%.1f", Double(triangleArea))) areaRatio=\(String(format: "%.2f", Double(areaRatio))) fractions=\(fractionText) selected=\(selectedText) ambiguous=\(ambiguous) status=\(status)
            """)
            onDebugUpdate(
                SelectionDebugInfo(
                    loopBoundingBox: bbox,
                    segmentSamples: samples,
                    fractions: fractions,
                    selectedSegment: selected,
                    ambiguous: ambiguous,
                    status: status
                )
            )
        }
    }
}
#else
private struct PKCanvasViewRepresentable: View {
    let diagramSpec: TriangleDiagramSpec?
    let onSegmentSelected: (String?) -> Void
    let onAmbiguousSelection: () -> Void
    let onDebugUpdate: (SelectionDebugInfo?) -> Void
    let canvasController: CanvasController

    var body: some View {
        Color.clear
    }
}
#endif

#if os(iOS)
private final class CanvasController: ObservableObject {
    weak var canvasView: PKCanvasView?

    func undo() {
        canvasView?.undoManager?.undo()
    }

    func redo() {
        canvasView?.undoManager?.redo()
    }

    func clear() {
        canvasView?.drawing = PKDrawing()
    }
}
#else
private final class CanvasController: ObservableObject {
    weak var canvasView: AnyObject?
    func undo() {}
    func redo() {}
    func clear() {}
}
#endif

private struct OverlayIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

private struct OverlayPillIconButton: View {
    let systemName: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 52, height: 44)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

private struct LogOverlay: View {
    let logText: String
    let onCopy: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Logs")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Button("Copy") {
                    onCopy()
                }
                .font(.footnote.weight(.semibold))
                Button("Close") {
                    onClose()
                }
                .font(.footnote.weight(.semibold))
            }
            TextEditor(text: .constant(logText))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 240)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

private struct NavigationDrawer: View {
    @Binding var isPresented: Bool
    @Binding var isShowingLearningHub: Bool
    @Binding var isLogExpanded: Bool
    let onRunMasterySimulation: () -> Void
    let onReset: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture {
                    closeDrawer()
                }

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Navigation")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Button {
                        closeDrawer()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                }

                Group {
                    Button {
                        isShowingLearningHub = true
                        closeDrawer()
                    } label: {
                        drawerRow(title: "Learning Hub", systemName: "book.closed")
                    }

                    if DebugFlags.showLogOverlay {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isLogExpanded.toggle()
                            }
                            closeDrawer()
                        } label: {
                            drawerRow(title: isLogExpanded ? "Hide Logs" : "Show Logs", systemName: "doc.text.magnifyingglass")
                        }
                    }

                    if DebugFlags.showMasterySimulator {
                        Button {
                            onRunMasterySimulation()
                            closeDrawer()
                        } label: {
                            drawerRow(title: "Run Mastery Simulator", systemName: "bolt.horizontal.circle")
                        }
                    }

                    Button {
                        onReset()
                        closeDrawer()
                    } label: {
                        drawerRow(title: "Reset Session", systemName: "arrow.counterclockwise")
                    }

                    drawerRow(title: "Account (Coming Soon)", systemName: "person.crop.circle", isEnabled: false)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: 300, maxHeight: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .overlay(alignment: .leading) {
                Divider()
            }
        }
    }

    private func drawerRow(title: String, systemName: String, isEnabled: Bool = true) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemName)
                .frame(width: 20)
            Text(title)
                .font(.body.weight(.medium))
            Spacer()
        }
        .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
        .padding(.vertical, 10)
    }

    private func closeDrawer() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPresented = false
        }
    }
}

private struct GrowingTextEditor: View {
    @Binding var text: String
    let minHeight: CGFloat
    let maxHeight: CGFloat
    @State private var measuredHeight: CGFloat = 48

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text("Type a message")
                    .font(.callout)
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            TextEditor(text: $text)
                .font(.callout)
                .frame(height: min(max(measuredHeight, minHeight), maxHeight))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.appBackground)
                    )
                .scrollContentBackground(.hidden)
                .overlay(
                    Text(text.isEmpty ? " " : text)
                        .font(.callout)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: TextHeightPreferenceKey.self, value: proxy.size.height)
                            }
                        )
                        .hidden()
                )
        }
        .onPreferenceChange(TextHeightPreferenceKey.self) { value in
            measuredHeight = value
        }
    }
}

private struct TextHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 48
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct GridBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Path { path in
                let spacing: CGFloat = 24
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += spacing
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
            }
            .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
        }
    }
}
