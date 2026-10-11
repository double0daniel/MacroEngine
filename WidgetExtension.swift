import AppIntents
import SwiftUI
import WidgetKit

struct Add250MillilitresIntent: AppIntent {
    static var title: LocalizedStringResource = "Add 250 ml Water"
    static var description = IntentDescription("Add 250 ml to today's MacroEngine water tracker.")

    func perform() async throws -> some IntentResult {
        MacroEngineWidgetDataStore.addWaterFromWidget(250)
        return .result()
    }
}

private struct MacroWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: MacroWidgetSnapshot
}

private struct MacroWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MacroWidgetEntry {
        MacroWidgetEntry(date: .now, snapshot: .empty())
    }

    func getSnapshot(in context: Context, completion: @escaping (MacroWidgetEntry) -> Void) {
        completion(MacroWidgetEntry(date: .now, snapshot: MacroEngineWidgetDataStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MacroWidgetEntry>) -> Void) {
        let entry = MacroWidgetEntry(date: .now, snapshot: MacroEngineWidgetDataStore.read())
        completion(Timeline(entries: [entry], policy: .after(Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now)))
    }
}

private enum WidgetSlate {
    static let canvas = Color(red: 27 / 255.0, green: 30 / 255.0, blue: 37 / 255.0)
    static let surface = Color(red: 37 / 255.0, green: 41 / 255.0, blue: 50 / 255.0)
    static let text = Color(red: 243 / 255.0, green: 244 / 255.0, blue: 246 / 255.0)
    static let secondary = Color(red: 184 / 255.0, green: 190 / 255.0, blue: 201 / 255.0)
    static let protein = Color(red: 77 / 255.0, green: 168 / 255.0, blue: 255 / 255.0)
    static let carbs = Color(red: 242 / 255.0, green: 201 / 255.0, blue: 76 / 255.0)
    static let fat = Color(red: 95 / 255.0, green: 214 / 255.0, blue: 164 / 255.0)
    static let calories = Color(red: 255 / 255.0, green: 122 / 255.0, blue: 89 / 255.0)
}

private extension MacroWidgetSnapshot {
    var remainingCalories: Int { max(0, (calorieTarget - caloriesEaten).rounded(.toNearestOrAwayFromZero).intValue) }
}

private extension Double {
    var intValue: Int {
        guard isFinite, self < Double(Int.max), self > Double(Int.min) else { return 0 }
        return Int(self)
    }
}

private struct MacroProgressWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: MacroWidgetSnapshot

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumLayout
            } else {
                smallLayout
            }
        }
        .padding(family == .systemMedium ? 14 : 12)
        .background(WidgetSlate.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .containerBackground(WidgetSlate.canvas, for: .widget)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("MACROENGINE")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(WidgetSlate.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(snapshot.remainingCalories)")
                    .font(.system(size: 27, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(WidgetSlate.calories)
                Text("left")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WidgetSlate.secondary)
            }
            Text("\(snapshot.caloriesEaten.intValue) / \(snapshot.calorieTarget.intValue) kcal")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(WidgetSlate.secondary)
            macroBar("P", value: snapshot.proteinEaten, goal: snapshot.proteinGoal, color: WidgetSlate.protein)
            macroBar("C", value: snapshot.carbsEaten, goal: snapshot.carbsGoal, color: WidgetSlate.carbs)
            macroBar("F", value: snapshot.fatEaten, goal: snapshot.fatGoal, color: WidgetSlate.fat)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumLayout: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CALORIES")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(WidgetSlate.secondary)
                Text("\(snapshot.remainingCalories)")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(WidgetSlate.calories)
                Text("kcal remaining")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetSlate.secondary)
                Text("\(snapshot.caloriesEaten.intValue) eaten · \(snapshot.calorieTarget.intValue) target")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(WidgetSlate.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 13) {
                macroBar("Protein", value: snapshot.proteinEaten, goal: snapshot.proteinGoal, color: WidgetSlate.protein, showValues: true)
                macroBar("Carbs", value: snapshot.carbsEaten, goal: snapshot.carbsGoal, color: WidgetSlate.carbs, showValues: true)
                macroBar("Fat", value: snapshot.fatEaten, goal: snapshot.fatGoal, color: WidgetSlate.fat, showValues: true)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func macroBar(_ title: String, value: Double, goal: Double, color: Color, showValues: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 1)
                if showValues { Text("\(value.intValue)/\(goal.intValue)g").monospacedDigit() }
            }
            .font(.system(size: showValues ? 10 : 9, weight: .semibold))
            .foregroundStyle(WidgetSlate.secondary)
            ProgressView(value: goal > 0 ? min(1, max(0, value / goal)) : 0)
                .tint(color)
                .scaleEffect(x: 1, y: 0.75, anchor: .center)
        }
    }
}

private struct QuickHydrationWidgetView: View {
    let snapshot: MacroWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Water", systemImage: "drop.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetSlate.text)
            Text("\(snapshot.waterConsumedMl)")
                .font(.system(size: 27, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(WidgetSlate.text)
            Text("of \(snapshot.waterGoalMl) ml")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(WidgetSlate.secondary)
            Button(intent: Add250MillilitresIntent()) {
                Label("+250 ml", systemImage: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WidgetSlate.canvas)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(WidgetSlate.text, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .containerBackground(WidgetSlate.canvas, for: .widget)
    }
}

private struct LockScreenProgressWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: MacroWidgetSnapshot

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(snapshot.remainingCalories), in: 0...max(1, snapshot.calorieTarget)) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text("\(snapshot.remainingCalories)")
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
            }
            .gaugeStyle(.accessoryCircular)
        default:
            Text("\(snapshot.remainingCalories) kcal left · \(snapshot.waterConsumedMl) ml · \(snapshot.foodLogStreak)d streak")
        }
    }
}

struct MacroProgressWidget: Widget {
    let kind = "MacroEngineProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MacroWidgetProvider()) { entry in
            MacroProgressWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("MacroEngine Progress")
        .description("Calories and daily macro progress at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickHydrationWidget: Widget {
    let kind = "MacroEngineQuickHydrationWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MacroWidgetProvider()) { entry in
            QuickHydrationWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Quick Hydration")
        .description("Add 250 ml to your daily water tracker.")
        .supportedFamilies([.systemSmall])
    }
}

struct LockScreenProgressWidget: Widget {
    let kind = "MacroEngineLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MacroWidgetProvider()) { entry in
            LockScreenProgressWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("MacroEngine Lock Screen")
        .description("See remaining calories, hydration and your logging streak.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

@main
struct MacroEngineWidgetBundle: WidgetBundle {
    var body: some Widget {
        MacroProgressWidget()
        QuickHydrationWidget()
        LockScreenProgressWidget()
    }
}
