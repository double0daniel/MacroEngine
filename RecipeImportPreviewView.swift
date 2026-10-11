import SwiftUI

struct RecipeImportPreviewView: View {
    @Environment(DiaryStore.self) private var diary
    @Environment(\.dismiss) private var dismiss

    @State private var pastedURL = ""
    @State private var mealName = ""
    @State private var servingsText = "1"
    @State private var caloriesText = "0"
    @State private var proteinText = "0"
    @State private var carbsText = "0"
    @State private var fatText = "0"
    @State private var ingredientLines: [String] = []
    @State private var matchedIngredientCount = 0
    @State private var isLoading = false
    @State private var hasReview = false
    @State private var errorMessage: String?
    @State private var previousServings = 1
    @State private var adjustMacrosWithServings = true
    @FocusState private var focusedField: ImportField?

    private enum ImportField: Hashable {
        case servings, calories, protein, carbs, fat
    }

    private var parsedServings: Int? {
        guard let value = Int(servingsText), value > 0, value <= 100 else { return nil }
        return value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                introCard
                linkCard

                if isLoading {
                    HStack(spacing: 12) {
                        ProgressView().tint(Slate.textPrimary)
                        Text("Reading recipe and estimating ingredients…")
                            .font(.meBody)
                            .foregroundStyle(Slate.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                if let errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Manual review available", systemImage: "info.circle.fill")
                            .font(.meHeadline)
                            .foregroundStyle(Slate.textPrimary)
                        Text(errorMessage)
                            .font(.meBody)
                            .foregroundStyle(Slate.textSecondary)
                        Button("Try Link Again") { Task { await importRecipe() } }
                            .buttonStyle(.primary)
                            .disabled(isLoading)
                    }
                    .card()
                }

                if hasReview { reviewForm }
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .slateScreen()
        .navigationTitle("Import Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Slate.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }.foregroundStyle(Slate.textPrimary)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }.foregroundStyle(Slate.textPrimary)
            }
        }
        .onChange(of: servingsText) { _, newValue in
            guard let newServings = Int(newValue), newServings > 0, previousServings > 0 else { return }
            if adjustMacrosWithServings {
                let scale = Double(previousServings) / Double(newServings)
                caloriesText = scaled(caloriesText, by: scale)
                proteinText = scaled(proteinText, by: scale)
                carbsText = scaled(carbsText, by: scale)
                fatText = scaled(fatText, by: scale)
            }
            previousServings = newServings
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("URL & Social Recipe Importer", systemImage: "link")
                .font(.meHeadline)
                .foregroundStyle(Slate.textPrimary)
            Text("Paste a public recipe or social post link. MacroEngine reads recipe details when available and estimates ingredients with Open Food Facts.")
                .font(.meBody)
                .foregroundStyle(Slate.textSecondary)
        }
        .card()
    }

    private var linkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recipe link")
                .font(.meHeadline)
                .foregroundStyle(Slate.textPrimary)
            TextField("Paste TikTok / Web Link", text: $pastedURL, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .foregroundStyle(Slate.textPrimary)
                .padding(14)
                .background(Slate.background, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Slate.stroke, lineWidth: 1))
            Button {
                Task { await importRecipe() }
            } label: {
                HStack(spacing: 8) {
                    if isLoading { ProgressView().tint(Slate.background) }
                    else { Image(systemName: "wand.and.stars") }
                    Text(isLoading ? "Importing…" : "Import & Estimate")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .disabled(isLoading || pastedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .card()
    }

    private var reviewForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Review your recipe")
                    .font(.meHeadline)
                    .foregroundStyle(Slate.textPrimary)
                Text("Macro values are per serving. Ingredient estimates can vary, so check them before saving.")
                    .font(.meCaption)
                    .foregroundStyle(Slate.textSecondary)
            }

            labeledField("Meal Name", placeholder: "Recipe name", text: $mealName)
            numericField("Number of Servings", text: $servingsText, field: .servings, suffix: "servings", decimals: false)

            VStack(alignment: .leading, spacing: 10) {
                Text("PER SERVING")
                    .font(.meCaption.weight(.semibold))
                    .tracking(0.7)
                    .foregroundStyle(Slate.textTertiary)
                numericField("Total Calories", text: $caloriesText, field: .calories, suffix: "kcal")
                numericField("Protein", text: $proteinText, field: .protein, suffix: "g")
                numericField("Carbs", text: $carbsText, field: .carbs, suffix: "g")
                numericField("Fat", text: $fatText, field: .fat, suffix: "g")
            }

            if !ingredientLines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Ingredients found", systemImage: "list.bullet")
                        .font(.meCaption.weight(.semibold))
                        .foregroundStyle(Slate.textPrimary)
                    Text(ingredientLines.prefix(8).joined(separator: "\n"))
                        .font(.meCaption)
                        .foregroundStyle(Slate.textSecondary)
                        .lineLimit(12)
                    Text("Matched \(matchedIngredientCount) of \(ingredientLines.count) ingredient lines for the estimate.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Slate.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(Slate.background, in: RoundedRectangle(cornerRadius: 14))
            } else {
                Text("No ingredient list was detected. Enter the recipe name, servings, and macro values manually.")
                    .font(.meCaption)
                    .foregroundStyle(Slate.textSecondary)
            }

            Button {
                saveMeal()
            } label: {
                Label("Save as Custom Meal", systemImage: "bookmark.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .disabled(mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !macroValuesAreValid || parsedServings == nil)
        }
        .card()
    }

    private var macroValuesAreValid: Bool {
        [caloriesText, proteinText, carbsText, fatText].allSatisfy { value in
            guard let number = Double(value.replacingOccurrences(of: ",", with: ".")) else { return false }
            return number.isFinite && number >= 0
        }
    }

    private func labeledField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.meCaption).foregroundStyle(Slate.textSecondary)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.words)
                .foregroundStyle(Slate.textPrimary)
                .padding(12)
                .background(Slate.background, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func numericField(_ title: String, text: Binding<String>, field: ImportField, suffix: String, decimals: Bool = true) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.meBody)
                .foregroundStyle(Slate.textPrimary)
            Spacer(minLength: 8)
            TextField("0", text: text)
                .keyboardType(decimals ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: field)
                .frame(width: 84)
                .foregroundStyle(Slate.textPrimary)
                .padding(10)
                .background(Slate.background, in: RoundedRectangle(cornerRadius: 10))
            Text(suffix)
                .font(.meCaption)
                .foregroundStyle(Slate.textSecondary)
                .frame(width: 48, alignment: .leading)
        }
    }

    @MainActor
    private func importRecipe() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let draft = try await RecipeImporterService().importRecipe(from: pastedURL)
            mealName = draft.name
            servingsText = String(draft.servings)
            previousServings = draft.servings
            adjustMacrosWithServings = !draft.usedDirectMacroCallouts
            caloriesText = format(draft.macrosPerServing.calories)
            proteinText = format(draft.macrosPerServing.protein)
            carbsText = format(draft.macrosPerServing.carbs)
            fatText = format(draft.macrosPerServing.fat)
            ingredientLines = draft.ingredientLines
            matchedIngredientCount = draft.matchedIngredientCount
            hasReview = true
            if draft.ingredientLines.isEmpty && draft.macrosPerServing == .zero {
                errorMessage = "No recipe data was detected from this link. Use the editable fields to enter the details manually."
            } else if !draft.ingredientLines.isEmpty && draft.matchedIngredientCount == 0 && !draft.usedDirectMacroCallouts {
                errorMessage = "Ingredients were found, but none could be estimated from Open Food Facts. Enter or correct the macros manually."
            } else if draft.matchedIngredientCount < draft.ingredientLines.count && !draft.usedDirectMacroCallouts {
                errorMessage = "Some ingredients could not be matched. Review and edit the estimated macros before saving."
            }
        } catch {
            mealName = fallbackName(from: pastedURL)
            servingsText = "1"
            previousServings = 1
            adjustMacrosWithServings = true
            caloriesText = "0"
            proteinText = "0"
            carbsText = "0"
            fatText = "0"
            ingredientLines = []
            matchedIngredientCount = 0
            hasReview = true
            errorMessage = error.localizedDescription + " Enter the details in the review form, or correct the link and try again."
        }
    }

    @MainActor
    private func saveMeal() {
        guard macroValuesAreValid,
              let calories = parsedNumber(caloriesText),
              let protein = parsedNumber(proteinText),
              let carbs = parsedNumber(carbsText),
              let fat = parsedNumber(fatText) else { return }
        let cleanName = mealName.trimmingCharacters(in: .whitespacesAndNewlines)
        let macros = Macros(calories: calories, protein: protein, carbs: carbs, fat: fat)
        let host = URL(string: pastedURL)?.host?.replacingOccurrences(of: "www.", with: "")
        let importedFood = FoodItem(
            id: "recipe-import-\(UUID().uuidString)",
            name: "\(cleanName) · per serving",
            brand: host.map { "Recipe import · \($0)" } ?? "Recipe import",
            per100g: macros,
            servingGrams: 100,
            imageURL: nil
        )
        let meal = CustomMeal(
            name: cleanName,
            ingredients: [MealIngredient(food: importedFood, grams: 100)],
            sourceServings: parsedServings ?? 1,
            sourceURL: pastedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        diary.saveCustomMeal(meal)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func fallbackName(from pastedURL: String) -> String {
        guard let url = URL(string: pastedURL), let host = url.host else { return "Imported recipe" }
        return host.replacingOccurrences(of: "www.", with: "").components(separatedBy: ".").first?.capitalized ?? "Imported recipe"
    }

    private func parsedNumber(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private func format(_ value: Double) -> String {
        value.isFinite ? String(format: "%.1f", value) : "0"
    }

    private func scaled(_ value: String, by factor: Double) -> String {
        guard let number = parsedNumber(value), factor.isFinite else { return value }
        return format(number * factor)
    }
}
