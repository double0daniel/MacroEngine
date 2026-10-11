import SwiftUI

struct SettingsView: View {
    @Environment(DiaryStore.self) private var diary
    @State private var goal: PrimaryGoal = .cutting
    @State private var activity: ActivityLevel = .moderatelyActive
    @State private var weightKg = "70"
    @State private var protein = "140"
    @State private var carbs = "200"
    @State private var fat = "65"
    @State private var showingDashboardLayout = false
    @State private var showingResetConfirmation = false
    @FocusState private var isFocused: Bool

    private var baseProfile: UserProfile {
        diary.profile ?? UserProfile(age: 30, sex: .preferNotToSay, heightCm: 170,
                                     weightKg: 70, activityLevel: .moderatelyActive, goal: .maingain)
    }

    private var draftProfile: UserProfile {
        let enteredWeight = Double(weightKg) ?? baseProfile.weightKg
        let selectedApproach: GoalApproach
        switch goal {
        case .cutting:
            selectedApproach = baseProfile.goal.primaryGoal == .cutting ? baseProfile.goal : .fatLoss
        case .bulking:
            selectedApproach = baseProfile.goal.primaryGoal == .bulking ? baseProfile.goal : .leanBulk
        case .maingain:
            selectedApproach = .maingain
        }
        return UserProfile(age: baseProfile.age, sex: baseProfile.sex, heightCm: baseProfile.heightCm,
                           weightKg: min(500, max(20, enteredWeight)),
                           activityLevel: activity, goal: selectedApproach,
                           createdAt: baseProfile.createdAt)
    }

    private var estimate: TargetEstimate { MacroTargetCalculator.estimate(for: draftProfile) }

    private var manualMacros: Macros {
        let proteinGrams = max(0, Double(protein) ?? 0)
        let carbGrams = max(0, Double(carbs) ?? 0)
        let fatGrams = max(0, Double(fat) ?? 0)
        return Macros(calories: proteinGrams * 4 + carbGrams * 4 + fatGrams * 9,
                      protein: proteinGrams, carbs: carbGrams, fat: fatGrams)
    }

    private var validManualMacros: Bool {
        [protein, carbs, fat].allSatisfy { Double($0).map { $0 >= 0 && $0.isFinite } ?? false }
    }

    private var settingsAreCurrent: Bool {
        guard diary.profile == draftProfile else { return false }
        return diary.goals.protein == manualMacros.protein &&
            diary.goals.carbs == manualMacros.carbs &&
            diary.goals.fat == manualMacros.fat
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Settings")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Slate.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                    VStack(alignment: .leading, spacing: 16) {
                        goalCard
                        rolloverCard
                        macroCard
                        dashboardLayoutCard
                        note
                        resetDataCard
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .slateScreen()
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(Slate.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear(perform: loadCurrentSettings)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isFocused = false }
                        .foregroundStyle(Slate.textPrimary)
                }
            }
            .sheet(isPresented: $showingDashboardLayout) {
                DashboardLayoutEditorView()
            }
            .alert("Reset App Data & Onboarding", isPresented: $showingResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset Data", role: .destructive) {
                    diary.resetAppData()
                }
            } message: {
                Text("Are you sure? This will erase all logs, custom meals, and settings, and return to the initial onboarding screen.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Daily goal", systemImage: "target")
                .font(.meHeadline)
                .foregroundStyle(Slate.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Focus")
                    .font(.meCaption)
                    .foregroundStyle(Slate.textSecondary)
                Picker("Goal", selection: $goal) {
                    ForEach(PrimaryGoal.allCases) { option in Text(option.title).tag(option) }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Activity")
                        .font(.meCaption)
                        .foregroundStyle(Slate.textSecondary)
                    Picker("Activity level", selection: $activity) {
                        ForEach(ActivityLevel.allCases) { option in Text(option.title).tag(option) }
                    }
                    .tint(Slate.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Weight (kg)")
                        .font(.meCaption)
                        .foregroundStyle(Slate.textSecondary)
                    TextField("70", text: $weightKg)
                        .focused($isFocused)
                        .keyboardType(.decimalPad)
                        .settingsInput()
                }
                .frame(width: 100)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Estimated TDEE")
                        .font(.meCaption)
                        .foregroundStyle(Slate.textSecondary)
                    Text("\(estimate.tdee.whole) kcal / day")
                        .font(.meNumber)
                        .foregroundStyle(Slate.textPrimary)
                }
                Spacer()
                Button("Recalculate") { recalculateMacros() }
                    .font(.meCaption.weight(.semibold))
                    .foregroundStyle(Slate.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Slate.surfaceRaised, in: Capsule())
            }

            Text("Estimated daily target: \(estimate.targetCalories.whole) kcal")
                .font(.meCaption)
                .foregroundStyle(Slate.textTertiary)
        }
        .card()
    }

    private var macroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Exact macro targets", systemImage: "slider.horizontal.3")
                .font(.meHeadline)
                .foregroundStyle(Slate.textPrimary)
            Text("Calories update from your macro grams: 4 kcal/g protein, 4 kcal/g carbs and 9 kcal/g fat.")
                .font(.meCaption)
                .foregroundStyle(Slate.textSecondary)

            HStack(spacing: 10) {
                macroField("Protein", text: $protein, color: Accent.protein)
                macroField("Carbs", text: $carbs, color: Accent.carbs)
                macroField("Fat", text: $fat, color: Accent.fat)
            }

            HStack {
                Text("Target calories")
                    .font(.meBody)
                    .foregroundStyle(Slate.textSecondary)
                Spacer()
                Text("\(manualMacros.calories.whole) kcal")
                    .font(.meNumber)
                    .foregroundStyle(Slate.textPrimary)
            }

            Button {
                diary.updateProfileAndGoals(draftProfile, goals: manualMacros)
            } label: {
                Text(settingsAreCurrent ? "Settings saved" : "Save settings")
            }
            .buttonStyle(.primary)
            .disabled(!validManualMacros)
        }
        .card()
    }

    private var rolloverCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Rollover Calorie Settings", systemImage: "arrow.left.arrow.right")
                .font(.meHeadline)
                .foregroundStyle(Slate.textPrimary)
            Toggle(isOn: Binding(
                get: { diary.rolloverEnabled },
                set: { diary.setRolloverEnabled($0) }
            )) {
                Text("Track unused calories")
                    .font(.meBody)
                    .foregroundStyle(Slate.textPrimary)
            }
            .tint(Slate.textPrimary)

            Text("Unused calories from logged days add to your bank. Eating above your base target uses the bank. The weekly bank balance is capped at your limit.")
                .font(.meCaption)
                .foregroundStyle(Slate.textSecondary)

            if diary.rolloverEnabled {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Banked calories")
                            .font(.meCaption)
                            .foregroundStyle(Slate.textSecondary)
                        Text("\(diary.bankedCalories) kcal available")
                            .font(.meNumber)
                            .foregroundStyle(Slate.textPrimary)
                    }
                    Spacer()
                    Stepper(value: Binding(
                        get: { diary.maxRolloverCap },
                        set: { diary.setMaxRolloverCap($0) }
                    ), in: 100...2_000, step: 50) {
                        Text("Weekly bank cap: \(diary.maxRolloverCap) kcal")
                            .font(.meCaption.monospacedDigit())
                            .foregroundStyle(Slate.textPrimary)
                    }
                    .fixedSize()
                }
            }
        }
        .card()
    }

    private var note: some View {
        Text("Targets are estimates that you can adjust to suit your needs. They are not medical advice.")
            .font(.meCaption)
            .foregroundStyle(Slate.textTertiary)
            .padding(.horizontal, 4)
    }

    private var dashboardLayoutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Dashboard layout", systemImage: "rectangle.3.group")
                .font(.meHeadline)
                .foregroundStyle(Slate.textPrimary)
            Text("Choose which cards appear and drag to change their order.")
                .font(.meCaption)
                .foregroundStyle(Slate.textSecondary)
            Button("Edit Dashboard Layout") { showingDashboardLayout = true }
                .buttonStyle(.primary)
        }
        .card()
    }

    private var resetDataCard: some View {
        Button {
            showingResetConfirmation = true
        } label: {
            Label("Reset App Data & Onboarding", systemImage: "arrow.counterclockwise")
                .font(.meHeadline)
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Slate.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Slate.stroke.opacity(0.6), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Clears app data and restarts onboarding after confirmation")
    }

    private func macroField(_ title: String, text: Binding<String>, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.meCaption)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            TextField("0", text: text)
                .focused($isFocused)
                .keyboardType(.numberPad)
                .settingsInput()
            Text("grams")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Slate.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadCurrentSettings() {
        guard let profile = diary.profile else { return }
        goal = profile.goal.primaryGoal
        activity = profile.activityLevel
        weightKg = String(profile.weightKg)
        protein = String(diary.goals.protein.whole)
        carbs = String(diary.goals.carbs.whole)
        fat = String(diary.goals.fat.whole)
    }

    private func recalculateMacros() {
        let values = estimate.macros
        protein = String(values.protein.whole)
        carbs = String(values.carbs.whole)
        fat = String(values.fat.whole)
        diary.updateProfileAndGoals(draftProfile, goals: values)
    }
}

private struct DashboardLayoutEditorView: View {
    @Environment(DiaryStore.self) private var diary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(diary.dashboardLayout) { preference in
                    Toggle(isOn: Binding(
                        get: { preference.isEnabled },
                        set: { diary.setDashboardSection(preference.section, enabled: $0) }
                    )) {
                        Text(preference.section.title)
                            .font(.meBody)
                            .foregroundStyle(Slate.textPrimary)
                    }
                    .tint(Slate.textPrimary)
                    .listRowBackground(Slate.surface)
                }
                .onMove(perform: diary.moveDashboardSections)
            }
            .scrollContentBackground(.hidden)
            .background(Slate.background)
            .navigationTitle("Dashboard Layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Slate.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Slate.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private extension View {
    func settingsInput() -> some View {
        self
            .font(.meNumber)
            .foregroundStyle(Slate.textPrimary)
            .padding(11)
            .background(Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: 11))
    }
}
