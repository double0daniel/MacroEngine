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

struct OpenFoodFactsService: Sendable {
    static let shared = OpenFoodFactsService()

    private let base = "https://world.openfoodfacts.org"
    private static let fields = "code,product_name,brands,nutriments,serving_quantity,image_small_url"

    // MARK: Public API

    func search(_ query: String, page: Int = 1) async throws -> [FoodItem] {
        // Prefer products tagged as sold in the United Kingdom, then fall back to the
        // full Open Food Facts catalogue so untagged products are still discoverable.
        do {
            let ukResponse: SearchResponse = try await fetch(searchURL(query, page: page, ukOnly: true))
            let ukItems = uniqueFoods(from: ukResponse.products)
            if !ukItems.isEmpty { return ukItems }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch {
            // Some catalogue responses may not support the country filter; use global search.
        }

        let globalResponse: SearchResponse = try await fetch(searchURL(query, page: page, ukOnly: false))
        return uniqueFoods(from: globalResponse.products)
    }

    private func searchURL(_ query: String, page: Int, ukOnly: Bool) -> URL? {
        guard var components = URLComponents(string: "\(base)/cgi/search.pl") else { return nil }
        var queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "30"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "fields", value: Self.fields)
        ]
        if ukOnly {
            queryItems.append(URLQueryItem(name: "countries_tags_en", value: "united-kingdom"))
        }
        components.queryItems = queryItems
        return components.url
    }

    private func uniqueFoods(from products: [Product]) -> [FoodItem] {
        var seen = Set<String>()
        return products
            .compactMap(\.foodItem)
            .filter { seen.insert($0.id).inserted }
    }

    func product(barcode: String) async throws -> FoodItem {
        let code = barcode.filter(\.isNumber)
        guard !code.isEmpty,
              var components = URLComponents(string: "\(base)/api/v2/product/\(code).json") else {
            throw FoodServiceError.invalidURL
        }
        components.queryItems = [.init(name: "fields", value: Self.fields)]

        do {
            let response: ProductResponse = try await fetch(components.url)
            guard response.status == 1, let item = response.product?.foodItem else {
                throw FoodServiceError.notFound
            }
            return item
        } catch FoodServiceError.badStatus(404) {
            throw FoodServiceError.notFound
        }
    }

    // MARK: Networking

    private func fetch<T: Decodable>(_ url: URL?) async throws -> T {
        guard let url else { throw FoodServiceError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 15)
        // Open Food Facts asks apps to identify themselves.
        request.setValue("MacroEngine/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
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
