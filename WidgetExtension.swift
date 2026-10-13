import SwiftUI
import WidgetKit

private struct MacroWidgetTimelineEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

private struct MacroWidgetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MacroWidgetTimelineEntry {
        MacroWidgetTimelineEntry(date: .now, data: .empty())
    }

    func getSnapshot(in context: Context, completion: @escaping (MacroWidgetTimelineEntry) -> Void) {
        completion(MacroWidgetTimelineEntry(date: .now, data: WidgetDataManager.shared.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MacroWidgetTimelineEntry>) -> Void) {
        let now = Date.now
        let entry = MacroWidgetTimelineEntry(date: now, data: WidgetDataManager.shared.read())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
            ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: [entry], policy: .after(tomorrow)))
    }
}

private enum WidgetPalette {
    static let canvas = Color(red: 27 / 255.0, green: 30 / 255.0, blue: 37 / 255.0)
    static let surface = Color(red: 37 / 255.0, green: 41 / 255.0, blue: 50 / 255.0)
    static let text = Color(red: 243 / 255.0, green: 244 / 255.0, blue: 246 / 255.0)
    static let secondary = Color(red: 184 / 255.0, green: 190 / 255.0, blue: 201 / 255.0)
    static let protein = Color(red: 77 / 255.0, green: 168 / 255.0, blue: 255 / 255.0)
    static let carbs = Color(red: 242 / 255.0, green: 201 / 255.0, blue: 76 / 255.0)
    static let fat = Color(red: 95 / 255.0, green: 214 / 255.0, blue: 164 / 255.0)
    static let calories = Color(red: 255 / 255.0, green: 122 / 255.0, blue: 89 / 255.0)
}

private extension WidgetData {
    var remainingCalories: Int { targetCalories - consumedCalories }
    var calorieProgress: Double {
        guard targetCalories > 0 else { return 0 }
        return min(1, max(0, Double(consumedCalories) / Double(targetCalories)))
    }
    var signedRollover: String { String(format: "%+d", calorieRollover) }
    var signedProjection: String { String(format: "%+.2f kg", projectedWeightChangeKg) }
    var toDateWeeklyBudget: Int {
        Int((Double(weeklyCalorieTarget) / 7 * Double(daysElapsed)).rounded())
    }
}

// MARK: Daily macro overview

private struct DailyMacroWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let data: WidgetData

    var body: some View {
        Group {
            if family == .systemMedium { mediumLayout } else { smallLayout }
        }
        .padding(family == .systemMedium ? 14 : 11)
        .containerBackground(WidgetPalette.canvas, for: .widget)
    }

    private var smallLayout: some View {
        VStack(spacing: 5) {
            Text("MACROENGINE")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(WidgetPalette.secondary)
            calorieRing(size: 86, lineWidth: 8)
            Text(data.calorieRollover == 0 ? "No rollover" : "Rollover: \(data.signedRollover) kcal")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(data.calorieRollover == 0 ? WidgetPalette.secondary : WidgetPalette.calories)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 4) {
                Image(systemName: "dumbbell.fill").foregroundStyle(WidgetPalette.protein)
                Text("Protein \(data.consumedProtein)/\(data.targetProtein)g")
                    .foregroundStyle(WidgetPalette.text)
            }
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WidgetPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var mediumLayout: some View {
        HStack(spacing: 14) {
            VStack(spacing: 6) {
                calorieRing(size: 88, lineWidth: 8)
                Text(data.calorieRollover == 0 ? "No rollover" : "Rollover \(data.signedRollover) kcal")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(data.calorieRollover == 0 ? WidgetPalette.secondary : WidgetPalette.calories)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 9) {
                macroBar("Protein", value: data.consumedProtein, target: data.targetProtein, color: WidgetPalette.protein)
                macroBar("Carbs", value: data.consumedCarbs, target: data.targetCarbs, color: WidgetPalette.carbs)
                macroBar("Fat", value: data.consumedFat, target: data.targetFat, color: WidgetPalette.fat)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Label("Water", systemImage: "drop.fill")
                        Spacer(minLength: 4)
                        Text("\(data.waterIntakeOz)/\(data.waterGoalOz) oz")
                            .monospacedDigit()
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WidgetPalette.secondary)
                    ProgressView(value: data.waterGoalOz > 0 ? min(1, Double(data.waterIntakeOz) / Double(data.waterGoalOz)) : 0)
                        .tint(WidgetPalette.protein)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(WidgetPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func calorieRing(size: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle().stroke(WidgetPalette.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: data.calorieProgress)
                .stroke(WidgetPalette.calories, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(data.remainingCalories)")
                    .font(.system(size: size > 86 ? 22 : 20, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(WidgetPalette.calories)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                Text("kcal left")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(WidgetPalette.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private func macroBar(_ title: String, value: Int, target: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(title)
                Spacer(minLength: 2)
                Text("\(value)/\(target)g").monospacedDigit()
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(WidgetPalette.secondary)
            ProgressView(value: target > 0 ? min(1, Double(value) / Double(target)) : 0)
                .tint(color)
        }
    }
}

struct DailyMacroWidget: Widget {
    let kind = "MacroEngineDailyMacroWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MacroWidgetTimelineProvider()) { entry in
            DailyMacroWidgetView(data: entry.data)
        }
        .configurationDisplayName("Daily Macros & Rollover")
        .description("Calories, rollover, macros and water for today.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: Weekly pace and projection

private struct WeeklyPacingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let data: WidgetData

    var body: some View {
        Group {
            if family == .systemMedium { mediumLayout } else { smallLayout }
        }
        .padding(family == .systemMedium ? 16 : 13)
        .containerBackground(WidgetPalette.canvas, for: .widget)
        .background(WidgetPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("WEEKLY PACE", systemImage: "figure.walk")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(WidgetPalette.secondary)
            Text(data.signedProjection)
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(paceColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("\(data.netCalorieSurplusDeficit >= 0 ? "+" : "")\(data.netCalorieSurplusDeficit) kcal vs plan")
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(WidgetPalette.text)
            statusBadge
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumLayout: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("THIS WEEK")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(WidgetPalette.secondary)
                Text(data.signedProjection)
                    .font(.system(size: 31, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(paceColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                statusBadge
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Day \(data.daysElapsed) of 7")
                    Spacer(minLength: 3)
                    Text("\(data.daysElapsed)/7").monospacedDigit()
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WidgetPalette.secondary)
                ProgressView(value: Double(data.daysElapsed), total: 7)
                    .tint(WidgetPalette.calories)
                Text("\(data.weeklyCalorieConsumed) / \(data.toDateWeeklyBudget) kcal so far")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(WidgetPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Macro says: \(mascotSummary)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusBadge: some View {
        Text(data.pacingStatus)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(WidgetPalette.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(WidgetPalette.surface, in: Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var paceColor: Color {
        abs(data.projectedWeightChangeKg) <= 0.05 ? WidgetPalette.fat : WidgetPalette.calories
    }

    private var mascotSummary: String {
        if data.projectedWeightChangeKg > 0.4 { return "Let's ease the surplus a touch." }
        if data.projectedWeightChangeKg < -1 { return "Keep recovery and energy in check." }
        if data.netCalorieSurplusDeficit <= 0 { return "You're keeping a steady pace." }
        return "Nice one, keep it consistent."
    }
}

struct WeeklyPacingWidget: Widget {
    let kind = "MacroEngineWeeklyPacingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MacroWidgetTimelineProvider()) { entry in
            WeeklyPacingWidgetView(data: entry.data)
        }
        .configurationDisplayName("Weekly Pace & Trajectory")
        .description("See this week's calorie pace and projected weight change.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: Lock Screen streak

private struct TrackingStreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let data: WidgetData

    private var flameColor: Color {
        data.isStreakActiveToday ? .orange : .secondary
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: data.isStreakActiveToday ? "flame.fill" : "flame")
                        .font(.system(size: 17, weight: .semibold))
                    Text("\(data.currentStreakDays)")
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                }
                .foregroundStyle(flameColor)
            }
        case .accessoryInline:
            Text("🔥 \(data.currentStreakDays) Day Streak")
        default:
            HStack(spacing: 9) {
                Image(systemName: data.isStreakActiveToday ? "flame.fill" : "flame")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(flameColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(data.currentStreakDays) Day Streak")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(data.isStreakActiveToday ? "Today Logged 🟢" : "Log food today to keep it going")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
            }
        }
    }
}

struct TrackingStreakLockScreenWidget: Widget {
    let kind = "MacroEngineTrackingStreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MacroWidgetTimelineProvider()) { entry in
            TrackingStreakWidgetView(data: entry.data)
        }
        .configurationDisplayName("MacroEngine Streak")
        .description("Keep your daily food logging streak in view.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

@main
struct MacroEngineWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyMacroWidget()
        WeeklyPacingWidget()
        TrackingStreakLockScreenWidget()
    }
}
