import Foundation
import WidgetKit

/// Shared bridge between the app process and the WidgetKit extension.
final class WidgetDataManager: @unchecked Sendable {
    static let shared = WidgetDataManager()
    static let appGroupID = "group.com.double0daniel.MacroEngine"

    private let snapshotKey = "macroengine.widget.data.v2"
    private let defaults = UserDefaults(suiteName: WidgetDataManager.appGroupID)

    private init() {}

    /// Persists the diary snapshot and immediately asks WidgetKit to refresh all tiles.
    @MainActor
    func updateWidgetData(from source: any WidgetDataProviding) {
        saveAndReload(source.makeWidgetData())
    }

    func read() -> WidgetData {
        guard let defaults,
              let data = defaults.data(forKey: snapshotKey),
              var widgetData = try? JSONDecoder().decode(WidgetData.self, from: data) else {
            return .empty()
        }

        guard !Calendar.current.isDateInToday(widgetData.day) else { return widgetData }
        let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .distantPast
        let streakCarriesForward = Calendar.current.isDate(widgetData.day, inSameDayAs: previousDay)
        widgetData.day = Calendar.current.startOfDay(for: .now)
        widgetData.consumedCalories = 0
        widgetData.consumedProtein = 0
        widgetData.consumedCarbs = 0
        widgetData.consumedFat = 0
        widgetData.waterIntakeOz = 0
        widgetData.isStreakActiveToday = false
        if !streakCarriesForward { widgetData.currentStreakDays = 0 }
        return widgetData
    }

    func waterAmount(for date: Date = .now) -> Int {
        let widgetData = read()
        guard Calendar.current.isDate(widgetData.day, inSameDayAs: date) else { return 0 }
        return Int((Double(widgetData.waterIntakeOz) * 29.5735).rounded())
    }

    func reset() {
        defaults?.removeObject(forKey: snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func saveAndReload(_ widgetData: WidgetData) {
        if let defaults, let data = try? JSONEncoder().encode(widgetData) {
            defaults.set(data, forKey: snapshotKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func safeInt(_ value: Double) -> Int {
        guard value.isFinite, value < Double(Int.max), value > Double(Int.min) else { return 0 }
        return Int(value.rounded())
    }
}
