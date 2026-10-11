import Foundation

enum FoodServiceError: LocalizedError {
    case invalidURL
    case notFound
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "That request couldn't be built."
        case .notFound: "No product found."
        case .badStatus(let code): "Open Food Facts returned an error (\(code)). Try again in a moment."
        }
    }
}

enum FoodAPIStatus: String, Equatable, Sendable {
    case liveUK
    case liveGlobal
    case liveNoMatch
    case offlineCache
    case unavailable

    var title: String {
        switch self {
        case .liveUK: "Live · UK Open Food Facts"
        case .liveGlobal: "Live · global fallback"
        case .liveNoMatch: "Live · barcode not found"
        case .offlineCache: "Offline / Cached"
        case .unavailable: "Connection unavailable"
        }
    }

    var isLive: Bool { self == .liveUK || self == .liveGlobal || self == .liveNoMatch }
}

struct FoodSearchResult: Sendable {
    let foods: [FoodItem]
    let status: FoodAPIStatus
}

struct FoodLookupResult: Sendable {
    let food: FoodItem
    let status: FoodAPIStatus
}

struct OpenFoodFactsService: Sendable {
    static let shared = OpenFoodFactsService()

    private let ukBase = "https://uk.openfoodfacts.org"
    private let globalBase = "https://world.openfoodfacts.org"
    private let session: URLSession
    private static let fields = "code,product_name,brands,nutriments,serving_quantity,image_small_url"

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Public API

    func search(_ query: String, page: Int = 1) async throws -> [FoodItem] {
        try await searchWithStatus(query, page: page).foods
    }

    /// Returns a previously saved search response without making a network request.
    func cachedSearch(_ query: String) -> [FoodItem]? {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return cached([FoodItem].self, key: searchCacheKey(normalized))
    }

    func searchWithStatus(_ query: String, page: Int = 1) async throws -> FoodSearchResult {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return FoodSearchResult(foods: [], status: .liveUK) }
        let cacheKey = searchCacheKey(normalized)
        var lastError: Error?
        var successfulEmptyStatus: FoodAPIStatus?
        let attempts: [(URL?, FoodAPIStatus)] = [
            (ukSearchURL(normalized, page: page), .liveUK),
            (searchURL(normalized, page: page, base: globalBase, ukOnly: false), .liveGlobal),
            (v2SearchURL(normalized, page: page), .liveGlobal)
        ]

        for (url, status) in attempts {
            do {
                let response: SearchResponse = try await fetch(url)
                let items = uniqueFoods(from: response.products)
                if !items.isEmpty {
                    cache(items, key: cacheKey)
                    return FoodSearchResult(foods: items, status: status)
                }
                successfulEmptyStatus = status
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw error
            } catch {
                lastError = error
            }
        }

        if let cached = cached([FoodItem].self, key: cacheKey), !cached.isEmpty {
            return FoodSearchResult(foods: cached, status: .offlineCache)
        }
        if let successfulEmptyStatus {
            return FoodSearchResult(foods: [], status: successfulEmptyStatus)
        }
        throw lastError ?? FoodServiceError.badStatus(503)
    }

    /// Full-text product search remains on OFF's keyword-search endpoint, hosted on the UK domain first.
    func ukSearchURL(_ query: String, page: Int = 1) -> URL? {
        searchURL(query, page: page, base: ukBase, ukOnly: true)
    }

    private func searchURL(_ query: String, page: Int, base: String, ukOnly: Bool) -> URL? {
        searchURL(query, page: page, base: base, path: "/cgi/search.pl", ukOnly: ukOnly)
    }

    private func v2SearchURL(_ query: String, page: Int) -> URL? {
        searchURL(query, page: page, base: globalBase, path: "/api/v2/search", ukOnly: false)
    }

    private func searchURL(_ query: String, page: Int, base: String, path: String, ukOnly: Bool) -> URL? {
        // Encode user input before assembling query parameters so terms containing
        // &, =, +, ?, or # cannot alter the request's query structure.
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#?%"))
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        var queryParts = [
            "search_terms=\(encodedQuery)",
            "page_size=30",
            "page=\(max(1, page))",
            "fields=\(Self.fields)"
        ]
        if path == "/cgi/search.pl" {
            queryParts += ["search_simple=1", "action=process", "json=1"]
            if ukOnly { queryParts.append("countries_tags_en=united-kingdom") }
        }
        return URL(string: "\(base)\(path)?\(queryParts.joined(separator: "&"))")
    }

    private func uniqueFoods(from products: [Product]) -> [FoodItem] {
        var seen = Set<String>()
        return products
            .compactMap(\.foodItem)
            .filter { seen.insert($0.id).inserted }
    }

    func product(barcode: String) async throws -> FoodItem {
        try await productWithStatus(barcode: barcode).food
    }

    func productWithStatus(barcode: String) async throws -> FoodLookupResult {
        let code = barcode.filter(\.isNumber)
        guard let productURL = ukProductURL(code), !code.isEmpty else { throw FoodServiceError.invalidURL }

        do {
            let response: ProductResponse = try await fetch(productURL)
            guard response.status == 1, let item = response.product?.foodItem else {
                throw FoodServiceError.notFound
            }
            cache(item, key: productCacheKey(code))
            return FoodLookupResult(food: item, status: .liveUK)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch FoodServiceError.notFound {
            throw FoodServiceError.notFound
        } catch FoodServiceError.badStatus(404) {
            throw FoodServiceError.notFound
        } catch {
            if let cached = cached(FoodItem.self, key: productCacheKey(code)) {
                return FoodLookupResult(food: cached, status: .offlineCache)
            }
            throw error
        }
    }

    func ukProductURL(_ barcode: String) -> URL? {
        let code = barcode.filter(\.isNumber)
        guard !code.isEmpty, var components = URLComponents(string: "\(ukBase)/api/v2/product/\(code).json") else {
            return nil
        }
        components.queryItems = [.init(name: "fields", value: Self.fields)]
        return components.url
    }

    private func searchCacheKey(_ query: String) -> String {
        "macroengine.offline.search.\(query.lowercased())"
    }

    private func productCacheKey(_ barcode: String) -> String {
        "macroengine.offline.product.\(barcode)"
    }

    private func cache<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func cached<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: Networking

    private func fetch<T: Decodable>(_ url: URL?) async throws -> T {
        guard let url else { throw FoodServiceError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(
            "MacroEngine - iOS App - Version 1.0 - double0daniel",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FoodServiceError.badStatus(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - DTOs

private struct SearchResponse: Decodable {
    let products: [Product]
}

private struct ProductResponse: Decodable {
    let status: Int?
    let product: Product?
}

/// Open Food Facts sometimes sends numbers as strings.
private struct LossyDouble: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Double(text.replacingOccurrences(of: ",", with: "."))
        } else {
            value = nil
        }
    }
}

private struct Nutriments: Decodable {
    let kcal: LossyDouble?
    let protein: LossyDouble?
    let carbs: LossyDouble?
    let fat: LossyDouble?

    enum CodingKeys: String, CodingKey {
        case kcal = "energy-kcal_100g"
        case protein = "proteins_100g"
        case carbs = "carbohydrates_100g"
        case fat = "fat_100g"
    }
}

private struct Product: Decodable {
    let code: String?
    let productName: String?
    let brands: String?
    let nutriments: Nutriments?
    let servingQuantity: LossyDouble?
    let imageSmallURL: String?

    enum CodingKeys: String, CodingKey {
        case code, brands, nutriments
        case productName = "product_name"
        case servingQuantity = "serving_quantity"
        case imageSmallURL = "image_small_url"
    }

    var foodItem: FoodItem? {
        guard let code,
              let name = productName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
              let nutriments else { return nil }

        let protein = nutriments.protein?.value ?? 0
        let carbs = nutriments.carbs?.value ?? 0
        let fat = nutriments.fat?.value ?? 0
        guard nutriments.kcal?.value != nil || (protein + carbs + fat) > 0 else { return nil }
        let kcal = nutriments.kcal?.value ?? (4 * protein + 4 * carbs + 9 * fat)

        let brand = brands?
            .split(separator: ",")
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let serving = servingQuantity?.value.flatMap { $0 > 0 ? $0 : nil }

        return FoodItem(
            id: code,
            name: name,
            brand: (brand?.isEmpty ?? true) ? nil : brand,
            per100g: Macros(calories: kcal, protein: protein, carbs: carbs, fat: fat),
            servingGrams: serving,
            imageURL: imageSmallURL.flatMap(URL.init(string:))
        )
    }
}
