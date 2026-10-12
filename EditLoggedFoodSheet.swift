import SwiftUI
import UIKit

struct EditLoggedFoodSheet: View {
    @Environment(DiaryStore.self) private var diary
    @Environment(\.dismiss) private var dismiss

    let entry: DiaryEntry

    @State private var gramsText: String
    @State private var category: MealCategory
    @State private var showingDeleteConfirmation = false

    init(entry: DiaryEntry) {
        self.entry = entry
        _gramsText = State(initialValue: Self.gramsString(entry.grams))
        _category = State(initialValue: entry.category)
    }

    private var grams: Double? {
        guard let value = Double(gramsText.replacingOccurrences(of: ",", with: ".")),
              value.isFinite, value > 0 else { return nil }
        return value
    }

    private var preview: Macros {
        entry.food.per100g.scaled(by: (grams ?? 0) / 100)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.customMealName ?? entry.food.name)
                            .font(.meHeadline)
                            .foregroundStyle(Slate.textPrimary)
                        if let brand = entry.food.brand, !brand.isEmpty {
                            Text(brand)
                                .font(.meCaption)
                                .foregroundStyle(Slate.textSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Portion size")
                            .font(.meCaption.weight(.semibold))
                            .foregroundStyle(Slate.textSecondary)
                        HStack(spacing: 10) {
                            TextField("Grams", text: $gramsText)
                                .keyboardType(.decimalPad)
                                .font(.meNumber)
                                .foregroundStyle(Slate.textPrimary)
                                .padding(13)
                                .background(Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                            Text("g")
                                .font(.meBody.weight(.semibold))
                                .foregroundStyle(Slate.textSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Meal")
                            .font(.meCaption.weight(.semibold))
                            .foregroundStyle(Slate.textSecondary)
                        Picker("Meal", selection: $category) {
                            ForEach(MealCategory.allCases) { meal in
                                Text(meal.title).tag(meal)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Updated nutrition")
                            .font(.meHeadline)
                            .foregroundStyle(Slate.textPrimary)
                        HStack(spacing: 8) {
                            macroPreview("Calories", value: "\(preview.calories.whole) kcal", color: Accent.calories)
                            macroPreview("Protein", value: "\(preview.protein.whole) g", color: Accent.protein)
                            macroPreview("Carbs", value: "\(preview.carbs.whole) g", color: Accent.carbs)
                            macroPreview("Fat", value: "\(preview.fat.whole) g", color: Accent.fat)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Slate.surface, in: RoundedRectangle(cornerRadius: 16))

                    Button {
                        guard let grams else { return }
                        var updated = entry
                        updated.grams = grams
                        updated.category = category
                        diary.updateLoggedEntry(updated)
                        dismiss()
                    } label: {
                        Text("Save Changes")
                    }
                    .buttonStyle(.primary)
                    .disabled(grams == nil)

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Entry", systemImage: "trash")
                            .font(.meBody.weight(.semibold))
                            .foregroundStyle(Accent.calories)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .slateScreen()
            .navigationTitle("Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Slate.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Slate.textPrimary)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
            .alert("Delete this diary entry?", isPresented: $showingDeleteConfirmation) {
                Button("Delete Entry", role: .destructive) {
                    diary.deleteLoggedEntry(entry)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove the food and its macros from your daily totals.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func macroPreview(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Slate.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private static func gramsString(_ grams: Double) -> String {
        guard grams == grams.rounded(), grams <= Double(Int.max) else { return String(grams) }
        return String(Int(grams))
    }
}
