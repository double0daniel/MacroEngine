import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let enabledKey = "macroengine.smartPushReminders.enabled.v1"
    private let identifierPrefix = "macroengine.mealReminder."
    private let scheduledDays = 14

    private struct ReminderWindow {
        let category: MealCategory
        let hour: Int

        static let all: [ReminderWindow] = [
            ReminderWindow(category: .breakfast, hour: 9),
            ReminderWindow(category: .lunch, hour: 13),
            ReminderWindow(category: .dinner, hour: 19)
        ]
    }

    private override init() {
        super.init()
        center.delegate = self
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Requests permission and schedules date-specific notifications for the next
    /// two weeks. Date-specific requests let a logged meal cancel only today's window.
    @discardableResult
    func setEnabled(
        _ enabled: Bool,
        userName: String,
        loggedCategoriesToday: Set<MealCategory>
    ) async -> Bool {
        guard enabled else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            await removeAllMealReminders()
            return true
        }

        let granted = (try? await requestAuthorization()) ?? false
        guard granted else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            await removeAllMealReminders()
            return false
        }

        UserDefaults.standard.set(true, forKey: enabledKey)
        await scheduleReminders(userName: userName, loggedCategoriesToday: loggedCategoriesToday)
        return true
    }

    /// Refreshes scheduled reminders when the app opens or returns to the foreground.
    func refreshIfEnabled(userName: String, loggedCategoriesToday: Set<MealCategory>) async {
        guard isEnabled else { return }
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            await removeAllMealReminders()
            return
        }
        await scheduleReminders(userName: userName, loggedCategoriesToday: loggedCategoriesToday)
    }

    /// Removes the pending notification for the logged meal's date and category.
    func mealWasLogged(category: MealCategory, date: Date = .now) {
        guard isEnabled, let window = ReminderWindow.all.first(where: { $0.category == category }) else { return }
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: window, date: date)])
    }

    /// Used when all app data is reset, so an old reminder cannot survive onboarding reset.
    func disableReminders() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        Task { await removeAllMealReminders() }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func scheduleReminders(userName: String, loggedCategoriesToday: Set<MealCategory>) async {
        await removeAllMealReminders()

        let calendar = Calendar.current
        let now = Date()
        let safeName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let greetingName = safeName.isEmpty ? "there" : safeName

        for offset in 0..<scheduledDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            for window in ReminderWindow.all {
                if offset == 0, loggedCategoriesToday.contains(window.category) { continue }
                guard let fireDate = calendar.date(bySettingHour: window.hour, minute: 0, second: 0, of: date),
                      fireDate > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = "MacroEngine Reminder"
                content.body = "Hey \(greetingName), don't forget to log your \(window.category.title) to keep your weekly pace on target!"
                content.sound = .default

                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: identifier(for: window, date: date),
                    content: content,
                    trigger: trigger
                )
                try? await center.add(request)
            }
        }
    }

    private func identifier(for window: ReminderWindow, date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(identifierPrefix)\(window.category.rawValue).\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    private func removeAllMealReminders() async {
        let requests = await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { continuation.resume(returning: $0) }
        }
        let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
