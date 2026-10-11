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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Supplements", systemImage: "pills.fill")
                    .font(.meHeadline)
                    .foregroundStyle(Slate.textPrimary)
                Spacer()
                Text("\(diary.todaysSupplementIDs.intersection(Set(SupplementItem.defaults.map(\.id))).count)/\(SupplementItem.defaults.count) done")
                    .font(.meCaption)
                    .foregroundStyle(Slate.textSecondary)
            }

            ForEach(SupplementItem.defaults) { supplement in
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
        }
        .card()
    }
}
