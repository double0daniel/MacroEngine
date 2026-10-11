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
            caloriesEaten: 0, calorieTarget: 0,
            proteinEaten: 0, proteinGoal: 0,
            carbsEaten: 0, carbsGoal: 0,
            fatEaten: 0, fatGoal: 0,
            waterConsumedMl: 0, waterGoalMl: 2_000,
            foodLogStreak: 0
        )
    }
}

enum MacroEngineWidgetDataStore {
    static let appGroupID = "group.com.macroengine.app"
    private static let snapshotKey = "macroengine.widget.snapshot.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func read() -> MacroWidgetSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              var snapshot = try? JSONDecoder().decode(MacroWidgetSnapshot.self, from: data) else {
            return .empty()
        }
        if !Calendar.current.isDateInToday(snapshot.day) {
            snapshot.day = Calendar.current.startOfDay(for: .now)
            snapshot.caloriesEaten = 0
            snapshot.proteinEaten = 0
            snapshot.carbsEaten = 0
            snapshot.fatEaten = 0
            snapshot.waterConsumedMl = 0
        }
        return snapshot
    }

    static func write(_ snapshot: MacroWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func waterAmount(for date: Date = .now) -> Int {
        let snapshot = read()
        guard Calendar.current.isDate(snapshot.day, inSameDayAs: date) else { return 0 }
        return max(0, snapshot.waterConsumedMl)
    }

    @discardableResult
    static func addWaterFromWidget(_ amountMl: Int, date: Date = .now) -> Int {
        guard amountMl > 0 else { return waterAmount(for: date) }
        var snapshot = read()
        if !Calendar.current.isDate(snapshot.day, inSameDayAs: date) {
            snapshot = .empty(for: date)
        }
        snapshot.day = Calendar.current.startOfDay(for: date)
        snapshot.waterConsumedMl = max(0, snapshot.waterConsumedMl) + amountMl
        write(snapshot)
        return snapshot.waterConsumedMl
    }
}
