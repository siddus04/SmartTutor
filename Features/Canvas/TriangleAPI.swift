import Foundation

enum TriangleAPI {
    static func generateQuestion() async throws -> TriangleResponse {
        guard let url = URL(string: AppConfig.baseURL + "/api/triangles/generate") else {
            return await mockResponse()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                return try JSONDecoder().decode(TriangleResponse.self, from: data)
            }
        } catch {
            return await mockResponse()
        }

        return await mockResponse()
    }

    private static func mockResponse() async -> TriangleResponse {
        try? await Task.sleep(nanoseconds: 800_000_000)
        return TriangleResponse(
            bundleId: "mock_bundle_1",
            base: TriangleBase(
                tutorMessages: [
                    TriangleTutorMessage(role: "assistant", text: "Let’s look at this triangle together."),
                    TriangleTutorMessage(role: "assistant", text: "One angle has a little square in the corner."),
                    TriangleTutorMessage(role: "assistant", text: "Circle the hypotenuse of the triangle.")
                ],
                diagramSpec: TriangleDiagramSpec(
                    points: [
                        "A": TrianglePoint(x: 0.2, y: 0.75),
                        "B": TrianglePoint(x: 0.8, y: 0.75),
                        "C": TrianglePoint(x: 0.55, y: 0.25)
                    ],
                    segments: ["AB", "BC", "CA"],
                    vertexLabels: ["A": "A", "B": "B", "C": "C"],
                    rightAngleAt: "C"
                ),
                answer: TriangleAnswer(value: "AB")
            )
        )
    }
}
