import Combine
import Foundation

private enum OpenAIAPIClient {
    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let systemPrompt = "You are Macro, a friendly UK fitness mascot. Provide precise, direct advice tailored to the user's macros/question in a conversational British tone (15-25 words)."

    static func complete(
        cleanKey: String,
        remainingCalories: Int,
        remainingProtein: Int,
        userQuery: String
    ) async throws -> String {
        var configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6.0
        configuration.timeoutIntervalForResource = 6.0
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: endpoint, timeoutInterval: 6.0)
        request.httpMethod = "POST"
        request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "max_tokens": 60,
            "temperature": 0.7,
            "messages": [
                ["role": "system", "content": systemPrompt],
                [
                    "role": "user",
                    "content": "Context: \(remainingCalories) kcal, \(remainingProtein)g protein left today.\nUser query: \(userQuery)"
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIRequestError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            if let body = String(data: data, encoding: .utf8) {
                print("❌ OpenAI API Error Status \(httpResponse.statusCode): \(body)")
            }
            throw OpenAIRequestError.httpStatus(httpResponse.statusCode)
        }

        let completion = try JSONDecoder().decode(OpenAICompletion.self, from: data)
        guard let text = completion.choices.first?.message.content else {
            throw OpenAIRequestError.emptyCompletion
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw OpenAIRequestError.emptyCompletion }
        return cleaned
    }
}

private struct OpenAICompletion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

private enum OpenAIRequestError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case emptyCompletion

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenAI returned an invalid HTTP response."
        case let .httpStatus(status):
            return "OpenAI returned HTTP status \(status)."
        case .emptyCompletion:
            return "OpenAI returned an empty completion."
        }
    }
}

/// Sends Macro's request to OpenAI off the main actor and publishes UI state on the main actor.
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

        let apiKey = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String ?? ""
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let missingKeyMessage = "⚠️ OpenAI API key missing. Please check OPENAI_API_KEY in Info.plist."
        let temporaryErrorMessage = "Macro is taking a quick breather! Please check your connection and try again."

        guard !cleanKey.isEmpty, cleanKey != "$(OPENAI_API_KEY)" else {
            mascotText = missingKeyMessage
            return missingKeyMessage
        }

        let response = await Task.detached(priority: .userInitiated) {
            do {
                return try await OpenAIAPIClient.complete(
                    cleanKey: cleanKey,
                    remainingCalories: remainingCalories,
                    remainingProtein: remainingProtein,
                    userQuery: userQuery
                )
            } catch {
                print("❌ OpenAI API Request Error: \(error.localizedDescription)")
                return temporaryErrorMessage
            }
        }.value
        mascotText = response
        return response
    }
}
