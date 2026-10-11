import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(DiaryStore.self) private var diary
    @AppStorage("userName") private var userName = ""
    @State private var searchCategory: MealCategory?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    coachInsight
                    if diary.dashboardLayout.allSatisfy({ !$0.isEnabled }) {
                        EmptyStateView(
                            symbol: "rectangle.3.group",
                            title: "No dashboard cards enabled",
                            message: "Choose the cards you want to see in Settings."
                        )
                        .card(padding: 8)
                    } else {
                        ForEach(diary.dashboardLayout.filter(\.isEnabled)) { preference in
                            dashboardSection(preference.section)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .slateScreen()
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { addButton }
        }
        .sheet(item: $searchCategory) { category in
            FoodSearchView(initialCategory: category)
        }
        .preferredColorScheme(.dark)
    }

    private var coachInsight: some View {
        HStack(alignment: .center, spacing: 12) {
            MascotAvatarView(state: mascotState, size: .regular, layout: .badge)
            VStack(alignment: .leading, spacing: 5) {
                Text("Hey \(greetingName), here's your daily breakdown")
                    .font(.meHeadline)
                    .foregroundStyle(Slate.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.meBody)
                    .foregroundStyle(Slate.textSecondary)
                if let profile = diary.profile {
                    Text("\(profile.goal.titleForDashboard) · targets personalised")
                        .font(.meCaption)
                        .foregroundStyle(Slate.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var greetingName: String {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "there" : name
    }

    private var mascotState: MascotState {
        let calorieTarget = diary.adjustedDailyCalorieTarget
        let calorieGoalReached = calorieTarget > 0 && diary.totals.calories >= calorieTarget
        let proteinGoalReached = diary.goals.protein > 0 && diary.totals.protein >= diary.goals.protein
        if calorieGoalReached || proteinGoalReached { return .celebrating }
        if diary.totals.calories > 0 || diary.totals.protein > 0 { return .coaching }
        return .neutral
    }

    private var addButton: some View {
        Button {
            searchCategory = .snacks
        } label: {
            Label("Add food", systemImage: "plus")
        }
        .buttonStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background {
            LinearGradient(
                colors: [Slate.background.opacity(0), Slate.background],
                startPoint: .top,
                endPoint: .init(x: 0.5, y: 0.35)
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func dashboardSection(_ section: DashboardSection) -> some View {
        switch section {
        case .calorieSummary:
            CalorieSummaryCard(eaten: diary.totals.calories, burned: diary.caloriesBurnedToday,
                               goal: diary.adjustedDailyCalorieTarget,
                               baseTarget: diary.goals.calories,
                               rolloverAdjustment: diary.rolloverAdjustment)
        case .macroRings:
            MacroSegmentSummaryCard(totals: diary.totals, goals: diary.goals)
        case .macroBreakdown:
            MacroBreakdownCard(totals: diary.totals, goals: diary.goals)
        case .mealLogs:
            DiarySection(
                entries: diary.todaysEntries,
                onDelete: { diary.remove($0) },
                onAdd: { searchCategory = $0 }
            )
        case .waterTracker:
            WaterTrackerCard()
        case .supplementTracker:
            SupplementTrackerCard()
        case .workoutJournal:
            WorkoutJournalCard()
        }
    }
}

private extension GoalApproach {
    var titleForDashboard: String { title }
}

struct TelemetryView: View {
    @Environment(DiaryStore.self) private var diary

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Telemetry")
                            .font(.system(.largeTitle, weight: .bold))
                            .foregroundStyle(Slate.textPrimary)
                        Text("Progress trends and training reflections")
                            .font(.meBody)
                            .foregroundStyle(Slate.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    WeightTelemetryCard()
                    BodyMeasurementsCard()
                    TrainingJournalCard()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .slateScreen()
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Calorie hero

struct CalorieSummaryCard: View {
    let eaten: Double
    var burned: Int = 0
    let goal: Double
    var baseTarget: Double? = nil
    var rolloverAdjustment: Int = 0

    private var net: Double { eaten - Double(max(0, burned)) }
    private var remaining: Double { goal - net }
    private var progress: Double { goal > 0 ? net / goal : 0 }

    var body: some View {
        VStack(spacing: 22) {
            RingGauge(progress: progress, color: Accent.calories, lineWidth: 16) {
                VStack(spacing: 2) {
                    Text("\(abs(remaining).whole)")
                        .font(.meDisplay)
                        .foregroundStyle(Slate.textPrimary)
                    Text(remaining >= 0 ? "kcal left" : "kcal over")
                        .font(.meBody)
                        .foregroundStyle(Slate.textSecondary)
                }
            }
            .frame(width: 200, height: 200)

            HStack(spacing: 0) {
                stat(title: "Eaten", value: eaten.whole, symbol: "flame.fill", tinted: true)
                Rectangle().fill(Slate.stroke).frame(width: 1, height: 32)
                stat(title: "Burned", value: max(0, burned), symbol: "figure.run", tinted: false)
                Rectangle().fill(Slate.stroke).frame(width: 1, height: 32)
                stat(title: "Adjusted", value: goal.whole, symbol: "target", tinted: false)
            }

            HStack(alignment: .top, spacing: 8) {
                targetDetail(title: "Base Target", value: "\((baseTarget ?? goal).whole) kcal", color: Slate.textSecondary)
                targetDetail(title: "Rollover Adjustment", value: "\(rolloverAdjustment >= 0 ? "+" : "")\(rolloverAdjustment) kcal",
                             color: rolloverAdjustment > 0 ? Accent.fat : Slate.textSecondary)
                targetDetail(title: "Adjusted Net Target", value: "\(goal.whole) kcal", color: Slate.textPrimary)
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories")
        .accessibilityValue("\(eaten.whole) eaten, \(max(0, burned)) burned, base target \((baseTarget ?? goal).whole), rollover adjustment \(rolloverAdjustment), adjusted net target \(goal.whole). \(abs(remaining).whole) \(remaining >= 0 ? "left" : "over").")
    }

    private func stat(title: String, value: Int, symbol: String, tinted: Bool) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tinted ? Accent.calories : Slate.textTertiary)
                Text(title)
                    .font(.meBody)
                    .foregroundStyle(Slate.textSecondary)
            }
            Text("\(value)")
                .font(.meNumber)
                .foregroundStyle(Slate.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    private func targetDetail(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Slate.textTertiary)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Three-segment branded macro ring

struct MacroSegmentSummaryCard: View {
    let totals: Macros
    let goals: Macros

    private let starts: [CGFloat] = [0.0467, 0.3800, 0.7133]
    private let segmentLength: CGFloat = 0.24

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                ForEach(0..<MacroKind.macros.count, id: \.self) { index in
                    let kind = MacroKind.macros[index]
                    Circle()
                        .trim(from: starts[index], to: starts[index] + segmentLength)
                        .stroke(Slate.track, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Circle()
                        .trim(from: starts[index], to: starts[index] + segmentLength * progress(for: kind))
                        .stroke(kind.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .opacity(progress(for: kind) > 0.001 ? 1 : 0)
                }
                Image(systemName: "bolt.fill")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(Slate.textPrimary)
            }
            .frame(width: 118, height: 118)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 11) {
                Text("Macro balance")
                    .font(.meHeadline)
                    .foregroundStyle(Slate.textPrimary)
                ForEach(MacroKind.macros) { kind in
                    HStack(spacing: 7) {
                        Circle().fill(kind.color).frame(width: 7, height: 7)
                        Text(kind.title)
                            .font(.meCaption)
                            .foregroundStyle(Slate.textSecondary)
                        Spacer(minLength: 2)
                        Text("\(totals[kind].whole)/\(goals[kind].whole) g")
                            .font(.system(.caption, design: .rounded, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Slate.textPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card(padding: 18)
        .accessibilityElement(children: .contain)
    }

    private func progress(for kind: MacroKind) -> CGFloat {
        guard goals[kind] > 0 else { return 0 }
        return CGFloat(min(max(totals[kind] / goals[kind], 0), 1))
    }
}

// MARK: - Macro breakdown rows

struct MacroBreakdownCard: View {
    let totals: Macros
    let goals: Macros

    var body: some View {
        VStack(spacing: 0) {
            ForEach(MacroKind.macros) { kind in
                MacroProgressRow(kind: kind, value: totals[kind], goal: goals[kind])
                if kind != MacroKind.macros.last {
                    Divider().overlay(Slate.stroke).padding(.vertical, 14)
                }
            }
        }
        .card(padding: 18)
    }
}

struct MacroProgressRow: View {
    let kind: MacroKind
    let value: Double
    let goal: Double

    var body: some View {
        HStack(spacing: 14) {
            MacroIcon(kind: kind)

            VStack(alignment: .leading, spacing: 8) {
                Text(kind.title)
                    .font(.meBody)
                    .foregroundStyle(Slate.textSecondary)
                BarGauge(progress: goal > 0 ? value / goal : 0, color: kind.color)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(value.whole) g")
                    .font(.meNumber)
                    .foregroundStyle(Slate.textPrimary)
                Text("of \(goal.whole) g")
                    .font(.meCaption)
                    .foregroundStyle(Slate.textTertiary)
            }
            .frame(minWidth: 64, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
        .accessibilityValue("\(value.whole) of \(goal.whole) grams")
    }
}

// MARK: - Meal diary grouped by category

struct DiarySection: View {
    @Environment(DiaryStore.self) private var diary
    @State private var entryToRate: DiaryEntry?
    let entries: [DiaryEntry]
    let onDelete: (DiaryEntry) -> Void
    let onAdd: (MealCategory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's meals")
                .font(.meHeadline)
                .foregroundStyle(Slate.textPrimary)
                .accessibilityAddTraits(.isHeader)

            ForEach(MealCategory.allCases) { category in
                mealCard(category)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $entryToRate) { entry in
            SatietyRatingEditor(entry: entry) { rating in
                diary.updateSatietyRating(rating, for: entry)
            }
        }
    }

    private func mealCard(_ category: MealCategory) -> some View {
        let categoryEntries = entries.filter { $0.category == category }
        let calories = categoryEntries.reduce(0.0) { $0 + $1.macros.calories }

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: category.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Slate.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.meHeadline)
                        .foregroundStyle(Slate.textPrimary)
                    Text("\(categoryEntries.count) items · \(calories.whole) kcal")
                        .font(.meCaption)
                        .foregroundStyle(Slate.textSecondary)
                }
                Spacer(minLength: 8)
                Button { onAdd(category) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Slate.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(Slate.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add food to \(category.title)")
            }
            .padding(14)

            if !categoryEntries.isEmpty {
                Divider().overlay(Slate.stroke)
                ForEach(categoryEntries) { entry in
                    DiaryEntryRow(entry: entry) {
                        entryToRate = entry
                    }
                        .contextMenu {
                            Button(role: .destructive) { onDelete(entry) } label: {
                                Label("Remove entry", systemImage: "trash")
                            }
                        }
                    if entry.id != categoryEntries.last?.id {
                        Divider().overlay(Slate.stroke).padding(.leading, 16)
                    }
                }
            } else {
                Text("Nothing logged yet")
                    .font(.meCaption)
                    .foregroundStyle(Slate.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .background(Slate.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Slate.stroke.opacity(0.6), lineWidth: 1))
    }
}

struct DiaryEntryRow: View {
    let entry: DiaryEntry
    let onRate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.food.name)
                        .font(.meHeadline)
                        .foregroundStyle(Slate.textPrimary)
                        .lineLimit(1)
                    Text("\(entry.grams.whole) g" + (entry.food.brand.map { " · \($0)" } ?? ""))
                        .font(.meBody)
                        .foregroundStyle(Slate.textSecondary)
                        .lineLimit(1)
                    MacroChips(macros: entry.macros)
                        .padding(.top, 2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(entry.macros.calories.whole)")
                        .font(.meNumber)
                        .foregroundStyle(Slate.textPrimary)
                    Text("kcal")
                        .font(.meCaption)
                        .foregroundStyle(Slate.textTertiary)
                }
            }
            Button(action: onRate) {
                Label {
                    if let rating = entry.satietyRating {
                        Text("Satiety \(rating.satietyScore)/5 · Energy \(rating.energyScore)/5")
                    } else {
                        Text("Rate satiety & energy")
                    }
                } icon: {
                    Image(systemName: "heart.text.square.fill")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(entry.satietyRating == nil ? Slate.textSecondary : Slate.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Slate.surfaceRaised, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }
}

struct SatietyRatingEditor: View {
    @Environment(\.dismiss) private var dismiss
    let entry: DiaryEntry
    let onSave: (SatietyRating?) -> Void
    @State private var satietyScore: Int
    @State private var energyScore: Int

    init(entry: DiaryEntry, onSave: @escaping (SatietyRating?) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _satietyScore = State(initialValue: entry.satietyRating?.satietyScore ?? 3)
        _energyScore = State(initialValue: entry.satietyRating?.energyScore ?? 3)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Text(entry.customMealName ?? entry.food.name)
                    .font(.meHeadline)
                    .foregroundStyle(Slate.textPrimary)
                ratingControl(title: "Satiety", detail: "1 Hungry · 5 Very Full", score: $satietyScore)
                ratingControl(title: "Energy", detail: "1 Sluggish · 5 High Energy", score: $energyScore)
                Button("Save Rating") {
                    onSave(SatietyRating(satietyScore: satietyScore, energyScore: energyScore))
                    dismiss()
                }
                .buttonStyle(.primary)
                if entry.satietyRating != nil {
                    Button("Remove Rating", role: .destructive) {
                        onSave(nil)
                        dismiss()
                    }
                    .font(.meBody.weight(.semibold))
                    .foregroundStyle(Slate.textSecondary)
                    .frame(maxWidth: .infinity)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .slateScreen()
            .navigationTitle("Meal Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Slate.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Slate.textPrimary)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private func ratingControl(title: String, detail: String, score: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.meHeadline).foregroundStyle(Slate.textPrimary)
            Text(detail).font(.meCaption).foregroundStyle(Slate.textSecondary)
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { value in
                    Button { score.wrappedValue = value } label: {
                        Text("\(value)")
                            .font(.meBody.weight(.semibold))
                            .foregroundStyle(score.wrappedValue == value ? Slate.background : Slate.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(score.wrappedValue == value ? Slate.textPrimary : Slate.surfaceRaised,
                                        in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Weight logging + long-term telemetry

struct WeightTelemetryCard: View {
    @Environment(DiaryStore.self) private var diary
    @State private var weightInput = ""
    @State private var inputError: String?

    private var sortedEntries: [WeightEntry] { diary.weightEntries.sorted { $0.date < $1.date } }
    private var latest: WeightEntry? { sortedEntries.last }
    private var firstWeight: WeightEntry? { sortedEntries.first }
    private var overallChange: Double? {
        guard let firstWeight, let latest, sortedEntries.count > 1 else { return nil }
        return latest.weightKg - firstWeight.weightKg
    }
    private var chartDomain: ClosedRange<Double> {
        let values = sortedEntries.map(\.weightKg)
        guard let minimum = values.min(), let maximum = values.max() else { return 0...100 }
        let padding = max((maximum - minimum) * 0.2, 1)
        return max(0, minimum - padding)...(maximum + padding)
    }

    /// Compares the averages at either end of the latest 21-day window to reduce
    /// the influence of normal day-to-day scale fluctuations.
    private var recentTrendInsight: String? {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -21, to: .now) else { return nil }
        let recent = sortedEntries.filter { $0.date >= cutoff }
        guard recent.count >= 4,
              let first = recent.first,
              let last = recent.last,
              last.date.timeIntervalSince(first.date) >= 14 * 24 * 60 * 60 else { return nil }

        let sampleCount = max(1, recent.count / 3)
        let early = recent.prefix(sampleCount).map(\.weightKg)
        let late = recent.suffix(sampleCount).map(\.weightKg)
        let earlyAverage = early.reduce(0, +) / Double(early.count)
        let lateAverage = late.reduce(0, +) / Double(late.count)
        let change = lateAverage - earlyAverage

        if abs(change) < 0.3 {
            return "Weight has been broadly stable in recent weeks — a possible plateau. Compare the trend over several weeks before changing targets."
        }
        return String(format: "Recent trend: %+.1f kg between early and recent readings.", change)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weight trend")
                        .font(.meHeadline)
                        .foregroundStyle(Slate.textPrimary)
                    Text("Your long-term trend, in kilograms")
                        .font(.meCaption)
                        .foregroundStyle(Slate.textSecondary)
                }
                Spacer()
                if let latest {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f kg", latest.weightKg))
                            .font(.meNumber)
                            .foregroundStyle(Slate.textPrimary)
                        if let overallChange {
                            Text(String(format: "%+.1f kg overall", overallChange))
                                .font(.meCaption)
                                .foregroundStyle(Slate.textSecondary)
                        }
                    }
                }
            }

            if sortedEntries.count >= 2 {
                Chart(sortedEntries) { entry in
                    LineMark(
                        x: .value("Date", entry.date),
                        y: .value("Weight", entry.weightKg)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Slate.textPrimary)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("Date", entry.date),
                        y: .value("Weight", entry.weightKg)
                    )
                    .foregroundStyle(Slate.textSecondary)
                    .symbolSize(24)
                }
                .chartYScale(domain: chartDomain)
                .chartYAxisLabel("kg")
                .frame(height: 170)
                .accessibilityLabel("Weight history chart")
            } else {
                EmptyStateView(
                    symbol: "chart.xyaxis.line",
                    title: "Your trend starts here",
                    message: "Log weight on different days to see your progress over weeks and months. Daily fluctuations are normal."
                )
                .padding(.vertical, 2)
            }

            if let recentTrendInsight {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(Slate.textTertiary)
                    Text(recentTrendInsight)
                        .font(.meCaption)
                        .foregroundStyle(Slate.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                TextField("Weight in kg", text: $weightInput)
                    .keyboardType(.decimalPad)
                    .font(.meNumber)
                    .foregroundStyle(Slate.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Slate.stroke.opacity(0.7), lineWidth: 1))

                Button("Log weight") { saveWeight() }
                    .buttonStyle(.primary)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(parsedWeight == nil)
            }

            if let inputError {
                Text(inputError)
                    .font(.meCaption)
                    .foregroundStyle(Accent.calories)
            }
        }
        .card(padding: 18)
        .onAppear {
            if weightInput.isEmpty, let latest {
                weightInput = String(format: "%.1f", latest.weightKg)
            } else if weightInput.isEmpty, let profile = diary.profile {
                weightInput = String(format: "%.1f", profile.weightKg)
            }
        }
    }

    private var parsedWeight: Double? {
        guard let value = Double(weightInput.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")),
              value.isFinite, (20...500).contains(value) else { return nil }
        return value
    }

    private func saveWeight() {
        guard let weight = parsedWeight else {
            inputError = "Enter a weight between 20 and 500 kg."
            return
        }
        diary.recordWeight(weight)
        inputError = nil
        weightInput = String(format: "%.1f", weight)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

#if DEBUG
#Preview {
    DashboardView()
        .environment(DiaryStore.preview)
        .preferredColorScheme(.dark)
}
#endif
