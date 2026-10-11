import Foundation
import WidgetKit

/// Shared bridge between the main app, App Intents, and WidgetKit timelines.
final class WidgetDataManager: @unchecked Sendable {
    static let shared = WidgetDataManager()
    static let appGroupID = "group.com.macroengine.app"

    private let snapshotKey = "macroengine.widget.snapshot.v1"
    private let defaults = UserDefaults(suiteName: WidgetDataManager.appGroupID) ?? .standard

    private init() {}

    /// Updates eaten totals while preserving the latest goals stored by the app.
    func updateAndReload(calories: Double, protein: Double, carbs: Double, fat: Double, water: Int) {
        var snapshot = read()
        snapshot.day = Calendar.current.startOfDay(for: .now)
        snapshot.caloriesEaten = Self.nonnegative(calories)
        snapshot.proteinEaten = Self.nonnegative(protein)
        snapshot.carbsEaten = Self.nonnegative(carbs)
        snapshot.fatEaten = Self.nonnegative(fat)
        snapshot.waterConsumedMl = max(0, water)
        saveAndReload(snapshot)
    }

    /// Full update used by DiaryStore so targets and streak remain current too.
    func updateAndReload(
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        water: Int,
        calorieTarget: Double,
        proteinTarget: Double,
        carbsTarget: Double,
        fatTarget: Double,
        waterTarget: Int,
        foodLogStreak: Int
    ) {
        let snapshot = MacroWidgetSnapshot(
            day: Calendar.current.startOfDay(for: .now),
            caloriesEaten: Self.nonnegative(calories),
            calorieTarget: Self.nonnegative(calorieTarget),
            proteinEaten: Self.nonnegative(protein),
            proteinGoal: Self.nonnegative(proteinTarget),
            carbsEaten: Self.nonnegative(carbs),
            carbsGoal: Self.nonnegative(carbsTarget),
            fatEaten: Self.nonnegative(fat),
            fatGoal: Self.nonnegative(fatTarget),
            waterConsumedMl: max(0, water),
            waterGoalMl: max(1, waterTarget),
            foodLogStreak: max(0, foodLogStreak)
        )
        saveAndReload(snapshot)
    }

    func read() -> MacroWidgetSnapshot {
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

    func waterAmount(for date: Date = .now) -> Int {
        let snapshot = read()
        guard Calendar.current.isDate(snapshot.day, inSameDayAs: date) else { return 0 }
        return max(0, snapshot.waterConsumedMl)
    }

    @discardableResult
    func addWaterFromWidget(_ amountMl: Int, date: Date = .now) -> Int {
        guard amountMl > 0 else { return waterAmount(for: date) }
        var snapshot = read()
        if !Calendar.current.isDate(snapshot.day, inSameDayAs: date) {
            snapshot = .empty(for: date)
        }
        snapshot.day = Calendar.current.startOfDay(for: date)
        snapshot.waterConsumedMl = max(0, snapshot.waterConsumedMl) + amountMl
        saveAndReload(snapshot)
        return snapshot.waterConsumedMl
    }

    private func saveAndReload(_ snapshot: MacroWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func nonnegative(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }
}
