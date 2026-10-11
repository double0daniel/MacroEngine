import Foundation

/// Generates Macro's fitness coaching reply using Groq with a local offline fallback.
enum LocalAIEngine {
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
        let remainingCalories = remainingCals
        let proteinRemainingGrams = remainingProtein
        let userQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return await SmolLMInferenceService.shared.generateResponse(
            remainingCalories: remainingCalories,
            remainingProtein: proteinRemainingGrams,
            userQuery: userQuery
        )
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
