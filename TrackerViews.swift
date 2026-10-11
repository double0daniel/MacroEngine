import SwiftUI
import UIKit

struct WorkoutJournalCard: View {
    @Environment(DiaryStore.self) private var diary
    @State private var showingWorkoutForm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Label("Workout journal", systemImage: "figure.run")
                    .font(.meHeadline)
                    .foregroundStyle(Slate.textPrimary)
                Spacer()
                Text("\(diary.caloriesBurnedToday) kcal burned")
                    .font(.meCaption)
                    .foregroundStyle(Accent.calories)
                    .multilineTextAlignment(.trailing)
            }

            if diary.todaysWorkouts.isEmpty {
                Text("Log a workout to include its calories in today's net total.")
                    .font(.meBody)
                    .foregroundStyle(Slate.textSecondary)
            } else {
                ForEach(diary.todaysWorkouts) { workout in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .foregroundStyle(Slate.textSecondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workout.type)
                                .font(.meBody.weight(.semibold))
                                .foregroundStyle(Slate.textPrimary)
                            Text("\(workout.durationMinutes) min · \(workout.caloriesBurned) kcal")
                                .font(.meCaption)
                                .foregroundStyle(Slate.textSecondary)
                            if !workout.notes.isEmpty {
                                Text(workout.notes)
                                    .font(.meCaption)
                                    .foregroundStyle(Slate.textTertiary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) { diary.removeWorkout(workout) } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Slate.textTertiary)
                        }
                        .accessibilityLabel("Delete \(workout.type) workout")
                    }
                    .padding(11)
                    .background(Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            Button { showingWorkoutForm = true } label: {
                Label("Log workout", systemImage: "plus")
                    .font(.meBody.weight(.semibold))
                    .foregroundStyle(Slate.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Slate.surfaceRaised, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .card()
        .sheet(isPresented: $showingWorkoutForm) {
            WorkoutEntryForm { type, duration, notes, calories in
                diary.addWorkout(type: type, durationMinutes: duration, notes: notes, caloriesBurned: calories)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private struct WorkoutEntryForm: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String, Int, String, Int) -> Void

    @State private var type = ""
    @State private var duration = ""
    @State private var notes = ""
    @State private var calories = ""

    private var valid: Bool {
        !type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (Int(duration) ?? 0) > 0 && (Int(calories) ?? -1) >= 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    field("Workout type", text: $type, prompt: "Strength training, run…")
                    HStack(spacing: 12) {
                        field("Duration (min)", text: $duration, prompt: "45", keyboard: .numberPad)
                        field("Calories burned", text: $calories, prompt: "250", keyboard: .numberPad)
                    }
                    field("Notes", text: $notes, prompt: "Optional details", axis: .vertical)
                    Button {
                        guard let durationValue = Int(duration), let caloriesValue = Int(calories), valid else { return }
                        onSave(type, durationValue, notes, caloriesValue)
                        dismiss()
                    } label: {
                        Text("Save workout")
                    }
                    .buttonStyle(.primary)
                    .disabled(!valid)
                }
                .padding(20)
            }
            .slateScreen()
            .navigationTitle("Log workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Slate.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Slate.textPrimary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func field(_ title: String, text: Binding<String>, prompt: String,
                       keyboard: UIKeyboardType = .default, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.meCaption).foregroundStyle(Slate.textSecondary)
            TextField(prompt, text: text, axis: axis)
                .keyboardType(keyboard)
                .lineLimit(axis == .vertical ? 3...5 : 1...1)
                .foregroundStyle(Slate.textPrimary)
                .padding(12)
                .background(Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WaterTrackerCard: View {
    @Environment(DiaryStore.self) private var diary

    private var progress: Double {
        diary.waterGoalMl > 0 ? Double(diary.waterConsumedTodayMl) / Double(diary.waterGoalMl) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Water", systemImage: "drop.fill")
                    .font(.meHeadline)
                    .foregroundStyle(Slate.textPrimary)
                Spacer()
                Text("\(diary.waterConsumedTodayMl) / \(diary.waterGoalMl) ml")
                    .font(.meCaption.monospacedDigit())
                    .foregroundStyle(Slate.textSecondary)
            }

            BarGauge(progress: progress, color: Accent.fat, height: 9)
            Text(progress >= 1 ? "Daily water goal reached" : "\(max(0, diary.waterGoalMl - diary.waterConsumedTodayMl)) ml to your daily goal")
                .font(.meCaption)
                .foregroundStyle(Slate.textTertiary)

            HStack(spacing: 10) {
                addButton(250)
                addButton(500)
            }

            HStack {
                Text("Daily goal")
                    .font(.meCaption)
                    .foregroundStyle(Slate.textSecondary)
                Spacer()
                Stepper("\(diary.waterGoalMl) ml", value: Binding(
                    get: { diary.waterGoalMl },
                    set: { diary.setWaterGoal($0) }
                ), in: 500...5000, step: 250)
                .labelsHidden()
                Text("\(diary.waterGoalMl) ml")
                    .font(.meCaption.monospacedDigit())
                    .foregroundStyle(Slate.textPrimary)
            }
        }
        .card()
    }

    private func addButton(_ amount: Int) -> some View {
        Button { diary.addWater(amount) } label: {
            Text("+\(amount) ml")
                .font(.meBody.weight(.semibold))
                .foregroundStyle(Slate.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Slate.surfaceRaised, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SupplementTrackerCard: View {
    @Environment(DiaryStore.self) private var diary
    @State private var showingManager = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Supplements", systemImage: "pills.fill")
                    .font(.meHeadline)
                    .foregroundStyle(Slate.textPrimary)
                Spacer()
                Text("\(diary.todaysSupplementIDs.intersection(Set(diary.supplements.map(\.id))).count)/\(diary.supplements.count) done")
                    .font(.meCaption)
                    .foregroundStyle(Slate.textSecondary)
            }

            ForEach(diary.supplements) { supplement in
                let isDone = diary.todaysSupplementIDs.contains(supplement.id)
                Button { diary.toggleSupplement(supplement.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: supplement.symbol)
                            .foregroundStyle(isDone ? Accent.fat : Slate.textSecondary)
                            .frame(width: 22)
                        Text(supplement.name)
                            .font(.meBody)
                            .foregroundStyle(Slate.textPrimary)
                        Spacer()
                        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isDone ? Accent.fat : Slate.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isDone ? "Mark \(supplement.name) incomplete" : "Mark \(supplement.name) complete")")
            }

            Button { showingManager = true } label: {
                Label("Manage supplements", systemImage: "slider.horizontal.3")
                    .font(.meCaption.weight(.semibold))
                    .foregroundStyle(Slate.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
            .buttonStyle(.plain)
        }
        .card()
        .sheet(isPresented: $showingManager) {
            SupplementManagerView()
        }
    }
}

private struct SupplementManagerView: View {
    @Environment(DiaryStore.self) private var diary
    @Environment(\.dismiss) private var dismiss
    @State private var showingAdd = false
    @State private var editingSupplement: SupplementItem?

    var body: some View {
        NavigationStack {
            List {
                ForEach(diary.supplements) { supplement in
                    Button { editingSupplement = supplement } label: {
                        HStack(spacing: 12) {
                            Image(systemName: supplement.symbol)
                                .foregroundStyle(Slate.textPrimary)
                                .frame(width: 24)
                            Text(supplement.name)
                                .foregroundStyle(Slate.textPrimary)
                            Spacer()
                            Image(systemName: "pencil")
                                .font(.meCaption)
                                .foregroundStyle(Slate.textTertiary)
                        }
                    }
                    .listRowBackground(Slate.surface)
                    .swipeActions {
                        Button(role: .destructive) { diary.removeSupplement(supplement) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Slate.background)
            .navigationTitle("Supplements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Slate.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Slate.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                    .foregroundStyle(Slate.textPrimary)
                }
            }
            .sheet(isPresented: $showingAdd) {
                SupplementEditorView { name, symbol in
                    diary.saveSupplement(SupplementItem(id: UUID().uuidString, name: name, symbol: symbol))
                }
            }
            .sheet(item: $editingSupplement) { item in
                SupplementEditorView(supplement: item) { name, symbol in
                    diary.saveSupplement(SupplementItem(id: item.id, name: name, symbol: symbol))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct SupplementEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let supplement: SupplementItem?
    let onSave: (String, String) -> Void
    @State private var name: String
    @State private var symbol: String

    private let symbols = ["pill.fill", "cross.vial.fill", "flame.fill", "leaf.fill", "drop.fill", "bolt.fill", "fish.fill", "sun.max.fill"]

    init(supplement: SupplementItem? = nil, onSave: @escaping (String, String) -> Void) {
        self.supplement = supplement
        self.onSave = onSave
        _name = State(initialValue: supplement?.name ?? "")
        _symbol = State(initialValue: supplement?.symbol ?? "pill.fill")
    }

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Name").font(.meCaption).foregroundStyle(Slate.textSecondary)
                    TextField("e.g. Creatine", text: $name)
                        .foregroundStyle(Slate.textPrimary)
                        .padding(12)
                        .background(Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Icon").font(.meCaption).foregroundStyle(Slate.textSecondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 10) {
                        ForEach(symbols, id: \.self) { choice in
                            Button { symbol = choice } label: {
                                Image(systemName: choice)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(symbol == choice ? Slate.background : Slate.textPrimary)
                                    .frame(width: 48, height: 44)
                                    .background(symbol == choice ? Slate.textPrimary : Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice)
                        }
                    }
                }
                Button("Save Supplement") {
                    onSave(cleanName, symbol)
                    dismiss()
                }
                .buttonStyle(.primary)
                .disabled(cleanName.isEmpty)
                Spacer(minLength: 0)
            }
            .padding(20)
            .slateScreen()
            .navigationTitle(supplement == nil ? "Add Supplement" : "Edit Supplement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Slate.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Slate.textPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

struct TrainingJournalCard: View {
    @Environment(DiaryStore.self) private var diary
    @State private var showingNewEntry = false
    @State private var showingHistory = false
    @State private var editingEntry: TrainingReflectionEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Training journal", systemImage: "book.closed.fill")
                    .font(.meHeadline)
                    .foregroundStyle(Slate.textPrimary)
                Spacer()
                Button("History") { showingHistory = true }
                    .font(.meCaption.weight(.semibold))
                    .foregroundStyle(Slate.textSecondary)
            }

            if diary.todaysTrainingReflections.isEmpty {
                Text("Capture a win, a focus area, and how the session felt.")
                    .font(.meBody)
                    .foregroundStyle(Slate.textSecondary)
            } else {
                ForEach(diary.todaysTrainingReflections) { entry in
                    Button { editingEntry = entry } label: {
                        reflectionSummary(entry)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button { showingNewEntry = true } label: {
                Label("Add reflection", systemImage: "plus")
                    .font(.meBody.weight(.semibold))
                    .foregroundStyle(Slate.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Slate.surfaceRaised, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .card()
        .sheet(isPresented: $showingNewEntry) {
            TrainingReflectionEditorView { diary.saveTrainingReflection($0) }
        }
        .sheet(item: $editingEntry) { entry in
            TrainingReflectionEditorView(entry: entry) { diary.saveTrainingReflection($0) }
        }
        .sheet(isPresented: $showingHistory) {
            TrainingJournalHistoryView()
        }
    }

    @ViewBuilder
    private func reflectionSummary(_ entry: TrainingReflectionEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.sessionTag.isEmpty ? "Training session" : entry.sessionTag)
                    .font(.meBody.weight(.semibold))
                    .foregroundStyle(Slate.textPrimary)
                Spacer()
                Text("RPE \(entry.rpe)/10")
                    .font(.meCaption)
                    .foregroundStyle(Slate.textSecondary)
            }
            if !entry.keyWins.isEmpty { journalLine("Win", entry.keyWins) }
            if !entry.focusAreas.isEmpty { journalLine("Focus", entry.focusAreas) }
            if !entry.workoutNotes.isEmpty { journalLine("Notes", entry.workoutNotes) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: 13))
        .contentShape(Rectangle())
    }

    private func journalLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.5)
                .foregroundStyle(Slate.textTertiary)
            Text(value).font(.meCaption).foregroundStyle(Slate.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TrainingReflectionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: TrainingReflectionEntry?
    let onSave: (TrainingReflectionEntry) -> Void
    @State private var keyWins: String
    @State private var focusAreas: String
    @State private var workoutNotes: String
    @State private var rpe: Int
    @State private var sessionTag: String

    init(entry: TrainingReflectionEntry? = nil, onSave: @escaping (TrainingReflectionEntry) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _keyWins = State(initialValue: entry?.keyWins ?? "")
        _focusAreas = State(initialValue: entry?.focusAreas ?? "")
        _workoutNotes = State(initialValue: entry?.workoutNotes ?? "")
        _rpe = State(initialValue: entry?.rpe ?? 5)
        _sessionTag = State(initialValue: entry?.sessionTag ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    textField("Session tag", text: $sessionTag, prompt: "Leg day, tempo run…")
                    textField("What went well", text: $keyWins, prompt: "Key wins or personal records", multiline: true)
                    textField("What needs work", text: $focusAreas, prompt: "Focus areas for next time", multiline: true)
                    textField("Workout notes", text: $workoutNotes, prompt: "General session notes", multiline: true)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Exertion (RPE)").font(.meBody).foregroundStyle(Slate.textPrimary)
                            Spacer()
                            Text("\(rpe)/10").font(.meNumber).foregroundStyle(Slate.textPrimary)
                        }
                        Slider(value: Binding(get: { Double(rpe) }, set: { rpe = Int($0.rounded()) }), in: 1...10, step: 1)
                            .tint(Slate.textPrimary)
                    }
                    Button(entry == nil ? "Save Reflection" : "Update Reflection") {
                        let saved = TrainingReflectionEntry(
                            id: entry?.id ?? UUID(), date: entry?.date ?? .now,
                            keyWins: keyWins.trimmingCharacters(in: .whitespacesAndNewlines),
                            focusAreas: focusAreas.trimmingCharacters(in: .whitespacesAndNewlines),
                            workoutNotes: workoutNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                            rpe: rpe,
                            sessionTag: sessionTag.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        onSave(saved)
                        dismiss()
                    }
                    .buttonStyle(.primary)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.immediately)
            .scrollIndicators(.hidden)
            .slateScreen()
            .navigationTitle(entry == nil ? "New Reflection" : "Edit Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Slate.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Slate.textPrimary) } }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private func textField(_ title: String, text: Binding<String>, prompt: String, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.meCaption).foregroundStyle(Slate.textSecondary)
            TextField(prompt, text: text, axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 3...5 : 1...1)
                .foregroundStyle(Slate.textPrimary)
                .padding(12)
                .background(Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct TrainingJournalHistoryView: View {
    @Environment(DiaryStore.self) private var diary
    @Environment(\.dismiss) private var dismiss
    @State private var editingEntry: TrainingReflectionEntry?

    var body: some View {
        NavigationStack {
            List {
                if diary.trainingReflections.isEmpty {
                    Text("Your saved reflections will appear here.")
                        .foregroundStyle(Slate.textSecondary)
                        .listRowBackground(Slate.surface)
                }
                ForEach(diary.trainingReflections) { entry in
                    Button { editingEntry = entry } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(entry.sessionTag.isEmpty ? "Training session" : entry.sessionTag)
                                    .font(.meBody.weight(.semibold))
                                Spacer()
                                Text(entry.date, format: .dateTime.month(.abbreviated).day())
                                    .font(.meCaption)
                            }
                            Text("RPE \(entry.rpe)/10 · \([entry.keyWins, entry.focusAreas, entry.workoutNotes].first(where: { !$0.isEmpty }) ?? "No notes")")
                                .font(.meCaption)
                                .lineLimit(2)
                                .foregroundStyle(Slate.textSecondary)
                        }
                        .foregroundStyle(Slate.textPrimary)
                    }
                    .listRowBackground(Slate.surface)
                    .swipeActions {
                        Button(role: .destructive) { diary.removeTrainingReflection(entry) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Slate.background)
            .navigationTitle("Journal History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Slate.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.foregroundStyle(Slate.textPrimary) } }
            .sheet(item: $editingEntry) { entry in
                TrainingReflectionEditorView(entry: entry) { diary.saveTrainingReflection($0) }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct BodyMeasurementsCard: View {
    @Environment(DiaryStore.self) private var diary
    @State private var bodyFat = ""
    @State private var waist = ""
    @State private var hips = ""
    @State private var chest = ""
    @State private var loaded = false

    private var latest: BodyMeasurementEntry? { diary.bodyMeasurements.last }
    private var values: [String] { [bodyFat, waist, hips, chest] }
    private var hasValue: Bool { values.contains { Double($0).map { $0.isFinite && $0 > 0 } ?? false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Body measurements", systemImage: "ruler")
                .font(.meHeadline).foregroundStyle(Slate.textPrimary)
            Text("Optional check-ins help add context to your weight trend.")
                .font(.meCaption).foregroundStyle(Slate.textSecondary)
            HStack(spacing: 10) {
                measureField("Body fat %", text: $bodyFat)
                measureField("Waist cm", text: $waist)
            }
            HStack(spacing: 10) {
                measureField("Hips cm", text: $hips)
                measureField("Chest cm", text: $chest)
            }
            Button("Save today's measurements") {
                diary.saveBodyMeasurements(BodyMeasurementEntry(
                    date: .now,
                    bodyFatPercent: parsed(bodyFat), waistCm: parsed(waist),
                    hipsCm: parsed(hips), chestCm: parsed(chest)
                ))
            }
            .font(.meCaption.weight(.semibold))
            .foregroundStyle(Slate.textPrimary)
            .disabled(!hasValue)
            if let latest {
                Text("Latest saved: \(latest.date, format: .dateTime.month(.abbreviated).day())")
                    .font(.meCaption).foregroundStyle(Slate.textTertiary)
            }
            ForEach(diary.bodyMeasurements.suffix(3).reversed()) { entry in
                HStack(alignment: .top) {
                    Text(entry.date, format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(Slate.textTertiary)
                    Spacer(minLength: 8)
                    Text(measurementSummary(entry))
                        .foregroundStyle(Slate.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
                .font(.system(size: 11, weight: .medium))
            }
        }
        .card()
        .onAppear(perform: loadLatest)
        .onChange(of: diary.bodyMeasurements) { _, _ in loadLatest() }
    }

    private func measureField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Slate.textSecondary)
            TextField("—", text: text).keyboardType(.decimalPad).font(.meBody).foregroundStyle(Slate.textPrimary)
                .padding(10).background(Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func parsed(_ text: String) -> Double? {
        guard let value = Double(text), value.isFinite, value > 0 else { return nil }
        return value
    }

    private func measurementSummary(_ entry: BodyMeasurementEntry) -> String {
        [
            entry.bodyFatPercent.map { String(format: "%.1f%% fat", $0) },
            entry.waistCm.map { String(format: "%.1f cm waist", $0) },
            entry.hipsCm.map { String(format: "%.1f cm hips", $0) },
            entry.chestCm.map { String(format: "%.1f cm chest", $0) }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func loadLatest() {
        guard !loaded, let latest else { return }
        bodyFat = latest.bodyFatPercent.map { String($0) } ?? ""
        waist = latest.waistCm.map { String($0) } ?? ""
        hips = latest.hipsCm.map { String($0) } ?? ""
        chest = latest.chestCm.map { String($0) } ?? ""
        loaded = true
    }
}
