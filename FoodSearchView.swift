import SwiftUI

// MARK: - Search view model

@MainActor
@Observable
final class FoodSearchViewModel {
    enum Phase: Equatable {
        case idle, loading, results([FoodItem]), empty, failed(String)
    }

    var query = ""
    var phase: Phase = .idle
    var isLookingUpBarcode = false
    var barcodeError: String?
    var apiStatus: FoodAPIStatus?
    var recentSearches: [String]

    private let service = OpenFoodFactsService.shared
    private let recentSearchesKey = "macroengine.search.recent.v1"

    init() {
        recentSearches = UserDefaults.standard.stringArray(forKey: recentSearchesKey) ?? []
    }

    /// Called from `.task(id: query)`. The 350 ms pause debounces typing, and
    /// SwiftUI cancels the previous task whenever the query changes.
    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            phase = .idle
            apiStatus = nil
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(350))
            if Task.isCancelled { return }
            phase = .loading
            apiStatus = nil
            let result = try await service.searchWithStatus(trimmed)
            if Task.isCancelled { return }
            apiStatus = result.status
            phase = result.foods.isEmpty ? .empty : .results(result.foods)
            rememberSearch(trimmed)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            if !Task.isCancelled {
                apiStatus = .unavailable
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func lookup(barcode: String) async -> FoodItem? {
        isLookingUpBarcode = true
        defer { isLookingUpBarcode = false }
        do {
            let result = try await service.productWithStatus(barcode: barcode)
            apiStatus = result.status
            return result.food
        } catch FoodServiceError.notFound {
            apiStatus = .liveNoMatch
            barcodeError = "Open Food Facts doesn't have nutrition data for \(barcode) yet. Try searching by name."
            return nil
        } catch {
            apiStatus = .unavailable
            barcodeError = error.localizedDescription
            return nil
        }
    }

    func acceptBarcodeLookup(barcode: String, food: FoodItem?, status: FoodAPIStatus, error: String?) {
        apiStatus = status
        guard food == nil else { return }
        barcodeError = error ?? "Open Food Facts doesn't have nutrition data for \(barcode) yet. Try searching by name."
    }

    func clearSearchHistory() {
        recentSearches = []
        query = ""
        phase = .idle
        apiStatus = nil
        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
    }

    private func rememberSearch(_ query: String) {
        recentSearches.removeAll { $0.localizedCaseInsensitiveCompare(query) == .orderedSame }
        recentSearches.insert(query, at: 0)
        recentSearches = Array(recentSearches.prefix(8))
        UserDefaults.standard.set(recentSearches, forKey: recentSearchesKey)
    }
}

private enum FoodSearchSection: String, CaseIterable, Identifiable {
    case search = "Search"
    case favorites = "Favourites"
    case customMeals = "Custom meals"
    var id: String { rawValue }
}

// MARK: - Search, scan, favourites and saved meals

struct FoodSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = FoodSearchViewModel()
    @State private var selectedFood: FoodItem?
    @State private var showingScanner = false
    @State private var section: FoodSearchSection = .search
    @State private var selectedCategory: MealCategory
    @FocusState private var searchFocused: Bool

    init(initialCategory: MealCategory = .snacks) {
        _selectedCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                sectionPicker
                if section != .customMeals { categoryPicker }
                if section == .search {
                    searchBar
                    apiStatusIndicator
                    searchContent
                } else if section == .favorites {
                    FavoritesSectionView(category: selectedCategory) { food in
                        selectedFood = food
                    }
                } else {
                    CustomMealsSectionView(initialCategory: selectedCategory)
                }
            }
            .padding(.top, 8)
            .slateScreen()
            .navigationTitle(section == .search ? "Add food" : section.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Slate.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Slate.textPrimary)
                }
            }
            .navigationDestination(item: $selectedFood) { food in
                FoodDetailView(food: food, initialCategory: selectedCategory) { dismiss() }
            }
            .overlay {
                if viewModel.isLookingUpBarcode { lookupOverlay }
            }
            .alert("Couldn't find that product", isPresented: errorBinding) {
                Button("Scan again") { showingScanner = true }
                Button("Search by name", role: .cancel) { searchFocused = true; section = .search }
            } message: {
                Text(viewModel.barcodeError ?? "")
            }
        }
        .task(id: viewModel.query) { await viewModel.search() }
        .fullScreenCover(isPresented: $showingScanner) {
            BarcodeScannerView { code, food, status, error in
                viewModel.acceptBarcodeLookup(barcode: code, food: food, status: status, error: error)
                if let food { selectedFood = food }
            }
        }
        .onAppear { searchFocused = true }
        .preferredColorScheme(.dark)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.barcodeError != nil },
            set: { if !$0 { viewModel.barcodeError = nil } }
        )
    }

    private var sectionPicker: some View {
        Picker("Food library section", selection: $section) {
            ForEach(FoodSearchSection.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .onChange(of: section) { _, newValue in
            if newValue != .search { searchFocused = false }
        }
    }

    private var categoryPicker: some View {
        HStack {
            Text("ADD TO")
                .font(.meCaption)
                .tracking(0.8)
                .foregroundStyle(Slate.textTertiary)
            Spacer()
            Picker("Meal category", selection: $selectedCategory) {
                ForEach(MealCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }
            .tint(Slate.textPrimary)
        }
        .padding(.horizontal, 22)
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Slate.textTertiary)

                TextField("", text: $viewModel.query,
                          prompt: Text("Search foods").foregroundStyle(Slate.textTertiary))
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .foregroundStyle(Slate.textPrimary)

                if !viewModel.query.isEmpty {
                    Button("Clear") {
                        viewModel.query = ""
                        viewModel.phase = .idle
                        searchFocused = true
                    }
                    .font(.meCaption.weight(.semibold))
                    .foregroundStyle(Slate.textSecondary)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Slate.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Slate.stroke.opacity(0.6), lineWidth: 1)
            )

            Button {
                searchFocused = false
                showingScanner = true
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Slate.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityLabel("Scan barcode")

            Button {
                viewModel.clearSearchHistory()
                searchFocused = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Slate.textSecondary)
                    .frame(width: 42, height: 48)
                    .background(Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(viewModel.query.isEmpty && viewModel.recentSearches.isEmpty)
            .opacity(viewModel.query.isEmpty && viewModel.recentSearches.isEmpty ? 0.45 : 1)
            .accessibilityLabel("Clear recent search history and query")
        }
        .padding(.horizontal, 20)
    }

    // MARK: Search content

    @ViewBuilder private var searchContent: some View {
        switch viewModel.phase {
        case .idle:
            if viewModel.recentSearches.isEmpty {
                EmptyStateView(
                    symbol: "text.magnifyingglass",
                    title: "Find a food",
                    message: "Search by name or brand, or scan the barcode on the package."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent searches")
                            .font(.meCaption.weight(.semibold))
                            .foregroundStyle(Slate.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(viewModel.recentSearches, id: \.self) { recent in
                            Button {
                                viewModel.query = recent
                                searchFocused = true
                            } label: {
                                Label(recent, systemImage: "clock.arrow.circlepath")
                                    .font(.meBody)
                                    .foregroundStyle(Slate.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Slate.surface, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                }
            }

        case .loading:
            ProgressView()
                .tint(Slate.textSecondary)
                .frame(maxHeight: .infinity)

        case .results(let items):
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            searchFocused = false
                            selectedFood = item
                        } label: {
                            FoodResultRow(food: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

        case .empty:
            EmptyStateView(
                symbol: "magnifyingglass",
                title: "No matches",
                message: "Try a shorter name, or scan the barcode on the package."
            )
            .frame(maxHeight: .infinity)

        case .failed(let message):
            EmptyStateView(
                symbol: "wifi.exclamationmark",
                title: "Search didn't load",
                message: message,
                actionTitle: "Retry Search"
            ) {
                Task { await viewModel.search() }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var apiStatusIndicator: some View {
        Group {
            if let status = viewModel.apiStatus {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(status.isLive ? Accent.fat : Accent.calories)
                            .frame(width: 7, height: 7)
                        Text(status.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Slate.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Slate.surfaceRaised, in: Capsule())
                    Spacer(minLength: 0)
                    if status == .offlineCache {
                        Button("Retry Search") {
                            Task { await viewModel.search() }
                        }
                        .font(.meCaption.weight(.semibold))
                        .foregroundStyle(Slate.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Slate.surfaceRaised, in: Capsule())
                    }
                }
                .padding(.horizontal, 22)
                .accessibilityElement(children: .contain)
            }
        }
    }

    private var lookupOverlay: some View {
        ZStack {
            Slate.background.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(Slate.textPrimary)
                Text("Looking up barcode")
                    .font(.meBody)
                    .foregroundStyle(Slate.textSecondary)
            }
            .padding(24)
            .card(padding: 0)
        }
    }
}

// MARK: - Result row

struct FoodResultRow: View {
    let food: FoodItem

    var body: some View {
        HStack(spacing: 14) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(food.name)
                    .font(.meHeadline)
                    .foregroundStyle(Slate.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let brand = food.brand {
                    Text(brand)
                        .font(.meBody)
                        .foregroundStyle(Slate.textSecondary)
                        .lineLimit(1)
                }
                MacroChips(macros: food.per100g)
                    .padding(.top, 2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(food.per100g.calories.whole)")
                    .font(.meNumber)
                    .foregroundStyle(Slate.textPrimary)
                Text("kcal/100 g")
                    .font(.meCaption)
                    .foregroundStyle(Slate.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
        .contentShape(Rectangle())
    }

    private var thumbnail: some View {
        AsyncImage(url: food.imageURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Image(systemName: "fork.knife")
                    .font(.title3)
                    .foregroundStyle(Slate.textTertiary)
            }
        }
        .frame(width: 52, height: 52)
        .background(Slate.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Selected food + portion editor

struct FoodDetailView: View {
    let food: FoodItem
    var onAdded: () -> Void

    @Environment(DiaryStore.self) private var diary
    @State private var grams: Double
    @State private var category: MealCategory
    @FocusState private var amountFocused: Bool

    init(food: FoodItem, initialCategory: MealCategory = .snacks, onAdded: @escaping () -> Void) {
        self.food = food
        self.onAdded = onAdded
        _grams = State(initialValue: min(2000, max(0, food.servingGrams ?? 100)))
        _category = State(initialValue: initialCategory)
    }

    private var macros: Macros { food.per100g.scaled(by: max(grams, 0) / 100) }

    private var presets: [Double] {
        var values: [Double] = [50, 100, 200]
        if let serving = food.servingGrams, serving > 0, !values.contains(serving) {
            values.append(serving)
            values.sort()
        }
        return values
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                amountCard
                nutritionCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .slateScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Slate.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { amountFocused = false }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Add to \(category.title)") {
                diary.add(food, grams: grams, category: category)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onAdded()
            }
            .buttonStyle(.primary)
            .disabled(grams <= 0 || !grams.isFinite)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Slate.background.ignoresSafeArea())
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(food.name)
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(Slate.textPrimary)
                if let brand = food.brand {
                    Text(brand)
                        .font(.meBody)
                        .foregroundStyle(Slate.textSecondary)
                }
                Text("Nutrition is shown for your selected portion.")
                    .font(.meCaption)
                    .foregroundStyle(Slate.textTertiary)
                    .padding(.top, 3)
            }
            Spacer(minLength: 0)
            Button {
                diary.toggleFavorite(food)
            } label: {
                Image(systemName: diary.isFavorite(food) ? "star.fill" : "star")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(diary.isFavorite(food) ? Slate.textPrimary : Slate.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Slate.surfaceRaised, in: Circle())
            }
            .accessibilityLabel(diary.isFavorite(food) ? "Remove from favourites" : "Save to favourites")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Portion size")
                .font(.meHeadline)
                .foregroundStyle(Slate.textPrimary)

            HStack(spacing: 12) {
                stepButton(symbol: "minus", label: "Decrease amount") { grams = max(0, grams - 10) }

                HStack(spacing: 6) {
                    TextField("0", value: $grams, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .multilineTextAlignment(.trailing)
                        .font(.meDisplay)
                        .foregroundStyle(Slate.textPrimary)
                    Text("g")
                        .font(.meHeadline)
                        .foregroundStyle(Slate.textSecondary)
                }
                .frame(maxWidth: .infinity)

                stepButton(symbol: "plus", label: "Increase amount") { grams = min(2000, grams + 10) }
            }

            Slider(value: $grams, in: 0...2000, step: 5)
                .tint(Slate.textPrimary)
                .accessibilityLabel("Portion size in grams")
            HStack {
                Text("0 g")
                Spacer()
                Text("2,000 g")
            }
            .font(.meCaption)
            .foregroundStyle(Slate.textTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { value in
                        Button {
                            grams = value
                        } label: {
                            Text(value == food.servingGrams ? "1 serving · \(value.whole) g" : "\(value.whole) g")
                        }
                        .buttonStyle(ChipStyle(selected: grams == value))
                    }
                }
            }

            Divider().overlay(Slate.stroke)
            HStack {
                Text("Log as")
                    .font(.meBody)
                    .foregroundStyle(Slate.textSecondary)
                Spacer()
                Picker("Meal category", selection: $category) {
                    ForEach(MealCategory.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .tint(Slate.textPrimary)
            }
        }
        .card(padding: 18)
    }

    private func stepButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Slate.textPrimary)
                .frame(width: 44, height: 44)
                .background(Slate.surfaceRaised, in: Circle())
        }
        .accessibilityLabel(label)
    }

    private var nutritionCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                MacroIcon(kind: .calories)
                Text("Calories")
                    .font(.meBody)
                    .foregroundStyle(Slate.textSecondary)
                Spacer()
                Text("\(macros.calories.whole)")
                    .font(.meDisplay)
                    .foregroundStyle(Slate.textPrimary)
                Text("kcal")
                    .font(.meBody)
                    .foregroundStyle(Slate.textSecondary)
            }

            ForEach(MacroKind.macros) { kind in
                Divider().overlay(Slate.stroke).padding(.vertical, 12)
                HStack(spacing: 14) {
                    MacroIcon(kind: kind)
                    Text(kind.title)
                        .font(.meBody)
                        .foregroundStyle(Slate.textSecondary)
                    Spacer()
                    Text("\(macros[kind].whole) g")
                        .font(.meNumber)
                        .foregroundStyle(Slate.textPrimary)
                }
            }
        }
        .card(padding: 18)
    }
}

#if DEBUG
#Preview {
    FoodSearchView()
        .environment(DiaryStore.preview)
}
#endif
