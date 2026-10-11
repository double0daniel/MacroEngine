import Foundation

/// Generates Macro's replies with the bundled on-device Qwen model.
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
        let foodFits = remainingCalories >= 400
        let prompt = """
        <|im_start|>system
        You are MacroEngine's UK fitness coach. Provide ONE concise fitness/macro tip in 1 short sentence (around 15-20 words). Never generate multiple sentences.<|im_end|>
        <|im_start|>user
        Telemetry: \(remainingCalories) kcal, \(proteinRemainingGrams)g protein left. Fits budget: \(foodFits ? "Yes" : "No"). \(query)<|im_end|>
        <|im_start|>assistant
        """
        return await SmolLMInferenceService.shared.generateResponse(prompt: prompt)
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
