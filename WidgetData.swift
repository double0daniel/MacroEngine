import Foundation
import WidgetKit

struct MacroWidgetSnapshot: Codable, Sendable {
    var day: Date
    var caloriesEaten: Double
    var calorieTarget: Double
    var proteinEaten: Double
    var proteinGoal: Double
    var carbsEaten: Double
    var carbsGoal: Double
    var fatEaten: Double
    var fatGoal: Double
    var waterConsumedMl: Int
    var waterGoalMl: Int
    var foodLogStreak: Int

    static func empty(for date: Date = .now) -> MacroWidgetSnapshot {
        MacroWidgetSnapshot(
            day: Calendar.current.startOfDay(for: date),
            caloriesEaten: 0, calorieTarget: 2_400,
            proteinEaten: 0, proteinGoal: 160,
            carbsEaten: 0, carbsGoal: 260,
            fatEaten: 0, fatGoal: 75,
            waterConsumedMl: 0, waterGoalMl: 2_000,
            foodLogStreak: 0
        )
    }
}
