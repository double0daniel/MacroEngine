import Foundation

/// Shared payload saved in the App Group container for all MacroEngine widgets.
struct WidgetData: Codable, Sendable {
    var day: Date

    // Daily overview
    var consumedCalories: Int
    var targetCalories: Int
    var calorieRollover: Int
    var consumedProtein: Int
    var targetProtein: Int
    var consumedCarbs: Int
    var targetCarbs: Int
    var consumedFat: Int
    var targetFat: Int
    var waterIntakeOz: Int
    var waterGoalOz: Int

    // Logging streak
    var currentStreakDays: Int
    var isStreakActiveToday: Bool

    // Weekly pacing
    var weeklyCalorieTarget: Int
    var weeklyCalorieConsumed: Int
    var daysElapsed: Int
    var netCalorieSurplusDeficit: Int
    var projectedWeightChangeKg: Double
    var pacingStatus: String

    static func empty(for date: Date = .now) -> WidgetData {
        WidgetData(
            day: Calendar.current.startOfDay(for: date),
            consumedCalories: 0, targetCalories: 2_400, calorieRollover: 0,
            consumedProtein: 0, targetProtein: 160,
            consumedCarbs: 0, targetCarbs: 260,
            consumedFat: 0, targetFat: 75,
            waterIntakeOz: 0, waterGoalOz: 68,
            currentStreakDays: 0, isStreakActiveToday: false,
            weeklyCalorieTarget: 16_800, weeklyCalorieConsumed: 0,
            daysElapsed: 1, netCalorieSurplusDeficit: 0,
            projectedWeightChangeKg: 0, pacingStatus: "Log meals to see your pace"
        )
    }
}

@MainActor
protocol WidgetDataProviding {
    func makeWidgetData() -> WidgetData
}
