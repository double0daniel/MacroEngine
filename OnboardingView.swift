import SwiftUI
import UIKit

struct OnboardingView: View {
    @Environment(DiaryStore.self) private var diary

    @State private var step = 0
    @State private var ageText = "30"
    @State private var heightText = "175"
    @State private var weightText = "80"
    @State private var sex: BiologicalSex = .male
    @State private var activity: ActivityLevel = .moderatelyActive
    @State private var primaryGoal: PrimaryGoal = .cutting
    @State private var approach: GoalApproach = .fatLoss

    @State private var proteinGrams = 160.0
    @State private var carbsGrams = 220.0
    @State private var fatGrams = 70.0
    @State private var hasPreparedReview = false

    private var age: Int? { Int(ageText.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var heightCm: Double? { parseNumber(heightText) }
    private var weightKg: Double? { parseNumber(weightText) }

    private var profileDraft: UserProfile? {
        guard let age, let heightCm, let weightKg,
              (18...100).contains(age), (120...230).contains(heightCm), (35...350).contains(weightKg) else {
            return nil
        }
        return UserProfile(age: age, sex: sex, heightCm: heightCm, weightKg: weightKg,
                           activityLevel: activity, goal: approach)
    }

    private var estimate: TargetEstimate? {
        guard let profileDraft else { return nil }
        return MacroTargetCalculator.estimate(for: profileDraft)
    }

    private var editedCalories: Double {
        max(0, proteinGrams * 4 + carbsGrams * 4 + fatGrams * 9)
    }

    private var canContinue: Bool {
        switch step {
        case 0, 3, 4: true
        case 1: age != nil && (18...100).contains(age ?? 0)
        case 2: heightCm.map { (120...230).contains($0) } == true && weightKg.map { (35...350).contains($0) } == true
        case 5: proteinGrams >= 0 && carbsGrams >= 0 && fatGrams >= 0 && editedCalories > 0
        default: false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: personalDetailsStep
                    case 2: bodyMeasurementsStep
                    case 3: activityStep
                    case 4: goalStep
                    default: reviewStep
                    }
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 24)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .scrollIndicators(.hidden)

            bottomControls
        }
        .slateScreen()
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MacroEngine")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Slate.textPrimary)
                Spacer()
                if step > 0 {
                    Text("\(step) OF 5")
                        .font(.meCaption)
                        .tracking(1.1)
                        .foregroundStyle(Slate.textTertiary)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Slate.track)
                    Capsule().fill(Slate.textPrimary)
                        .frame(width: geometry.size.width * CGFloat(step == 0 ? 0.08 : Double(step) / 5))
                        .animation(.easeInOut(duration: 0.25), value: step)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 14)
            ZStack {
                Circle().stroke(Slate.track, lineWidth: 13)
                Circle().trim(from: 0.047, to: 0.287)
                    .stroke(Accent.protein, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle().trim(from: 0.38, to: 0.62)
                    .stroke(Accent.carbs, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle().trim(from: 0.713, to: 0.953)
                    .stroke(Accent.fat, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "bolt.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(Slate.textPrimary)
            }
            .frame(width: 164, height: 164)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 12) {
                Text("Fuel your goals.")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Slate.textPrimary)
                Text("Build a target that fits your body, activity and training goal. Then track your meals and progress in one place.")
                    .font(.system(size: 17))
                    .foregroundStyle(Slate.textSecondary)
                    .lineSpacing(4)
            }

            VStack(alignment: .leading, spacing: 14) {
                benefitRow(symbol: "target", title: "Personal targets", subtitle: "An estimate you can fine-tune")
                benefitRow(symbol: "fork.knife", title: "Food made simple", subtitle: "Search, scan and save regular meals")
                benefitRow(symbol: "chart.xyaxis.line", title: "Progress over time", subtitle: "Track weight trends, not just one day")
            }
            .card(padding: 18)

            Text("MacroEngine is a tracking tool. Calorie estimates are starting points, not medical advice.")
                .font(.meCaption)
                .foregroundStyle(Slate.textTertiary)
        }
    }

    private var personalDetailsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepHeading(eyebrow: "YOUR STARTING POINT", title: "A little about you", subtitle: "Used only to estimate your daily energy needs.")

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Age")
                HStack {
                    TextField("Age", text: $ageText)
                        .keyboardType(.numberPad)
                        .font(.meDisplay)
                        .foregroundStyle(Slate.textPrimary)
                    Spacer()
                    Text("years")
                        .font(.meBody)
                        .foregroundStyle(Slate.textSecondary)
                }
                .padding(16)
                .background(Slate.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Slate.stroke, lineWidth: 1))
                Text("MacroEngine's default calculator is designed for adults aged 18–100.")
                    .font(.meCaption)
                    .foregroundStyle(Slate.textTertiary)
            }

            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("Sex used by the energy equation")
                ForEach(BiologicalSex.allCases) { option in
                    selectableRow(title: option.title,
                                  subtitle: option == .preferNotToSay ? "Uses a midpoint estimate" : nil,
                                  selected: sex == option) {
                        sex = option
                    }
                }
            }
        }
    }

    private var bodyMeasurementsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepHeading(eyebrow: "METRICS", title: "Your current measurements", subtitle: "Metric units keep the calculation consistent. You can update your weight log any time.")
            measurementField(title: "Height", subtitle: "Centimetres", value: $heightText, unit: "cm", keyboard: .decimalPad)
            measurementField(title: "Weight", subtitle: "Kilograms", value: $weightText, unit: "kg", keyboard: .decimalPad)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Slate.textTertiary)
                Text("For best results, enter a recent weight and your height without shoes. The estimate can differ from your real energy needs.")
                    .font(.meBody)
                    .foregroundStyle(Slate.textSecondary)
            }
            .card(padding: 16)
        }
    }

    private var activityStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeading(eyebrow: "ENERGY OUTPUT", title: "How active are you?", subtitle: "Choose the level that best reflects a typical week, including work and planned exercise.")
            ForEach(ActivityLevel.allCases) { level in
                selectableRow(title: level.title, subtitle: level.detail, selected: activity == level) {
                    activity = level
                }
            }
            if let estimate {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Estimated maintenance")
                            .font(.meBody)
                            .foregroundStyle(Slate.textSecondary)
                        Text("\(estimate.tdee.whole) kcal/day")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(Slate.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundStyle(Accent.calories)
                }
                .card(padding: 18)
            }
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeading(eyebrow: "DIRECTION", title: "What's your goal?", subtitle: "We'll use this to set an initial calorie and macro target. You can customise it on the next screen.")

            ForEach(PrimaryGoal.allCases) { goal in
                selectableRow(title: goal.title, subtitle: goal.detail, selected: primaryGoal == goal) {
                    withAnimation(.snappy(duration: 0.2)) {
                        primaryGoal = goal
                        switch goal {
                        case .cutting: approach = .fatLoss
                        case .bulking: approach = .leanBulk
                        case .maingain: approach = .maingain
                        }
                    }
                }
            }

            if primaryGoal != .maingain {
                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel(primaryGoal == .cutting ? "Choose your cutting approach" : "Choose your bulking approach")
                    ForEach(GoalApproach.allCases.filter { $0.primaryGoal == primaryGoal }) { option in
                        selectableRow(title: option.title, subtitle: option.detail, selected: approach == option) {
                            approach = option
                        }
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let estimate {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Initial target")
                        .font(.meBody)
                        .foregroundStyle(Slate.textSecondary)
                    Text("\(estimate.targetCalories.whole) kcal/day")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Slate.textPrimary)
                    Text("Based on your estimated maintenance of \(estimate.tdee.whole) kcal/day.")
                        .font(.meCaption)
                        .foregroundStyle(Slate.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 18)
            }
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeading(eyebrow: "REVIEW", title: "Make these targets yours", subtitle: "Fine-tune grams for each macro. Your displayed calorie target updates to match the energy represented by those grams.")

            if let estimate {
                HStack(spacing: 0) {
                    metricSummary(title: "BMR", value: estimate.bmr.whole, detail: "kcal/day")
                    Rectangle().fill(Slate.stroke).frame(width: 1, height: 44)
                    metricSummary(title: "Maintenance", value: estimate.tdee.whole, detail: "kcal/day")
                }
                .card(padding: 16)
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Daily target")
                        .font(.meHeadline)
                        .foregroundStyle(Slate.textPrimary)
                    Spacer()
                    Text("\(editedCalories.whole) kcal")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(Slate.textPrimary)
                }
                Divider().overlay(Slate.stroke)
                macroEditor(title: "Protein", symbol: "dumbbell.fill", color: Accent.protein, value: $proteinGrams, range: 0...500, step: 5)
                Divider().overlay(Slate.stroke)
                macroEditor(title: "Carbs", symbol: "bolt.fill", color: Accent.carbs, value: $carbsGrams, range: 0...1000, step: 5)
                Divider().overlay(Slate.stroke)
                macroEditor(title: "Fat", symbol: "drop.fill", color: Accent.fat, value: $fatGrams, range: 0...300, step: 5)
            }
            .card(padding: 18)

            Text("Starting estimates use the Mifflin–St Jeor equation, an activity multiplier and a goal adjustment. Your actual needs can differ; change targets based on your progress and, where appropriate, professional advice.")
                .font(.meCaption)
                .foregroundStyle(Slate.textTertiary)
                .lineSpacing(3)
        }
        .onAppear(perform: prepareReviewIfNeeded)
    }

    private var bottomControls: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.22)) { step -= 1 }
                }
                .font(.meHeadline)
                .foregroundStyle(Slate.textPrimary)
                .padding(.horizontal, 22)
                .padding(.vertical, 15)
                .background(Slate.surfaceRaised, in: Capsule())
            }

            Button {
                advance()
            } label: {
                HStack(spacing: 8) {
                    Text(step == 5 ? "Start tracking" : step == 0 ? "Get started" : "Continue")
                    Image(systemName: step == 5 ? "arrow.right" : "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .buttonStyle(.primary)
            .disabled(!canContinue)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(LinearGradient(colors: [Slate.background.opacity(0), Slate.background], startPoint: .top, endPoint: .bottom))
    }

    private func advance() {
        guard canContinue else { return }
        if step == 4 {
            hasPreparedReview = false
            prepareReviewIfNeeded()
        }
        if step == 5 {
            guard let profile = profileDraft else { return }
            diary.finishOnboarding(
                profile: profile,
                goals: Macros(calories: editedCalories, protein: proteinGrams, carbs: carbsGrams, fat: fatGrams)
            )
        } else {
            withAnimation(.easeInOut(duration: 0.22)) { step += 1 }
        }
    }

    private func prepareReviewIfNeeded() {
        guard !hasPreparedReview, let estimate else { return }
        proteinGrams = estimate.macros.protein
        carbsGrams = estimate.macros.carbs
        fatGrams = estimate.macros.fat
        hasPreparedReview = true
    }

    private func parseNumber(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private func stepHeading(eyebrow: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.meCaption)
                .tracking(1.2)
                .foregroundStyle(Slate.textTertiary)
            Text(title)
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .foregroundStyle(Slate.textPrimary)
            Text(subtitle)
                .font(.meBody)
                .foregroundStyle(Slate.textSecondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.meCaption)
            .tracking(0.7)
            .foregroundStyle(Slate.textTertiary)
    }

    private func selectableRow(title: String, subtitle: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.meHeadline)
                        .foregroundStyle(Slate.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.meBody)
                            .foregroundStyle(Slate.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Slate.textPrimary : Slate.textTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Slate.surfaceRaised : Slate.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Slate.textPrimary.opacity(0.45) : Slate.stroke.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func measurementField(title: String, subtitle: String, value: Binding<String>, unit: String, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.meHeadline).foregroundStyle(Slate.textPrimary)
            HStack(spacing: 10) {
                TextField(title, text: value)
                    .keyboardType(keyboard)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Slate.textPrimary)
                Spacer()
                Text(unit).font(.meBody).foregroundStyle(Slate.textSecondary)
            }
            .padding(16)
            .background(Slate.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Slate.stroke, lineWidth: 1))
            Text(subtitle).font(.meCaption).foregroundStyle(Slate.textTertiary)
        }
    }

    private func benefitRow(symbol: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Slate.textPrimary)
                .frame(width: 40, height: 40)
                .background(Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.meHeadline).foregroundStyle(Slate.textPrimary)
                Text(subtitle).font(.meBody).foregroundStyle(Slate.textSecondary)
            }
            Spacer()
        }
    }

    private func metricSummary(title: String, value: Int, detail: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.meCaption).foregroundStyle(Slate.textTertiary)
            Text("\(value)").font(.meNumber).foregroundStyle(Slate.textPrimary)
            Text(detail).font(.meCaption).foregroundStyle(Slate.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func macroEditor(title: String, symbol: String, color: Color, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
            Text(title)
                .font(.meHeadline)
                .foregroundStyle(Slate.textPrimary)
            Spacer()
            Button {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Slate.surfaceRaised, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Slate.textPrimary)
            .accessibilityLabel("Decrease \(title)")

            Text("\(value.wrappedValue.whole) g")
                .font(.meNumber)
                .foregroundStyle(Slate.textPrimary)
                .frame(minWidth: 56, alignment: .trailing)

            Button {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Slate.surfaceRaised, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Slate.textPrimary)
            .accessibilityLabel("Increase \(title)")
        }
    }
}

#if DEBUG
#Preview {
    OnboardingView().environment(DiaryStore(persist: false))
}
#endif
