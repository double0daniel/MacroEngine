import SwiftUI
import Observation
import Foundation

// MARK: - Macros

struct Macros: Equatable, Hashable, Codable, Sendable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    static let zero = Macros()

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(
            calories: lhs.calories + rhs.calories,
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat
        )
    }

    func scaled(by factor: Double) -> Macros {
        let safeFactor = factor.isFinite ? max(0, factor) : 0
        return Macros(
            calories: calories * safeFactor,
            protein: protein * safeFactor,
            carbs: carbs * safeFactor,
            fat: fat * safeFactor
        )
    }

    subscript(kind: MacroKind) -> Double {
        switch kind {
        case .calories: calories
        case .protein: protein
        case .carbs: carbs
        case .fat: fat
        }
    }

    /// Energy estimated from macro grams (4 kcal/g protein and carbohydrate, 9 kcal/g fat).
    var energyFromMacros: Double { protein * 4 + carbs * 4 + fat * 9 }
}

enum MacroKind: String, CaseIterable, Identifiable, Sendable {
    case calories, protein, carbs, fat

    static let macros: [MacroKind] = [.protein, .carbs, .fat]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calories: "Calories"
        case .protein: "Protein"
        case .carbs: "Carbs"
        case .fat: "Fat"
        }
    }

    var symbol: String {
        switch self {
        case .calories: "flame.fill"
        case .protein: "dumbbell.fill"
        case .carbs: "bolt.fill"
        case .fat: "drop.fill"
        }
    }

    var color: Color {
        switch self {
        case .calories: Accent.calories
        case .protein: Accent.protein
        case .carbs: Accent.carbs
        case .fat: Accent.fat
        }
    }
}

extension Double {
    /// Rounded for display; safely handles non-finite and out-of-range values.
    var whole: Int {
        guard isFinite, self < Double(Int.max), self > Double(Int.min) else { return 0 }
        return Int(rounded())
    }
}

// MARK: - Food + diary

struct FoodItem: Identifiable, Hashable, Codable, Sendable {
    let id: String            // barcode or Open Food Facts product code
    let name: String
    let brand: String?
    let per100g: Macros
    let servingGrams: Double?
    let imageURL: URL?
}

enum MealCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snacks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snacks: "Snacks"
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snacks: "carrot.fill"
        }
    }
}

struct DiaryEntry: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    let food: FoodItem
    var grams: Double
    var date: Date
    var category: MealCategory

    init(
        id: UUID = UUID(),
        food: FoodItem,
        grams: Double,
        date: Date = .now,
        category: MealCategory = .snacks
    ) {
        self.id = id
        self.food = food
        self.grams = max(0, grams.isFinite ? grams : 0)
        self.date = date
        self.category = category
    }

    var macros: Macros { food.per100g.scaled(by: grams / 100) }

    // Backwards compatibility for entries persisted before meal categories were introduced.
    private enum CodingKeys: String, CodingKey { case id, food, grams, date, category }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        food = try container.decode(FoodItem.self, forKey: .food)
        let decodedGrams = try container.decodeIfPresent(Double.self, forKey: .grams) ?? 0
        grams = max(0, decodedGrams.isFinite ? decodedGrams : 0)
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? .now
        category = try container.decodeIfPresent(MealCategory.self, forKey: .category) ?? .snacks
    }
}

// MARK: - Onboarding profile + target calculation

enum BiologicalSex: String, CaseIterable, Identifiable, Codable, Sendable {
    case female, male, preferNotToSay

    var id: String { rawValue }
    var title: String {
        switch self {
        case .female: "Female"
        case .male: "Male"
        case .preferNotToSay: "Prefer not to say"
        }
    }

    /// Mifflin–St Jeor coefficient. The undisclosed option uses the midpoint as an estimate.
    var equationConstant: Double {
        switch self {
        case .female: -161
        case .male: 5
        case .preferNotToSay: -78
        }
    }
}

enum ActivityLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case sedentary, lightlyActive, moderatelyActive, veryActive, extraActive

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sedentary: "Sedentary"
        case .lightlyActive: "Lightly active"
        case .moderatelyActive: "Moderately active"
        case .veryActive: "Very active"
        case .extraActive: "Extra active"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: "Mostly seated; little planned exercise"
        case .lightlyActive: "Light exercise or sport 1–3 days a week"
        case .moderatelyActive: "Moderate exercise 3–5 days a week"
        case .veryActive: "Hard exercise 6–7 days a week"
        case .extraActive: "Very demanding training or a physical job"
        }
    }

    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .lightlyActive: 1.375
        case .moderatelyActive: 1.55
        case .veryActive: 1.725
        case .extraActive: 1.9
        }
    }
}

enum PrimaryGoal: String, CaseIterable, Identifiable, Codable, Sendable {
    case cutting, bulking, maingain
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cutting: "Cutting"
        case .bulking: "Bulking"
        case .maingain: "Maingain"
        }
    }

    var detail: String {
        switch self {
        case .cutting: "Reduce body weight"
        case .bulking: "Build muscle and body mass"
        case .maingain: "Recompose around maintenance"
        }
    }
}

enum GoalApproach: String, CaseIterable, Identifiable, Codable, Sendable {
    case fatLoss, overallWeightLoss, leanBulk, dirtyBulk, maingain
    var id: String { rawValue }

    var primaryGoal: PrimaryGoal {
        switch self {
        case .fatLoss, .overallWeightLoss: .cutting
        case .leanBulk, .dirtyBulk: .bulking
        case .maingain: .maingain
        }
    }

    var title: String {
        switch self {
        case .fatLoss: "Fat loss"
        case .overallWeightLoss: "Overall weight loss"
        case .leanBulk: "Lean bulk"
        case .dirtyBulk: "Dirty bulk"
        case .maingain: "Maingain"
        }
    }

    var detail: String {
        switch self {
        case .fatLoss: "A moderate deficit focused on reducing body fat"
        case .overallWeightLoss: "A larger deficit focused on total body weight"
        case .leanBulk: "A small surplus to support gradual muscle gain"
        case .dirtyBulk: "A larger surplus; weight gain may include more fat"
        case .maingain: "Aim around estimated maintenance calories"
        }
    }

    var calorieAdjustment: Double {
        switch self {
        case .fatLoss: 0.85
        case .overallWeightLoss: 0.80
        case .leanBulk: 1.08
        case .dirtyBulk: 1.15
        case .maingain: 1.0
        }
    }

    var proteinGramsPerKg: Double {
        switch self {
        case .fatLoss: 2.0
        case .overallWeightLoss: 1.8
        case .leanBulk: 1.8
        case .dirtyBulk: 1.6
        case .maingain: 1.8
        }
    }
}

struct UserProfile: Codable, Equatable, Sendable {
    var age: Int
    var sex: BiologicalSex
    var heightCm: Double
    var weightKg: Double
    var activityLevel: ActivityLevel
    var goal: GoalApproach
    var createdAt: Date = .now
}

struct TargetEstimate: Equatable, Sendable {
    let bmr: Double
    let tdee: Double
    let targetCalories: Double
    let macros: Macros
}

enum MacroTargetCalculator {
    /// Mifflin–St Jeor BMR followed by a conventional activity multiplier.
    /// These are estimates, not medical advice; real energy needs vary between people.
    static func estimate(for profile: UserProfile) -> TargetEstimate {
        let weight = max(0, profile.weightKg)
        let height = max(0, profile.heightCm)
        let age = Double(max(0, profile.age))
        let bmr = 10 * weight + 6.25 * height - 5 * age + profile.sex.equationConstant
        let tdee = max(0, bmr * profile.activityLevel.multiplier)
        let target = max(0, (tdee * profile.goal.calorieAdjustment / 25).rounded() * 25)

        // Keep protein within 40% of target energy for extreme inputs so it cannot
        // crowd out all other macros; the chosen gram target remains editable.
        let proteinByWeight = weight * profile.goal.proteinGramsPerKg
        let proteinEnergyCap = target * 0.40 / 4
        let protein = min(proteinByWeight, proteinEnergyCap).rounded()
        let fat = (target * 0.25 / 9).rounded()
        let carbs = max(0, ((target - protein * 4 - fat * 9) / 4).rounded())
        let macros = Macros(calories: target, protein: protein, carbs: carbs, fat: fat)
        return TargetEstimate(bmr: bmr, tdee: tdee, targetCalories: target, macros: macros)
    }
}

// MARK: - Favourites, custom meals, and weight history

struct MealIngredient: Codable, Hashable, Identifiable, Sendable {
    var id: String { food.id }
    var food: FoodItem
    var grams: Double

    var macros: Macros { food.per100g.scaled(by: grams / 100) }
}

struct CustomMeal: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var ingredients: [MealIngredient]
    var createdAt: Date = .now

    var totals: Macros {
        ingredients.reduce(.zero) { $0 + $1.macros }
    }
}

struct WeightEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var date: Date = .now
    var weightKg: Double
}

struct WorkoutEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var date: Date = .now
    var type: String
    var durationMinutes: Int
    var notes: String
    var caloriesBurned: Int
}

struct HydrationEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var date: Date = .now
    var amountMl: Int = 0
}

struct SupplementDay: Codable, Hashable, Sendable {
    var date: Date = .now
    var completedIDs: [String] = []
}

struct SupplementItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let symbol: String

    static let defaults: [SupplementItem] = [
        .init(id: "creatine", name: "Creatine", symbol: "bolt.fill"),
        .init(id: "electrolytes", name: "Electrolytes", symbol: "drop.fill"),
        .init(id: "fish-oil", name: "Fish Oil", symbol: "fish.fill"),
        .init(id: "multivitamin", name: "Multivitamin", symbol: "pills.fill"),
        .init(id: "vitamin-d", name: "Vitamin D", symbol: "sun.max.fill")
    ]
}

// MARK: - App store

@MainActor
@Observable
final class DiaryStore {
    var entries: [DiaryEntry] = []
    var goals = Macros(calories: 2400, protein: 160, carbs: 260, fat: 75)
    var profile: UserProfile?
    var hasCompletedOnboarding = false
    var favoriteFoods: [FoodItem] = []
    var customMeals: [CustomMeal] = []
    var weightEntries: [WeightEntry] = []
    var workouts: [WorkoutEntry] = []
    var hydrationEntries: [HydrationEntry] = []
    var waterGoalMl = 2000
    var supplementDays: [SupplementDay] = []

    private let persist: Bool
    private enum Key {
        static let entries = "macroengine.entries.v1"
        static let goals = "macroengine.goals.v1"
        static let profile = "macroengine.profile.v1"
        static let onboarding = "macroengine.onboarding.completed.v1"
        static let favorites = "macroengine.favorites.v1"
        static let customMeals = "macroengine.customMeals.v1"
        static let weightEntries = "macroengine.weightEntries.v1"
        static let workouts = "macroengine.workouts.v1"
        static let hydrationEntries = "macroengine.hydration.v1"
        static let waterGoal = "macroengine.waterGoal.v1"
        static let supplementDays = "macroengine.supplements.v1"
    }

    init(persist: Bool = true) {
        self.persist = persist
        guard persist else { return }
        load()
    }

    var todaysEntries: [DiaryEntry] {
        entries
            .filter { Calendar.current.isDateInToday($0.date) }
            .sorted { $0.date > $1.date }
    }

    var totals: Macros {
        todaysEntries.reduce(.zero) { $0 + $1.macros }
    }

    var todaysWorkouts: [WorkoutEntry] {
        workouts.filter { Calendar.current.isDateInToday($0.date) }.sorted { $0.date > $1.date }
    }

    var caloriesBurnedToday: Int { todaysWorkouts.reduce(0) { $0 + max(0, $1.caloriesBurned) } }

    var netCaloriesToday: Double { totals.calories - Double(caloriesBurnedToday) }

    var waterConsumedTodayMl: Int {
        hydrationEntries.first(where: { Calendar.current.isDateInToday($0.date) })?.amountMl ?? 0
    }

    var todaysSupplementIDs: Set<String> {
        Set(supplementDays.first(where: { Calendar.current.isDateInToday($0.date) })?.completedIDs ?? [])
    }

    func entries(for category: MealCategory) -> [DiaryEntry] {
        todaysEntries.filter { $0.category == category }
    }

    func totals(for category: MealCategory) -> Macros {
        entries(for: category).reduce(.zero) { $0 + $1.macros }
    }

    func add(_ food: FoodItem, grams: Double, category: MealCategory = .snacks, date: Date = .now) {
        guard grams.isFinite, grams > 0 else { return }
        entries.append(DiaryEntry(food: food, grams: grams, date: date, category: category))
        save(entries, key: Key.entries)
    }

    func log(_ meal: CustomMeal, category: MealCategory, date: Date = .now) {
        for ingredient in meal.ingredients {
            add(ingredient.food, grams: ingredient.grams, category: category, date: date)
        }
    }

    func remove(_ entry: DiaryEntry) {
        entries.removeAll { $0.id == entry.id }
        save(entries, key: Key.entries)
    }

    func addWorkout(type: String, durationMinutes: Int, notes: String, caloriesBurned: Int, date: Date = .now) {
        let cleanType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanType.isEmpty, durationMinutes > 0, caloriesBurned >= 0 else { return }
        workouts.append(WorkoutEntry(date: date, type: cleanType, durationMinutes: durationMinutes,
                                     notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                                     caloriesBurned: caloriesBurned))
        save(workouts, key: Key.workouts)
    }

    func removeWorkout(_ workout: WorkoutEntry) {
        workouts.removeAll { $0.id == workout.id }
        save(workouts, key: Key.workouts)
    }

    func addWater(_ amountMl: Int, date: Date = .now) {
        guard amountMl > 0 else { return }
        if let index = hydrationEntries.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            hydrationEntries[index].amountMl += amountMl
        } else {
            hydrationEntries.append(HydrationEntry(date: date, amountMl: amountMl))
        }
        save(hydrationEntries, key: Key.hydrationEntries)
    }

    func setWaterGoal(_ amountMl: Int) {
        waterGoalMl = min(10_000, max(250, amountMl))
        if persist { UserDefaults.standard.set(waterGoalMl, forKey: Key.waterGoal) }
    }

    func toggleSupplement(_ id: String, date: Date = .now) {
        let calendar = Calendar.current
        if let index = supplementDays.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            if supplementDays[index].completedIDs.contains(id) {
                supplementDays[index].completedIDs.removeAll { $0 == id }
            } else {
                supplementDays[index].completedIDs.append(id)
            }
        } else {
            supplementDays.append(SupplementDay(date: date, completedIDs: [id]))
        }
        save(supplementDays, key: Key.supplementDays)
    }

    func finishOnboarding(profile: UserProfile, goals: Macros) {
        self.profile = profile
        self.goals = Macros(
            calories: max(0, goals.calories),
            protein: max(0, goals.protein),
            carbs: max(0, goals.carbs),
            fat: max(0, goals.fat)
        )
        hasCompletedOnboarding = true
        save(profile, key: Key.profile)
        save(self.goals, key: Key.goals)
        if persist { UserDefaults.standard.set(true, forKey: Key.onboarding) }
        if weightEntries.isEmpty {
            recordWeight(profile.weightKg)
        }
    }

    func updateGoals(_ newGoals: Macros) {
        goals = Macros(
            calories: max(0, newGoals.calories),
            protein: max(0, newGoals.protein),
            carbs: max(0, newGoals.carbs),
            fat: max(0, newGoals.fat)
        )
        save(goals, key: Key.goals)
    }

    func updateProfileAndGoals(_ newProfile: UserProfile, goals newGoals: Macros) {
        let weightChanged = profile?.weightKg != newProfile.weightKg
        profile = newProfile
        save(newProfile, key: Key.profile)
        updateGoals(newGoals)
        if weightChanged { recordWeight(newProfile.weightKg) }
        if persist { UserDefaults.standard.set(true, forKey: Key.onboarding) }
    }

    func isFavorite(_ food: FoodItem) -> Bool {
        favoriteFoods.contains { $0.id == food.id }
    }

    func toggleFavorite(_ food: FoodItem) {
        if isFavorite(food) {
            favoriteFoods.removeAll { $0.id == food.id }
        } else {
            favoriteFoods.insert(food, at: 0)
        }
        save(favoriteFoods, key: Key.favorites)
    }

    func saveCustomMeal(_ meal: CustomMeal) {
        guard !meal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !meal.ingredients.isEmpty else { return }
        if let index = customMeals.firstIndex(where: { $0.id == meal.id }) {
            customMeals[index] = meal
        } else {
            customMeals.insert(meal, at: 0)
        }
        save(customMeals, key: Key.customMeals)
    }

    func removeCustomMeal(_ meal: CustomMeal) {
        customMeals.removeAll { $0.id == meal.id }
        save(customMeals, key: Key.customMeals)
    }

    func recordWeight(_ weightKg: Double, date: Date = .now) {
        guard weightKg.isFinite, (20...500).contains(weightKg) else { return }
        let calendar = Calendar.current
        if let index = weightEntries.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            weightEntries[index].weightKg = weightKg
            weightEntries[index].date = date
        } else {
            weightEntries.append(WeightEntry(date: date, weightKg: weightKg))
        }
        weightEntries.sort { $0.date < $1.date }
        save(weightEntries, key: Key.weightEntries)
    }

    // MARK: Persistence

    private func save<T: Encodable>(_ value: T, key: String) {
        guard persist, let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func load() {
        entries = decode([DiaryEntry].self, key: Key.entries) ?? []
        goals = decode(Macros.self, key: Key.goals) ?? goals
        profile = decode(UserProfile.self, key: Key.profile)
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Key.onboarding)
        favoriteFoods = decode([FoodItem].self, key: Key.favorites) ?? []
        customMeals = decode([CustomMeal].self, key: Key.customMeals) ?? []
        weightEntries = decode([WeightEntry].self, key: Key.weightEntries) ?? []
        workouts = decode([WorkoutEntry].self, key: Key.workouts) ?? []
        hydrationEntries = decode([HydrationEntry].self, key: Key.hydrationEntries) ?? []
        waterGoalMl = UserDefaults.standard.object(forKey: Key.waterGoal) as? Int ?? waterGoalMl
        supplementDays = decode([SupplementDay].self, key: Key.supplementDays) ?? []
    }
}

#if DEBUG
extension DiaryStore {
    static var preview: DiaryStore {
        let store = DiaryStore(persist: false)
        store.add(FoodItem(id: "1", name: "Greek yoghurt, 0% fat", brand: "Fage",
                           per100g: Macros(calories: 54, protein: 10, carbs: 3.5, fat: 0.2),
                           servingGrams: 170, imageURL: nil), grams: 170, category: .breakfast)
        store.add(FoodItem(id: "2", name: "Rolled oats", brand: "Quaker",
                           per100g: Macros(calories: 372, protein: 13, carbs: 60, fat: 7),
                           servingGrams: 40, imageURL: nil), grams: 80, category: .breakfast)
        store.add(FoodItem(id: "3", name: "Chicken breast, grilled", brand: nil,
                           per100g: Macros(calories: 165, protein: 31, carbs: 0, fat: 3.6),
                           servingGrams: nil, imageURL: nil), grams: 200, category: .lunch)
        store.recordWeight(82.4, date: Calendar.current.date(byAdding: .day, value: -20, to: .now) ?? .now)
        store.recordWeight(81.9, date: Calendar.current.date(byAdding: .day, value: -12, to: .now) ?? .now)
        store.recordWeight(81.7)
        return store
    }
}
#endif
