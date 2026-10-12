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
    @State private var activeSheet: CustomMealSheet?
    @State private var category: MealCategory

    private enum CustomMealSheet: Identifiable {
        case create
        case importRecipe
        case logMeal(CustomMeal)

        var id: String {
            switch self {
            case .create: "create"
            case .importRecipe: "import-recipe"
            case .logMeal(let meal): "log-\(meal.id.uuidString)"
            }
        }
    }

    init(initialCategory: MealCategory = .snacks) {
        _category = State(initialValue: initialCategory)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button { activeSheet = .create } label: {
                    Text("Create Meal")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.primary)

                Button { activeSheet = .importRecipe } label: {
                    Label("Import Recipe from Link", systemImage: "link")
                        .font(.meBody.weight(.semibold))
                        .foregroundStyle(Slate.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Slate.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Slate.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)

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
                        message: "Search for foods or scan their barcodes, then combine portions into a meal you can log with one tap.",
                        actionTitle: "Create Meal"
                    ) { activeSheet = .create }
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
        .sheet(item: $activeSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .create:
                    CreateCustomMealView()
                case .importRecipe:
                    RecipeImportPreviewView()
                case .logMeal(let meal):
                    MealPrepPortionView(meal: meal, category: category)
                }
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
                    if meal.sourceURL != nil {
                        Text("Imported recipe · \(meal.sourceServings) servings per batch")
                            .font(.meCaption)
                            .foregroundStyle(Slate.textSecondary)
                            .lineLimit(2)
                    } else if meal.isMealPrep {
                        Text("Meal prep · \(meal.numberOfServings) servings per batch")
                            .font(.meCaption)
                            .foregroundStyle(Slate.textSecondary)
                    } else {
                        Text(meal.ingredients.map { "\($0.food.name) · \($0.grams.whole) g" }.joined(separator: ", "))
                            .font(.meCaption)
                            .foregroundStyle(Slate.textSecondary)
                            .lineLimit(3)
                    }
                    Text("\(meal.totals.calories.whole) kcal")
                        .font(.meNumber)
                        .foregroundStyle(Slate.textPrimary)
                    if meal.isMealPrep {
                        Text("Per serving · \(meal.perServingTotals.calories.whole) kcal")
                            .font(.meCaption)
                            .foregroundStyle(Slate.textSecondary)
                        MacroChips(macros: meal.perServingTotals)
                    } else {
                        MacroChips(macros: meal.totals)
                    }
                    if let rating = diary.satietySummary(for: meal) {
                        Label("Satiety & Energy Summary", systemImage: "heart.text.square.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Slate.textPrimary)
                        Text(String(format: "Satiety %.1f/5 · Energy %.1f/5 · %d log(s)",
                                    rating.averageSatiety, rating.averageEnergy, rating.mealCount))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Slate.textSecondary)
                    } else {
                        Label("Satiety & Energy: no ratings yet", systemImage: "heart")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Slate.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button {
                    if meal.isMealPrep {
                        activeSheet = .logMeal(meal)
                    } else {
                        diary.log(meal, category: category)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
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

private struct MealPrepPortionView: View {
    @Environment(DiaryStore.self) private var diary
    @Environment(\.dismiss) private var dismiss

    let meal: CustomMeal
    let category: MealCategory
    @State private var portions = 1.0
    @State private var customWeightText: String
    @State private var mode: PortionMode = .servings
    @FocusState private var weightFocused: Bool

    private enum PortionMode: String, CaseIterable, Identifiable {
        case servings = "Servings"
        case grams = "Custom grams"
        var id: String { rawValue }
    }

    init(meal: CustomMeal, category: MealCategory) {
        self.meal = meal
        self.category = category
        let defaultWeight = meal.totalBatchWeightGrams / Double(max(1, meal.numberOfServings))
        _customWeightText = State(initialValue: String(format: "%.0f", defaultWeight))
    }

    private var customWeight: Double? {
        guard let value = Double(customWeightText.replacingOccurrences(of: ",", with: ".")),
              value.isFinite, value > 0,
              meal.totalBatchWeightGrams > 0 else { return nil }
        return min(value, meal.totalBatchWeightGrams)
    }

    /// Portion count is expressed in servings so DiaryStore can apply one consistent scale.
    private var selectedPortions: Double? {
        switch mode {
        case .servings:
            return portions
        case .grams:
            guard let customWeight else { return nil }
            return customWeight / meal.totalBatchWeightGrams * Double(max(1, meal.numberOfServings))
        }
    }

    private var selectedMacros: Macros {
        guard let selectedPortions else { return .zero }
        return meal.totals.scaled(by: selectedPortions / Double(max(1, meal.numberOfServings)))
    }

    private var portionDescription: String {
        switch mode {
        case .servings:
            return "\(portions.formatted(.number.precision(.fractionLength(0...1)))) serving\(portions == 1 ? "" : "s")"
        case .grams:
            return "\(customWeight?.whole ?? 0) g"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(meal.name)
                .font(.meHeadline)
                .foregroundStyle(Slate.textPrimary)

            Picker("Portion amount", selection: $mode) {
                ForEach(PortionMode.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if mode == .servings {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose servings from this batch of \(meal.numberOfServings)")
                        .font(.meBody)
                        .foregroundStyle(Slate.textSecondary)
                    Stepper(value: $portions, in: 0.5...Double(max(1, meal.numberOfServings)), step: 0.5) {
                        Text(portionDescription)
                            .font(.meNumber)
                            .foregroundStyle(Slate.textPrimary)
                            .monospacedDigit()
                    }
                    .tint(Slate.textPrimary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Batch weight: \(meal.totalBatchWeightGrams.whole) g")
                        .font(.meBody)
                        .foregroundStyle(Slate.textSecondary)
                    HStack {
                        Text("Portion weight")
                            .font(.meBody)
                            .foregroundStyle(Slate.textPrimary)
                        Spacer()
                        TextField("100", text: $customWeightText)
                            .keyboardType(.decimalPad)
                            .focused($weightFocused)
                            .multilineTextAlignment(.trailing)
                            .font(.meNumber)
                            .foregroundStyle(Slate.textPrimary)
                            .frame(width: 90)
                        Text("g")
                            .font(.meBody)
                            .foregroundStyle(Slate.textSecondary)
                    }
                    .padding(12)
                    .background(Slate.surface, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("\(portionDescription) · \(selectedMacros.calories.whole) kcal")
                    .font(.meHeadline)
                    .foregroundStyle(Slate.textPrimary)
                MacroChips(macros: selectedMacros)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16)

            Button(action: logPortion) {
                Label("Log \(portionDescription)", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .disabled(selectedPortions == nil)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .slateScreen()
        .navigationTitle("Log meal prep")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Slate.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Slate.textPrimary)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFocused = false }
                    .foregroundStyle(Slate.textPrimary)
            }
        }
    }

    private func logPortion() {
        guard let selectedPortions else { return }
        diary.log(meal, category: category, portions: selectedPortions)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Build a custom meal from search or barcode scan

struct CreateCustomMealView: View {
    @Environment(DiaryStore.self) private var diary
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var searchModel = FoodSearchViewModel()
    @State private var draftIngredients: [MealIngredient] = []
    @State private var isMealPrep = false
    @State private var numberOfServings = 1
    @State private var showingScanner = false
    @State private var showingValidation = false
    @FocusState private var searchFocused: Bool
    @FocusState private var portionFocused: Bool

    private var barcodeErrorBinding: Binding<Bool> {
        Binding(
            get: { searchModel.barcodeError != nil },
            set: { if !$0 { searchModel.barcodeError = nil } }
        )
    }

    private var previewTotals: Macros {
        draftIngredients.reduce(.zero) { $0 + $1.macros }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Meal name")
                        .font(.meHeadline)
                        .foregroundStyle(Slate.textPrimary)
                    TextField("e.g. Post-Workout Smoothie", text: $name)
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

                    HStack(spacing: 10) {
                        HStack(spacing: 9) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Slate.textTertiary)
                            TextField("Search foods or brands", text: $searchModel.query)
                                .focused($searchFocused)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .foregroundStyle(Slate.textPrimary)
                        }
                        .padding(.horizontal, 13)
                        .frame(minHeight: 48)
                        .background(Slate.background, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Slate.stroke, lineWidth: 1))

                        Button { showingScanner = true } label: {
                            Image(systemName: "barcode.viewfinder")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Slate.textPrimary)
                                .frame(width: 48, height: 48)
                                .background(Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: 13))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Scan food barcode")
                    }

                    searchResults

                    if draftIngredients.isEmpty {
                        Text("Search for an ingredient or scan a product barcode to add it to this meal.")
                            .font(.meCaption)
                            .foregroundStyle(Slate.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(draftIngredients) { ingredient in
                            ingredientRow(ingredient)
                        }
                    }
                }

                Toggle("Batch Meal Prep / Multiple Servings", isOn: $isMealPrep)
                    .font(.meBody.weight(.semibold))
                    .foregroundStyle(Slate.textPrimary)
                    .tint(Slate.textPrimary)
                    .padding(14)
                    .background(Slate.surface, in: RoundedRectangle(cornerRadius: 14))

                if isMealPrep {
                    HStack {
                        Text("Number of servings")
                            .font(.meBody)
                            .foregroundStyle(Slate.textPrimary)
                        Spacer()
                        Stepper(value: $numberOfServings, in: 1...100) {
                            Text("\(numberOfServings)")
                                .font(.meNumber)
                                .foregroundStyle(Slate.textPrimary)
                                .monospacedDigit()
                        }
                        .fixedSize()
                    }
                    .padding(14)
                    .background(Slate.surface, in: RoundedRectangle(cornerRadius: 14))
                }

                if !draftIngredients.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("MEAL MACROS")
                            .font(.meCaption.weight(.semibold))
                            .tracking(0.7)
                            .foregroundStyle(Slate.textTertiary)
                        macroSummary(title: "Total Batch", macros: previewTotals)
                        Divider().overlay(Slate.stroke)
                        macroSummary(title: "Per Serving", macros: previewTotals.scaled(by: 1 / Double(isMealPrep ? numberOfServings : 1)))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 16)
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .slateScreen()
        .task(id: searchModel.query) { await searchModel.search() }
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
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftIngredients.isEmpty)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    searchFocused = false
                    portionFocused = false
                }
                    .foregroundStyle(Slate.textPrimary)
            }
        }
        .fullScreenCover(isPresented: $showingScanner) {
            BarcodeScannerView { code, food, status, error in
                searchModel.acceptBarcodeLookup(barcode: code, food: food, status: status, error: error)
                if let food { appendFood(food) }
            }
        }
        .alert("Couldn't save meal", isPresented: $showingValidation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Add a name and at least one ingredient.")
        }
        .alert("Couldn't find scanned food", isPresented: barcodeErrorBinding) {
            Button("Search by name") {
                searchModel.barcodeError = nil
                searchFocused = true
            }
            Button("OK", role: .cancel) { searchModel.barcodeError = nil }
        } message: {
            Text(searchModel.barcodeError ?? "Try searching for the food by name.")
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        switch searchModel.phase {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView("Searching foods…")
                .font(.meCaption)
                .tint(Slate.textPrimary)
                .foregroundStyle(Slate.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .results(let foods):
            VStack(spacing: 8) {
                ForEach(foods) { food in
                    Button { appendFood(food) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(food.name)
                                    .font(.meBody.weight(.semibold))
                                    .foregroundStyle(Slate.textPrimary)
                                    .multilineTextAlignment(.leading)
                                Text("\(food.per100g.calories.whole) kcal / 100 g" + (food.brand.map { " · \($0)" } ?? ""))
                                    .font(.meCaption)
                                    .foregroundStyle(Slate.textSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Slate.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Slate.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        case .empty:
            Text("No foods found. Try another search or scan the product barcode.")
                .font(.meCaption)
                .foregroundStyle(Slate.textSecondary)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text("Search didn't load: \(message)")
                    .font(.meCaption)
                    .foregroundStyle(Slate.textSecondary)
                Button("Retry Search") { Task { await searchModel.search() } }
                    .font(.meCaption.weight(.semibold))
                    .foregroundStyle(Slate.textPrimary)
            }
        }
    }

    private func ingredientRow(_ ingredient: MealIngredient) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ingredient.food.name)
                        .font(.meBody.weight(.semibold))
                        .foregroundStyle(Slate.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(ingredient.macros.calories.whole) kcal")
                        .font(.meCaption)
                        .foregroundStyle(Slate.textSecondary)
                }
                Spacer(minLength: 2)
                Button(role: .destructive) {
                    draftIngredients.removeAll { $0.food.id == ingredient.food.id }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Accent.calories)
                        .frame(width: 34, height: 34)
                        .background(Slate.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(ingredient.food.name)")
            }

            HStack(spacing: 10) {
                Text("Portion")
                    .font(.meCaption)
                    .foregroundStyle(Slate.textSecondary)
                Spacer()
                Button { adjustGrams(for: ingredient.food.id, by: -10) } label: {
                    Image(systemName: "minus")
                        .frame(width: 32, height: 32)
                        .background(Slate.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
                TextField("100", value: gramsBinding(for: ingredient.food.id), format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .focused($portionFocused)
                    .multilineTextAlignment(.trailing)
                    .font(.meNumber)
                    .foregroundStyle(Slate.textPrimary)
                    .frame(width: 66)
                Text("g")
                    .font(.meBody)
                    .foregroundStyle(Slate.textSecondary)
                Button { adjustGrams(for: ingredient.food.id, by: 10) } label: {
                    Image(systemName: "plus")
                        .frame(width: 32, height: 32)
                        .background(Slate.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(Slate.textPrimary)
        }
        .padding(14)
        .background(Slate.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Slate.stroke.opacity(0.7), lineWidth: 1))
    }

    private func gramsBinding(for foodID: String) -> Binding<Double> {
        Binding(
            get: { draftIngredients.first(where: { $0.food.id == foodID })?.grams ?? 100 },
            set: { updateGrams(for: foodID, to: $0) }
        )
    }

    private func adjustGrams(for foodID: String, by amount: Double) {
        updateGrams(for: foodID, to: (draftIngredients.first(where: { $0.food.id == foodID })?.grams ?? 100) + amount)
    }

    private func updateGrams(for foodID: String, to grams: Double) {
        guard let index = draftIngredients.firstIndex(where: { $0.food.id == foodID }) else { return }
        draftIngredients[index].grams = min(2_000, max(1, grams.isFinite ? grams : 1))
    }

    private func appendFood(_ food: FoodItem) {
        searchFocused = false
        if let index = draftIngredients.firstIndex(where: { $0.food.id == food.id }) {
            draftIngredients[index].grams = min(2_000, draftIngredients[index].grams + (food.servingGrams ?? 100))
        } else {
            draftIngredients.append(MealIngredient(food: food, grams: min(2_000, max(1, food.servingGrams ?? 100))))
        }
        searchModel.query = ""
    }

    private func saveMeal() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !draftIngredients.isEmpty else {
            showingValidation = true
            return
        }
        diary.saveCustomMeal(CustomMeal(
            name: cleanName,
            ingredients: draftIngredients,
            numberOfServings: isMealPrep ? numberOfServings : 1,
            isMealPrep: isMealPrep
        ))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func macroSummary(title: String, macros: Macros) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.meHeadline)
                    .foregroundStyle(Slate.textPrimary)
                Spacer()
                Text("\(macros.calories.whole) kcal")
                    .font(.meNumber)
                    .foregroundStyle(Slate.textPrimary)
            }
            MacroChips(macros: macros)
        }
    }
}
