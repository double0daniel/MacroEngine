import Foundation

/// Generates Macro's replies with the bundled on-device SmolLM model.
/// Telemetry is calculated locally and included in every prompt; no user query
/// or personal data is sent to a server.
enum LocalAIEngine {
    private static let inferenceFailureMessage = "I couldn't generate a response just now. Please try again."

    static func generateInsight(
        for query: String,
        userName: String,
        remainingCals: Int,
        remainingProtein: Int,
        remainingCarbs: Int,
        remainingFat: Int,
        goal: String,
        waterMl: Int
    ) async -> String {
        // Resolve the current telemetry before asking the model to reason about it.
        let remainingCalories = remainingCals
        let proteinRemainingGrams = remainingProtein
        let foodFits = remainingCalories >= 400

        // Keep the full app context available in the task, while the model prompt
        // uses the requested concise structure and live calorie/protein values.
        _ = (userName, remainingCarbs, remainingFat, goal, waterMl)
        let prompt = "System: You are MacroEngine's UK fitness mascot. Telemetry: \(remainingCalories) kcal remaining, \(proteinRemainingGrams)g protein remaining. User query: '\(query)'. Guideline: \(foodFits ? "This food fits within the budget." : "This food exceeds the calorie budget."). Deliver a direct, unique, conversational response."

        guard let generated = await SmolLMInferenceService.shared.generateResponse(prompt: prompt) else {
            return inferenceFailureMessage
        }

        let response = generated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard response.count >= 2,
              response.count <= 600,
              !response.localizedCaseInsensitiveContains("user query:") else {
            return inferenceFailureMessage
        }
        return response
    }

    /// Keeps the dashboard's mascot celebration cue independent of response generation.
    static func shouldCelebrate(query: String, remainingCals: Int, remainingProtein: Int) -> Bool {
        let text = query.lowercased()
        let positiveSignals = ["hit my goal", "reached my goal", "personal best", "great progress"]
        let asksAboutProgress = ["track", "progress", "goal", "doing"].contains { text.contains($0) }
        return (remainingProtein <= 0 && asksAboutProgress)
            || (positiveSignals.contains(where: { text.contains($0) }) || text.contains("new pr") || text.contains("pr today")) && remainingCals >= 0
    }
}
