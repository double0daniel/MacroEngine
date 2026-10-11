import Foundation

struct RecipeImportDraft: Sendable {
    var name: String
    var servings: Int
    var ingredientLines: [String]
    var macrosPerServing: Macros
    var matchedIngredientCount: Int
    var usedDirectMacroCallouts: Bool
    var sourceURL: URL
}

enum RecipeImportError: LocalizedError {
    case invalidURL
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a complete web link beginning with https:// or http://."
        case .unavailable: "This page could not be read automatically. You can still enter the recipe details below."
        }
    }
}

struct RecipeImporterService: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func importRecipe(from pastedURL: String) async throws -> RecipeImportDraft {
        guard let url = Self.webURL(from: pastedURL) else { throw RecipeImportError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("MacroEngine iOS Recipe Importer/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw RecipeImportError.unavailable
            }
            return await parse(html: html, url: url)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch {
            throw RecipeImportError.unavailable
        }
    }

    private func parse(html: String, url: URL) async -> RecipeImportDraft {
        let metadata = Self.pageMetadata(from: html)
        let recipe = Self.recipeObject(from: html)
        let title = Self.string(recipe?["name"]) ?? metadata.title ?? Self.hostTitle(url) ?? "Imported recipe"
        let schemaLines = Self.stringArray(recipe?["recipeIngredient"])
        let caption = Self.socialCaption(from: html)
        let lines = schemaLines.isEmpty
            ? Self.ingredientLines(in: metadata.description + "\n" + caption)
            : schemaLines
        let servings = Self.servingCount(recipe?["recipeYield"]) ?? Self.servingCount(in: metadata.description + " " + caption) ?? 1
        let schemaMacros = Self.schemaMacros(recipe?["nutrition"])
        let captionMacros = Self.directMacroCallouts(in: metadata.description + " " + caption)
        let directMacros = schemaMacros ?? captionMacros

        let estimate = await RecipeIngredientMatcher().estimate(lines: lines)
        let calculated = estimate.macros.scaled(by: 1 / Double(max(1, servings)))
        let macros = Self.merge(explicit: directMacros, estimated: calculated)

        return RecipeImportDraft(
            name: title,
            servings: max(1, servings),
            ingredientLines: lines,
            macrosPerServing: macros,
            matchedIngredientCount: estimate.matchedCount,
            usedDirectMacroCallouts: directMacros != nil,
            sourceURL: url
        )
    }

    private static func webURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, host.contains("."),
              let url = components.url else { return nil }
        return url
    }

    private static func recipeObject(from html: String) -> [String: Any]? {
        let pattern = #"(?is)<script\b(?=[^>]*\btype\s*=\s*[\"']application/ld\+json[\"'])[^>]*>(.*?)</script\s*>"#
        for match in matches(pattern, in: html) {
            guard let rawJSON = substring(match, in: html, at: 1) else { continue }
            var jsonText = rawJSON
                .replacingOccurrences(of: "<![CDATA[", with: "")
                .replacingOccurrences(of: "]]>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if jsonText.hasPrefix("<!--") { jsonText = String(jsonText.dropFirst(4)) }
            if jsonText.hasSuffix("-->") { jsonText = String(jsonText.dropLast(3)) }
            guard let data = jsonText.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let recipe = findRecipe(in: value) { return recipe }
        }
        return nil
    }

    private static func findRecipe(in value: Any) -> [String: Any]? {
        if let objects = value as? [[String: Any]] {
            for object in objects {
                if let found = findRecipe(in: object) { return found }
            }
        } else if let object = value as? [String: Any] {
            let types = (object["@type"] as? [String]) ?? [object["@type"] as? String ?? ""]
            let isRecipe = types.contains { type in
                let shortName = type.split(separator: "/").last.map(String.init) ?? type
                return shortName.caseInsensitiveCompare("Recipe") == .orderedSame
            }
            if isRecipe { return object }
            for key in ["@graph", "mainEntity", "mainEntityOfPage", "itemListElement"] {
                if let child = object[key], let found = findRecipe(in: child) { return found }
            }
        }
        return nil
    }

    private static func pageMetadata(from html: String) -> (title: String?, description: String) {
        var title: String?
        var description = ""
        for tag in matches(#"(?is)<meta\b[^>]*>"#, in: html) {
            guard let text = substring(tag, in: html) else { continue }
            let key = attribute("property", in: text) ?? attribute("name", in: text) ?? ""
            let content = attribute("content", in: text) ?? ""
            if ["og:title", "twitter:title"].contains(key.lowercased()), title == nil { title = cleanText(content) }
            if ["og:description", "twitter:description", "description"].contains(key.lowercased()), description.isEmpty {
                description = cleanText(content)
            }
        }
        if title == nil, let match = matches(#"(?is)<title\b[^>]*>(.*?)</title\s*>"#, in: html).first,
           let value = substring(match, in: html, at: 1) {
            title = cleanText(value)
        }
        return (title, description)
    }

    private static func socialCaption(from html: String) -> String {
        // TikTok and Instagram often expose caption text in embedded JSON even when
        // their pages do not include Recipe schema. Decode common HTML entities.
        let snippets = matches(#"(?is)(?:desc|caption|description)[\"']?\s*[:=]\s*[\"']((?:\\.|[^\"'\\]){20,4000})[\"']"#, in: html)
            .compactMap { substring($0, in: html, at: 1) }
        return snippets.map { decodeCaption($0) }.joined(separator: "\n")
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = #"(?is)\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*([\"'])(.*?)\1"#
        guard let match = matches(pattern, in: tag).first else { return nil }
        return substring(match, in: tag, at: 2)
    }

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String { return cleanText(string) }
        if let number = value as? NSNumber { return number.stringValue }
        if let values = value as? [Any] { return values.compactMap { string($0) }.first }
        return nil
    }

    private static func stringArray(_ value: Any?) -> [String] {
        if let values = value as? [Any] { return values.compactMap { string($0) }.filter { !$0.isEmpty } }
        if let value = string(value), !value.isEmpty { return [value] }
        return []
    }

    private static func servingCount(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let number = value as? NSNumber { return number.intValue > 0 ? number.intValue : nil }
        if let values = value as? [Any] { return values.compactMap { servingCount($0) }.first }
        if let text = value as? String { return servingCount(in: text) }
        return nil
    }

    private static func servingCount(in text: String) -> Int? {
        let patterns = [#"(?i)\bserves?\s*[:]?\s*(\d{1,2})\b"#, #"(?i)\b(\d{1,2})\s+servings?\b"#]
        for pattern in patterns {
            if let match = matches(pattern, in: text).first, match.numberOfRanges > 1,
               let value = substring(match, in: text, at: 1),
               let count = Int(value), (1...100).contains(count) { return count }
        }
        return nil
    }

    private static func schemaMacros(_ value: Any?) -> Macros? {
        guard let nutrition = value as? [String: Any] else { return nil }
        let calories = numeric(nutrition["calories"])
        let protein = numeric(nutrition["proteinContent"])
        let carbs = numeric(nutrition["carbohydrateContent"])
        let fat = numeric(nutrition["fatContent"])
        guard calories != nil || protein != nil || carbs != nil || fat != nil else { return nil }
        let p = protein ?? 0
        let c = carbs ?? 0
        let f = fat ?? 0
        return Macros(calories: calories ?? (p * 4 + c * 4 + f * 9), protein: p, carbs: c, fat: f)
    }

    private static func directMacroCallouts(in text: String) -> Macros? {
        let calories = firstNumber(#"(?i)(\d+(?:[.,]\d+)?)\s*(?:kcal|calories|cal)\b"#, in: text)
        let protein = firstNumber(#"(?i)(\d+(?:[.,]\d+)?)\s*g?\s*protein\b"#, in: text)
        let carbs = firstNumber(#"(?i)(\d+(?:[.,]\d+)?)\s*g?\s*(?:carbs?|carbohydrates?)\b"#, in: text)
        let fat = firstNumber(#"(?i)(\d+(?:[.,]\d+)?)\s*g?\s*fat\b"#, in: text)
        guard calories != nil || protein != nil || carbs != nil || fat != nil else { return nil }
        let p = protein ?? 0
        let c = carbs ?? 0
        let f = fat ?? 0
        return Macros(calories: calories ?? (p * 4 + c * 4 + f * 9), protein: p, carbs: c, fat: f)
    }

    private static func ingredientLines(in caption: String) -> [String] {
        let blockPattern = #"(?is)ingredients?\s*[:\-]\s*(.*?)(?:\b(?:method|instructions?|directions?|steps?)\s*[:\-]|\z)"#
        let source = matches(blockPattern, in: caption).first.flatMap { substring($0, in: caption, at: 1) } ?? caption
        let normalized = source
            .replacingOccurrences(of: #"(?i)#[\w]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(?:serves?|servings?)\s*:?\s*\d+\b"#, with: "", options: .regularExpression)
        let parts = normalized.components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: "•;|")))
            .flatMap { $0.components(separatedBy: ",") }
        var result: [String] = []
        for rawPart in parts {
            let line = rawPart
                .replacingOccurrences(of: #"(?i)^\s*(?:ingredients?|for the recipe)\s*[:\-]?\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-*•")))
            let isMacroCallout = line.range(of: #"(?i)^\s*\d+(?:[.,]\d+)?\s*g?\s*(?:kcal|calories|protein|carbs?|carbohydrates?|fat)\b"#, options: .regularExpression) != nil
            let hasAmount = line.range(of: #"(?i)\b\d+(?:[.,]\d+)?\s*(?:kg|g|grams?|ml|l|oz|lbs?|tsp|tbsp|cups?)?\b"#, options: .regularExpression) != nil
            let looksLikeIngredient = line.split(whereSeparator: \.isWhitespace).count >= 2
            if hasAmount && looksLikeIngredient && !isMacroCallout && line.count <= 180 {
                result.append(line)
            }
            if result.count == 20 { break }
        }
        return result
    }

    private static func decodeCaption(_ value: String) -> String {
        var text = value
        for (escaped, replacement) in [("\\n", "\n"), ("\\r", "\n"), ("\\t", " "), ("\\\"", "\""), ("\\'", "'")] {
            text = text.replacingOccurrences(of: escaped, with: replacement)
        }
        text = text.replacingOccurrences(of: "\\u0026", with: "&", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "\\u003c", with: "<", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "\\u003e", with: ">", options: .caseInsensitive)
        return text
    }

    private static func merge(explicit: Macros?, estimated: Macros) -> Macros {
        guard let explicit else { return estimated }
        return Macros(
            calories: explicit.calories > 0 ? explicit.calories : estimated.calories,
            protein: explicit.protein > 0 ? explicit.protein : estimated.protein,
            carbs: explicit.carbs > 0 ? explicit.carbs : estimated.carbs,
            fat: explicit.fat > 0 ? explicit.fat : estimated.fat
        )
    }

    private static func numeric(_ value: Any?) -> Double? {
        guard let text = string(value) else { return nil }
        return firstNumber(#"(\d+(?:[.,]\d+)?)"#, in: text)
    }

    private static func firstNumber(_ pattern: String, in text: String) -> Double? {
        guard let match = matches(pattern, in: text).first,
              let value = substring(match, in: text, at: 1) else { return nil }
        return Double(value.replacingOccurrences(of: ",", with: "."))
    }

    private static func hostTitle(_ url: URL) -> String? {
        url.host?.replacingOccurrences(of: "www.", with: "").components(separatedBy: ".").first?.capitalized
    }

    private static func cleanText(_ input: String) -> String {
        var text = input
        for (entity, replacement) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("\\u0026", "&"), ("\\u003c", "<"), ("\\u003e", ">"), ("\\n", " ")] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func substring(_ match: NSTextCheckingResult, in text: String, at index: Int = 0) -> String? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }
}

private struct RecipeIngredientMatcher: Sendable {
    func estimate(lines: [String]) async -> (macros: Macros, matchedCount: Int) {
        let candidates = Array(lines.prefix(20))
        var total = Macros.zero
        var matchedCount = 0
        await withTaskGroup(of: (Macros, Bool).self) { group in
            var index = 0
            while index < candidates.count {
                let end = min(index + 4, candidates.count)
                for line in candidates[index..<end] {
                    group.addTask {
                        let query = Self.searchTerm(from: line)
                        guard !query.isEmpty else { return (.zero, false) }
                        let foods: [FoodItem]
                        if let cached = OpenFoodFactsService.shared.cachedSearch(query), !cached.isEmpty {
                            foods = cached
                        } else {
                            foods = (try? await OpenFoodFactsService.shared.searchWithStatus(query).foods) ?? []
                        }
                        guard let food = foods.first else { return (.zero, false) }
                        let grams = Self.estimatedGrams(from: line)
                        return (food.per100g.scaled(by: grams / 100), true)
                    }
                }
                for await (macros, matched) in group {
                    total = total + macros
                    if matched { matchedCount += 1 }
                }
                index = end
            }
        }
        return (total, matchedCount)
    }

    private static func searchTerm(from line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: #"^\s*\d+(?:[.,]\d+)?(?:\s*/\s*\d+)?\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\b\d+(?:[.,]\d+)?\b"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)\b(kg|g|grams?|ml|litres?|liters?|l|oz|ounces?|lbs?|pounds?|tsp|teaspoons?|tbsp|tablespoons?|cups?|x|cans?|tins?|of)\b"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[,;:].*$"#, with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func estimatedGrams(from line: String) -> Double {
        let quantityUnitPattern = #"(?i)(\d+(?:[.,]\d+)?)\s*(kg|g|grams?|ml|l|litres?|liters?|oz|ounces?|lbs?|pounds?|tsp|teaspoons?|tbsp|tablespoons?|cups?)\b"#
        if let regex = try? NSRegularExpression(pattern: quantityUnitPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let numberRange = Range(match.range(at: 1), in: line),
           let unitRange = Range(match.range(at: 2), in: line),
           let quantity = Double(line[numberRange].replacingOccurrences(of: ",", with: ".")) {
            let unit = String(line[unitRange]).lowercased()
            if unit == "kg" { return quantity * 1_000 }
            if ["g", "gram", "grams"].contains(unit) { return quantity }
            if unit == "ml" { return quantity }
            if ["l", "litre", "liter", "litres", "liters"].contains(unit) { return quantity * 1_000 }
            if ["oz", "ounce", "ounces"].contains(unit) { return quantity * 28.35 }
            if ["lb", "lbs", "pound", "pounds"].contains(unit) { return quantity * 453.6 }
            if ["tsp", "teaspoon", "teaspoons"].contains(unit) { return quantity * 5 }
            if ["tbsp", "tablespoon", "tablespoons"].contains(unit) { return quantity * 15 }
            if unit == "cup" || unit == "cups" { return quantity * 240 }
        }
        let amount = firstAmount(in: line) ?? 1
        let lower = line.lowercased()
        if lower.contains("to taste") || lower.contains("pinch") { return max(0.5, amount) }
        if lower.contains("clove") && lower.contains("garlic") { return amount * 3 }
        if lower.contains("egg") { return amount * 50 }
        if lower.contains("onion") { return amount * 110 }
        if lower.contains("banana") { return amount * 120 }
        if lower.contains("apple") { return amount * 180 }
        if lower.contains("tomato") { return amount * 120 }
        if lower.contains("pepper") { return amount * 120 }
        if lower.contains("slice") && lower.contains("bread") { return amount * 30 }
        return amount * 100
    }

    private static func firstAmount(in line: String) -> Double? {
        let pattern = #"^\s*(\d+(?:[.,]\d+)?)(?:\s*/\s*(\d+(?:[.,]\d+)?))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let firstRange = Range(match.range(at: 1), in: line),
              let first = Double(line[firstRange].replacingOccurrences(of: ",", with: ".")) else { return nil }
        if match.range(at: 2).location != NSNotFound, let secondRange = Range(match.range(at: 2), in: line),
           let second = Double(line[secondRange]), second > 0 { return first / second }
        return first
    }
}
