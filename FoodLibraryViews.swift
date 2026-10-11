import SwiftUI

// MARK: - Favourites

struct FavoritesSectionView: View {
    @Environment(DiaryStore.self) private var diary
    let category: MealCategory
    let onSelectFood: (FoodItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if diary.favoriteFoods.isEmpty {
                    EmptyStateView(
                        symbol: "star",
                        title: "No favourites yet",
                        message: "Open a food's details and tap Save to favourites. Your regular foods will appear here."
                    )
                    .card(padding: 8)
                } else {
                    Text("Tap a food to adjust its portion, use + to log its usual serving, or tap the star to remove it.")
                        .font(.meBody)
                        .foregroundStyle(Slate.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 2)

                    ForEach(diary.favoriteFoods) { food in
                        HStack(spacing: 5) {
                            Button { onSelectFood(food) } label: {
                                FoodResultRow(food: food)
                            }
                            .buttonStyle(.plain)

                            VStack(spacing: 6) {
                                Button {
                                    diary.add(food, grams: food.servingGrams ?? 100, category: category)
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Slate.textPrimary)
                                        .frame(width: 36, height: 36)
                                        .background(Slate.surfaceRaised, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Quick add \(food.name) to \(category.title)")

                                Button {
                                    diary.toggleFavorite(food)
                                } label: {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Slate.textPrimary)
                                        .frame(width: 36, height: 36)
                                        .background(Slate.surfaceRaised, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(food.name) from favourites")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Saved custom meals

struct CustomMealsSectionView: View {
    @Environment(DiaryStore.self) private var diary
    @State private var showingCreateMeal = false
    @State private var category: MealCategory

    init(initialCategory: MealCategory = .snacks) {
        _category = State(initialValue: initialCategory)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button { showingCreateMeal = true } label: {
                    Label("Create custom meal", systemImage: "plus")
                }
                .buttonStyle(.primary)

                if !diary.customMeals.isEmpty {
                    HStack {
                        Text("ADD MEALS TO")
                            .font(.meCaption)
                            .tracking(0.8)
                            .foregroundStyle(Slate.textTertiary)
                        Spacer()
                        Picker("Meal category", selection: $category) {
                            ForEach(MealCategory.allCases) { mealCategory in
                                Text(mealCategory.title).tag(mealCategory)
                            }
                        }
                        .tint(Slate.textPrimary)
                    }
                    .padding(.top, 4)
                }

                if diary.customMeals.isEmpty {
                    EmptyStateView(
                        symbol: "takeoutbag.and.cup.and.straw",
                        title: "Save a go-to meal",
                        message: diary.favoriteFoods.isEmpty
                            ? "Save a few foods as favourites first, then combine their portions into a custom meal."
                            : "Combine your favourite foods into a meal you can log with one tap.",
                        actionTitle: "Create custom meal"
                    ) { showingCreateMeal = true }
                    .card(padding: 8)
                } else {
                    ForEach(diary.customMeals) { meal in
                        customMealRow(meal)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showingCreateMeal) {
            NavigationStack {
                CreateCustomMealView()
            }
        }
    }

    private func customMealRow(_ meal: CustomMeal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Slate.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.name)
                        .font(.meHeadline)
                        .foregroundStyle(Slate.textPrimary)
                    Text(meal.ingredients.map { "\($0.food.name) · \($0.grams.whole) g" }.joined(separator: ", "))
                        .font(.meCaption)
                        .foregroundStyle(Slate.textSecondary)
                        .lineLimit(3)
                    Text("\(meal.totals.calories.whole) kcal")
                        .font(.meNumber)
                        .foregroundStyle(Slate.textPrimary)
                    MacroChips(macros: meal.totals)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button {
                    diary.log(meal, category: category)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Label("Add to \(category.title)", systemImage: "plus.circle.fill")
                        .font(.meBody.weight(.semibold))
                        .foregroundStyle(Slate.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Slate.textPrimary, in: Capsule())
                }
                .buttonStyle(.plain)

                Menu {
                    Button(role: .destructive) { diary.removeCustomMeal(meal) } label: {
                        Label("Delete custom meal", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Slate.textPrimary)
                        .frame(width: 42, height: 42)
                        .background(Slate.surfaceRaised, in: Circle())
                }
                .accessibilityLabel("More options for \(meal.name)")
            }
        }
        .card(padding: 16)
    }
}

// MARK: - Build a custom meal from favourites

struct CreateCustomMealView: View {
    @Environment(DiaryStore.self) private var diary
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedFoodIDs: Set<String> = []
    @State private var gramsByFoodID: [String: Double] = [:]
    @State private var showingValidation = false

    private var selectedFoods: [FoodItem] {
        diary.favoriteFoods.filter { selectedFoodIDs.contains($0.id) }
    }

    private var previewTotals: Macros {
        selectedFoods.reduce(.zero) { partial, food in
            let grams = gramsByFoodID[food.id] ?? food.servingGrams ?? 100
            return partial + food.per100g.scaled(by: grams / 100)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Meal name")
                        .font(.meHeadline)
                        .foregroundStyle(Slate.textPrimary)
                    TextField("e.g. Chicken rice bowl", text: $name)
                        .textInputAutocapitalization(.words)
                        .foregroundStyle(Slate.textPrimary)
                        .padding(14)
                        .background(Slate.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Slate.stroke, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Ingredients")
                        .font(.meHeadline)
                        .foregroundStyle(Slate.textPrimary)
                    if diary.favoriteFoods.isEmpty {
                        EmptyStateView(
                            symbol: "star",
                            title: "Save foods first",
                            message: "Return to food search, open a food and tap Save to favourites. Then you can compose a meal from those foods."
                        )
                        .card(padding: 8)
                    } else {
                        ForEach(diary.favoriteFoods) { food in
                            ingredientRow(food)
                        }
                    }
                }

                if !selectedFoods.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ESTIMATED MEAL TOTAL")
                            .font(.meCaption)
                            .tracking(0.7)
                            .foregroundStyle(Slate.textTertiary)
                        Text("\(previewTotals.calories.whole) kcal")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Slate.textPrimary)
                        MacroChips(macros: previewTotals)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 16)
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .slateScreen()
        .navigationTitle("New custom meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Slate.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Slate.textPrimary)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveMeal() }
                    .foregroundStyle(Slate.textPrimary)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedFoods.isEmpty)
            }
        }
        .alert("Couldn't save meal", isPresented: $showingValidation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Add a name and select at least one ingredient.")
        }
    }

    private func ingredientRow(_ food: FoodItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: selectionBinding(for: food)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name)
                        .font(.meBody.weight(.semibold))
                        .foregroundStyle(Slate.textPrimary)
                    Text("\(food.per100g.calories.whole) kcal / 100 g")
                        .font(.meCaption)
                        .foregroundStyle(Slate.textSecondary)
                }
            }
            .tint(Slate.textPrimary)

            if selectedFoodIDs.contains(food.id) {
                HStack {
                    Text("Portion")
                        .font(.meBody)
                        .foregroundStyle(Slate.textSecondary)
                    Spacer()
                    Stepper(value: gramsBinding(for: food), in: 1...1000, step: 10) {
                        Text("\((gramsByFoodID[food.id] ?? food.servingGrams ?? 100).whole) g")
                            .font(.meNumber)
                            .foregroundStyle(Slate.textPrimary)
                    }
                    .fixedSize()
                }
                .padding(.leading, 4)
            }
        }
        .padding(14)
        .background(Slate.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Slate.stroke.opacity(0.7), lineWidth: 1))
    }

    private func selectionBinding(for food: FoodItem) -> Binding<Bool> {
        Binding(
            get: { selectedFoodIDs.contains(food.id) },
            set: { selected in
                if selected {
                    selectedFoodIDs.insert(food.id)
                    gramsByFoodID[food.id] = gramsByFoodID[food.id] ?? food.servingGrams ?? 100
                } else {
                    selectedFoodIDs.remove(food.id)
                }
            }
        )
    }

    private func gramsBinding(for food: FoodItem) -> Binding<Double> {
        Binding(
            get: { gramsByFoodID[food.id] ?? food.servingGrams ?? 100 },
            set: { gramsByFoodID[food.id] = min(1000, max(1, $0)) }
        )
    }

    private func saveMeal() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !selectedFoods.isEmpty else {
            showingValidation = true
            return
        }
        let ingredients = selectedFoods.map { food in
            MealIngredient(food: food, grams: gramsByFoodID[food.id] ?? food.servingGrams ?? 100)
        }
        diary.saveCustomMeal(CustomMeal(name: cleanName, ingredients: ingredients))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
