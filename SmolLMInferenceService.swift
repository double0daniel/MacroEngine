import Combine
import Foundation

enum OfflineQueryResponder {
    static func response(
        for userQuery: String,
        remainingCalories: Int,
        remainingProtein: Int
    ) -> String {
        let query = userQuery.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")

        if ["rollover", "roll over", "weekly budget", "carry over"].contains(where: { query.contains($0) }) {
            return "[Fallback] Unused calories from yesterday roll over across your remaining week so you can stay on target overall!"
        }
        if ["track", "progress", "on track", "doing today", "how am i"].contains(where: { query.contains($0) }) {
            return "[Fallback] You have \(remainingCalories) kcal and \(remainingProtein)g protein left today. Focus on hitting your protein target!"
        }
        if ["workout", "exercise", "cardio", "gym", "burn", "burned"].contains(where: { query.contains($0) }) {
            return "[Fallback] Logged workouts add burned calories back into your daily net budget to fuel your recovery properly."
        }
        if ["pizza", "burger", "takeaway", "nandos", "mcdonalds", "junk", "cheat"].contains(where: { query.contains($0) }) {
            return "[Fallback] You have \(remainingCalories) kcal and \(remainingProtein)g protein left. Enjoy it as long as it fits your calorie budget!"
        }
        if ["snack", "protein", "food", "eat", "hungry", "meal", "breakfast", "lunch", "dinner"].contains(where: { query.contains($0) }) {
            return "[Fallback] You have \(remainingCalories) kcal and \(remainingProtein)g protein remaining. Try Greek yogurt, eggs, or chicken breast!"
        }
        return "[Fallback] You have \(remainingCalories) kcal and \(remainingProtein)g protein left today. Prioritize lean protein to hit your daily goal!"
    }
}

private enum GroqAPIClient {
    private static let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    private static let systemPrompt = "You are MacroEngine's UK fitness coach mascot. Answer the user in ONE concise sentence (max 20 words) with clear fitness advice."

    static func complete(
        apiKey: String,
        remainingCalories: Int,
        remainingProtein: Int,
        userQuery: String
    ) async throws -> String {
        var configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2.5
        configuration.timeoutIntervalForResource = 2.5
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: endpoint, timeoutInterval: 2.5)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "llama-3.1-8b-instant",
            "max_completion_tokens": 40,
            "temperature": 0.5,
            "messages": [
                ["role": "system", "content": systemPrompt],
                [
                    "role": "user",
                    "content": "Telemetry Context: \(remainingCalories) kcal, \(remainingProtein)g protein left today.\nUser Question: \(userQuery)"
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroqRequestError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GroqRequestError.httpStatus(httpResponse.statusCode)
        }

        let completion = try JSONDecoder().decode(GroqCompletion.self, from: data)
        guard let text = completion.choices.first?.message.content else {
            throw GroqRequestError.emptyCompletion
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw GroqRequestError.emptyCompletion }
        return cleaned
    }
}

private struct GroqCompletion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

private enum GroqRequestError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case emptyCompletion

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Groq returned an invalid HTTP response."
        case let .httpStatus(status):
            return "Groq returned HTTP status \(status)."
        case .emptyCompletion:
            return "Groq returned an empty completion."
        }
    }
}

/// Sends Macro's request to Groq off the main actor and publishes UI state on the main actor.
@MainActor
final class SmolLMInferenceService: ObservableObject {
    static let shared = SmolLMInferenceService()

    @Published private(set) var mascotText = ""
    @Published private(set) var isLoading = false

    private init() {}

    func generateResponse(
        remainingCalories: Int,
        remainingProtein: Int,
        userQuery: String
    ) async -> String {
        isLoading = true
        defer { isLoading = false }

        let apiKey = (Bundle.main.object(forInfoDictionaryKey: "GROQ_API_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let generatedText: String?

        if apiKey.isEmpty || apiKey == "$(GROQ_API_KEY)" {
            print("Groq API key is not configured; using offline coaching rules.")
            generatedText = nil
        } else {
            generatedText = await Task.detached(priority: .userInitiated) {
                do {
                    return try await GroqAPIClient.complete(
                        apiKey: apiKey,
                        remainingCalories: remainingCalories,
                        remainingProtein: remainingProtein,
                        userQuery: userQuery
                    )
                } catch {
                    print("⚠️ Groq API Error: \(error.localizedDescription)")
                    return nil
                }
            }.value
        }

        let response = generatedText ?? OfflineQueryResponder.response(
            for: userQuery,
            remainingCalories: remainingCalories,
            remainingProtein: remainingProtein
        )
        mascotText = response
        return response
    }
}
