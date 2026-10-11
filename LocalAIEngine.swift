import Foundation

/// On-device MacroEngine coach. Responses are generated from the current diary context;
/// no query or personal data is sent to a server.
enum LocalAIEngine {
    private enum Intent {
        case food
        case progress
        case recovery
        case rollover
        case tdee
        case macros
        case openEnded
    }

    private struct FoodOption {
        let name: String
        let unitGrams: Int
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let aliases: [String]
    }

    private struct QuerySignals {
        let intent: Intent
        let entities: [String]
        let isConcerned: Bool
        let isPositive: Bool
    }

    private static let foodOptions = [
        FoodOption(name: "Arla Protein pudding", unitGrams: 200, calories: 150, protein: 20, carbs: 12, fat: 2, aliases: ["arla", "pudding"]),
        FoodOption(name: "Arla Protein yogurt", unitGrams: 200, calories: 140, protein: 20, carbs: 10, fat: 1, aliases: ["arla", "yogurt", "yoghurt"]),
        FoodOption(name: "Skyr", unitGrams: 150, calories: 95, protein: 16, carbs: 6, fat: 0.5, aliases: ["skyr"]),
        FoodOption(name: "Cottage cheese", unitGrams: 100, calories: 98, protein: 12, carbs: 3, fat: 4, aliases: ["cottage cheese"]),
        FoodOption(name: "Lean bresaola", unitGrams: 50, calories: 78, protein: 16, carbs: 0.5, fat: 1.5, aliases: ["bresaola"]),
        FoodOption(name: "Cooked chicken slices", unitGrams: 60, calories: 92, protein: 18, carbs: 1, fat: 2, aliases: ["chicken"]),
        FoodOption(name: "Egg", unitGrams: 1, calories: 78, protein: 6.3, carbs: 0.6, fat: 5.3, aliases: ["egg", "eggs"])
    ]

    /// Generates a personalised answer using the current day's remaining allowance.
    /// Calorie and macro values are estimates for guidance, not medical advice.
    static func generateInsight(
        for query: String,
        userName: String,
        remainingCals: Int,
        remainingProtein: Int,
        remainingCarbs: Int,
        remainingFat: Int,
        goal: String,
        waterMl: Int
    ) -> String {
        let signals = analyse(query)
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = name.isEmpty ? "" : "\(name), "
        let cals = max(0, remainingCals)
        let protein = max(0, remainingProtein)
        let carbs = max(0, remainingCarbs)
        let fat = max(0, remainingFat)
        let goalName = goal.components(separatedBy: " [target=").first ?? goal
        let goalStyle = goalName.lowercased()
        let dailyTarget = targetCalories(from: goal)

        switch signals.intent {
        case .food:
            return foodRecommendation(
                address: address,
                query: query,
                entities: signals.entities,
                remainingCals: remainingCals,
                remainingProtein: remainingProtein,
                remainingCarbs: remainingCarbs,
                remainingFat: remainingFat
            )

        case .progress:
            var opening = signals.isPositive ? "Good momentum" : "Here's your check-in"
            if signals.isConcerned { opening = "It's understandable to check in. Here's where you are" }
            let calorieLine: String
            if remainingCals < 0 {
                calorieLine = "you're about \(abs(remainingCals)) kcal over today's allowance"
            } else {
                calorieLine = "you have about \(remainingCals) kcal left"
            }
            let proteinLine = remainingProtein > 0
                ? "and \(remainingProtein) g protein to reach your target"
                : "and have reached your protein target"
            let goalTip: String
            if goalStyle.contains("cut") || goalStyle.contains("loss") {
                goalTip = "For a cut, aim for a steady, manageable deficit and keep protein consistent; one day does not define your progress."
            } else if goalStyle.contains("bulk") {
                goalTip = "For a bulk, use the remaining allowance to support training with a balanced meal, and spread protein across the day."
            } else {
                goalTip = "For maingain, consistency around maintenance and regular protein servings support gradual recomposition."
            }
            let totalContext = dailyTarget.map { "Your adjusted target is \($0) kcal, with roughly \($0 - remainingCals) net kcal logged." } ?? ""
            return "\(opening), \(address.lowercased().isEmpty ? "" : address)\(calorieLine) \(proteinLine). \(totalContext) \(goalTip)"

        case .recovery:
            let empathy = signals.isConcerned ? "Sorry you're feeling that way. " : ""
            var observations: [String] = []
            if waterMl < 2_000 {
                observations.append("You've logged \(waterMl) ml of water; a glass now and another with your next meal can help you work towards 2,000 ml or your personal target.")
            } else {
                observations.append("You've logged \(waterMl) ml of water today, so hydration is moving along.")
            }
            if let dailyTarget {
                let loggedNetCalories = dailyTarget - remainingCals
                if loggedNetCalories < 500 {
                    observations.append("Your diary shows about \(loggedNetCalories) net kcal so far. If you've eaten very little, a balanced meal with protein and carbohydrates may help support energy.")
                } else {
                    observations.append("Your diary shows about \(loggedNetCalories) net kcal against a \(dailyTarget) kcal target so far.")
                }
            } else if remainingCals > 1_200 {
                observations.append("A large part of your calorie allowance remains. If you've eaten very little, a balanced meal with protein and carbohydrates may help support energy.")
            } else if remainingCals < 0 {
                observations.append("You're about \(abs(remainingCals)) kcal over today's allowance; avoid compensating by skipping meals, and return to your usual plan at the next meal.")
            }
            if remainingProtein > 0 {
                observations.append("You have about \(remainingProtein) g protein remaining; include a convenient protein source with food if it suits your appetite.")
            }
            observations.append("Fatigue can have many causes. Rest, sleep and a regular meal can help; persistent or severe tiredness is worth discussing with a health professional.")
            return "\(empathy)\(address)\(observations.joined(separator: " "))"

        case .rollover:
            return "\(address)calorie rollover lets unused calories build a limited bank for a later day, which can give you more flexibility around a social meal. Your calorie target is still a guide for your overall plan; check Settings to enable rollover and set its cap. Today's remaining allowance is \(remainingCals) kcal."

        case .tdee:
            let goalAdvice: String
            if goalStyle.contains("cut") || goalStyle.contains("loss") {
                goalAdvice = "Your cutting target is set below estimated maintenance to support gradual fat loss."
            } else if goalStyle.contains("bulk") {
                goalAdvice = "Your bulking target is set above estimated maintenance to support weight gain and training."
            } else {
                goalAdvice = "Your maingain target aims around estimated maintenance to support recomposition."
            }
            return "\(address)TDEE is an estimate of the energy you use across a day, including activity. MacroEngine uses it to set a calorie target for your selected goal. \(goalAdvice) Use your weight trend over several weeks to judge whether the estimate needs adjusting."

        case .macros:
            return "\(address)your remaining targets are about \(protein) g protein, \(carbs) g carbs and \(fat) g fat, with \(cals) kcal left. Protein supports repair and fullness, carbs help fuel training, and dietary fat supports normal body functions. You can adjust exact targets in Settings; the goal selected is \(goalName)."

        case .openEnded:
            let encouragement = signals.isConcerned
                ? "A tricky day does not erase your progress. "
                : signals.isPositive ? "Nice work staying engaged with your plan. " : ""
            let goalHint: String
            if goalStyle.contains("cut") || goalStyle.contains("loss") {
                goalHint = "Since your current approach is cutting, prioritise a sustainable deficit and enough protein."
            } else if goalStyle.contains("bulk") {
                goalHint = "Since your current approach is bulking, support training with enough energy and consistent protein."
            } else {
                goalHint = "Since your current approach is maingain, focus on consistency around your targets and training."
            }
            let calorieSummary = dailyTarget.map { "You've logged about \($0 - remainingCals) net kcal against a \($0) kcal target." } ?? "You have about \(cals) kcal remaining."
            return "\(encouragement)\(address)today: \(calorieSummary) You have about \(protein) g protein, \(carbs) g carbs and \(fat) g fat remaining, with \(waterMl) ml water logged. \(goalHint) If you share a specific meal, workout or goal question, I can make the suggestion more focused."
        }
    }

    /// Highlights target achievement or clearly positive progress in the mascot state.
    static func shouldCelebrate(query: String, remainingCals: Int, remainingProtein: Int) -> Bool {
        let text = normalized(query)
        let positiveSignals = ["hit my goal", "reached my goal", "personal best", "great progress"]
        let asksAboutProgress = containsAny(text, ["track", "progress", "goal", "doing"])
        return (remainingProtein <= 0 && asksAboutProgress)
            || (positiveSignals.contains(where: { text.contains($0) }) || text.contains("new pr") || text.contains("pr today")) && remainingCals >= 0
    }

    private static func foodRecommendation(
        address: String,
        query: String,
        entities: [String],
        remainingCals: Int,
        remainingProtein: Int,
        remainingCarbs: Int,
        remainingFat: Int
    ) -> String {
        let queryText = normalized(query)
        let requestedOption = foodOptions.first { option in
            queryText.contains(option.name.lowercased())
        } ?? foodOptions.first { option in
            option.aliases.contains(where: { queryText.contains($0) })
        }
        let rankedOptions = foodOptions.sorted { lhs, rhs in
            let leftMatches = entities.contains(lhs.name)
            let rightMatches = entities.contains(rhs.name)
            if leftMatches != rightMatches { return leftMatches }
            let leftEfficiency = lhs.protein / lhs.calories
            let rightEfficiency = rhs.protein / rhs.calories
            return leftEfficiency > rightEfficiency
        }
        let options = requestedOption.map { selected in
            [selected] + rankedOptions.filter { $0.name != selected.name }
        } ?? rankedOptions

        guard remainingCals > 0 else {
            let choice = requestedOption ?? foodOptions[4]
            return "\(address)you're at or over today's calorie allowance. If you're still hungry or need protein, a modest portion such as 25 g of \(choice.name.lowercased()) is roughly \(Int((choice.calories * 0.5).rounded())) kcal and \(Int((choice.protein * 0.5).rounded())) g protein. These are approximate values; check the pack label and follow your appetite rather than skipping meals."
        }

        let candidates = options.compactMap { option -> (FoodOption, Double)? in
            let calorieScale = min(1, Double(remainingCals) / option.calories)
            let proteinScale = remainingProtein > 0 ? min(1, Double(remainingProtein) / option.protein) : 1
            let scale = min(calorieScale, proteinScale)
            guard scale >= 0.2 else { return nil }
            return (option, scale)
        }
        guard let best = requestedOption.flatMap({ selected in candidates.first(where: { $0.0.name == selected.name }) })
                ?? candidates.max(by: { $0.0.protein * $0.1 < $1.0.protein * $1.1 }) else {
            return "\(address)with about \(remainingCals) kcal and \(remainingProtein) g protein left, a full high-protein serving may not fit comfortably. Try a smaller amount of cooked chicken slices or Skyr, and compare the label with your remaining targets (\(remainingCarbs) g carbs and \(remainingFat) g fat)."
        }

        let option = best.0
        let scale = best.1
        let portion = max(1, Int((Double(option.unitGrams) * scale).rounded()))
        let estimateCalories = Int((option.calories * scale).rounded())
        let estimateProtein = Int((option.protein * scale).rounded())
        let estimateCarbs = Int((option.carbs * scale).rounded())
        let estimateFat = Int((option.fat * scale).rounded())
        let remainingAfter = max(0, remainingCals - estimateCalories)
        let entityHint = entities.isEmpty ? "" : " I picked up that you mentioned \(entities.joined(separator: ", "))."
        let portionName = option.unitGrams == 1 ? "\(portion) egg" : "\(portion) g of \(option.name.lowercased())"
        let proteinNote: String
        if remainingProtein <= 0 {
            proteinNote = "Your protein target is already met, so this is an optional snack."
        } else if estimateProtein < remainingProtein {
            proteinNote = "That leaves roughly \(remainingProtein - estimateProtein) g protein to cover later."
        } else {
            proteinNote = "That is close to your remaining protein target."
        }
        return "\(address)a portion of \(portionName) is a practical UK option: roughly \(estimateCalories) kcal, \(estimateProtein) g protein, \(estimateCarbs) g carbs and \(estimateFat) g fat. That should leave about \(remainingAfter) kcal.\(entityHint) \(proteinNote) Nutrition varies by brand and serving, so check the label."
    }

    private static func analyse(_ query: String) -> QuerySignals {
        let text = normalized(query)
        let entities = foodOptions
            .filter { option in option.aliases.contains(where: { text.contains($0) }) }
            .map(\.name)
        let hasQuestion = text.contains("?") || text.hasPrefix("how ") || text.hasPrefix("what ")
        let isConcerned = containsAny(text, ["tired", "fatigue", "hungry", "struggling", "behind", "stressed", "worried", "frustrated", "sore", "low energy"])
        let isPositive = containsAny(text, ["great", "personal best", "hit my goal", "reached my goal", "on track", "crushed", "new pr"])

        let intent: Intent
        if containsAny(text, ["rollover", "calorie bank", "banked calorie"]) {
            intent = .rollover
        } else if containsAny(text, ["tdee", "maintenance calories", "energy expenditure"]) {
            intent = .tdee
        } else if containsAny(text, ["macro", "macros", "carbs", "carbohydrate", "fat target", "protein goal", "protein target", "how much protein", "protein intake"]) {
            intent = .macros
        } else if containsAny(text, ["tired", "fatigue", "energy", "hydration", "water", "recovery", "recover", "sore", "sleep", "why am i tired"]) {
            intent = .recovery
        } else if containsAny(text, ["on track", "how am i doing", "progress", "audit", "goal status", "doing today"]) {
            intent = .progress
        } else if containsAny(text, ["snack", "meal", "food", "eat", "recipe", "recommend", "suggest", "protein source", "what can i have"])
                    || entities.isEmpty == false && containsAny(text, ["protein", "good", "best", "what should i"]) {
            intent = .food
        } else if hasQuestion {
            intent = .openEnded
        } else {
            intent = .openEnded
        }

        return QuerySignals(intent: intent, entities: entities, isConcerned: isConcerned, isPositive: isPositive)
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_GB"))
    }

    private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains(where: { text.contains($0) })
    }

    private static func targetCalories(from goalContext: String) -> Int? {
        guard let marker = goalContext.range(of: "[target=") else { return nil }
        let digits = goalContext[marker.upperBound...].prefix(while: { $0.isNumber })
        return Int(digits)
    }
}
