import Combine
import CoreML
import Foundation

private struct SmolLMLoadedAssets: @unchecked Sendable {
    let model: MLModel
    let tokenizer: SmolLMTokenizer
}

private final class SmolLMInferenceRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?
    private var inferenceTask: Task<Void, Never>?
    private var finished = false

    func install(_ continuation: CheckedContinuation<String?, Never>) {
        lock.lock()
        if finished {
            lock.unlock()
            continuation.resume(returning: nil)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func install(_ inferenceTask: Task<Void, Never>) {
        lock.lock()
        if finished {
            lock.unlock()
            inferenceTask.cancel()
        } else {
            self.inferenceTask = inferenceTask
            lock.unlock()
        }
    }

    func finish(_ value: String?) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        inferenceTask = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }

    func cancel() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        let inferenceTask = self.inferenceTask
        self.continuation = nil
        self.inferenceTask = nil
        lock.unlock()
        inferenceTask?.cancel()
        continuation?.resume(returning: nil)
    }
}

private enum SmolLMModelRunner {
    static func generate(prompt: String, model: MLModel, tokenizer: SmolLMTokenizer) throws -> String? {
        let contextLimit = 32
        let inputTokens = tokenizer.encodePrompt(prompt, maxTokens: contextLimit)
        guard !inputTokens.isEmpty else { return nil }
        let boundedInputTokens = Array(inputTokens.suffix(contextLimit))

        var generated: [Int] = []
        for _ in 0..<24 {
            guard !Task.isCancelled else { return nil }
            let context = Array((boundedInputTokens + generated).suffix(contextLimit))
            let paddedTokens = context + Array(repeating: 0, count: contextLimit - context.count)
            let ids = try MLMultiArray(
                shape: [NSNumber(value: 1), NSNumber(value: contextLimit)],
                dataType: .int32
            )
            let mask = try MLMultiArray(
                shape: [NSNumber(value: 1), NSNumber(value: contextLimit)],
                dataType: .int32
            )

            for (index, token) in paddedTokens.enumerated() {
                let position = [NSNumber(value: 0), NSNumber(value: index)]
                ids[position] = NSNumber(value: token)
                mask[position] = index < context.count ? 1 : 0
            }

            let provider = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": ids,
                "attention_mask": mask
            ])
            let output = try model.prediction(from: provider)
            guard !Task.isCancelled else { return nil }
            guard let logits = output.featureValue(for: "logits")?.multiArrayValue else { return nil }

            let position = context.count - 1
            let nextToken = argmax(logits, position: position)
            if nextToken == tokenizer.endOfTextID || nextToken == tokenizer.endOfTurnID { break }
            generated.append(nextToken)
        }

        let answer = tokenizer.decode(generated).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty, answer.count <= 600 else { return nil }
        return answer
    }

    private static func argmax(_ logits: MLMultiArray, position: Int) -> Int {
        let vocabularySize = logits.shape.last?.intValue ?? 0
        guard vocabularySize > 0 else { return 0 }
        var bestToken = 0
        var bestValue = -Double.infinity
        for token in 0..<vocabularySize {
            let value = logits[[NSNumber(value: 0), NSNumber(value: position), NSNumber(value: token)]].doubleValue
            if value > bestValue {
                bestValue = value
                bestToken = token
            }
        }
        return bestToken
    }
}

/// Small on-device runner for the bundled, fixed-context SmolLM Core ML model.
/// The model and tokenizer are loaded off the main thread. Calls wait for an
/// in-progress model load before attempting inference.
@MainActor
final class SmolLMInferenceService: ObservableObject {
    static let shared = SmolLMInferenceService()

    @Published private(set) var isModelLoaded = false

    private var assets: SmolLMLoadedAssets?
    private var loadingTask: Task<SmolLMLoadedAssets?, Never>?

    private init() {
        Task { [weak self] in
            _ = await self?.loadAssetsIfNeeded()
        }
    }

    /// Runs greedy autoregressive prediction away from the main thread.
    /// The shipped Core ML graph has a fixed 32-token input and logits output.
    func generateResponse(prompt: String) async -> String {
        let fallback = telemetryFallback(from: prompt)
        guard let loadedAssets = await loadAssetsIfNeeded() else { return fallback }

        let race = SmolLMInferenceRace()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                race.install(continuation)
                let inferenceTask = Task.detached(priority: .userInitiated) {
                    do {
                        let response = try SmolLMModelRunner.generate(
                            prompt: prompt,
                            model: loadedAssets.model,
                            tokenizer: loadedAssets.tokenizer
                        )
                        race.finish(response)
                    } catch {
                        race.finish(nil)
                    }
                }
                race.install(inferenceTask)
            }
        } onCancel: {
            // Return to the UI immediately, then stop the detached decode after
            // any currently executing Core ML prediction pass completes.
            race.cancel()
        }
        let response = result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return response.isEmpty ? fallback : response
    }

    private func telemetryFallback(from prompt: String) -> String {
        let pattern = #"Rem:\s*(-?\d+)\s*kcal,\s*(-?\d+)g\s+protein"#
        guard
            let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = expression.firstMatch(in: prompt, range: NSRange(prompt.startIndex..<prompt.endIndex, in: prompt)),
            let caloriesRange = Range(match.range(at: 1), in: prompt),
            let proteinRange = Range(match.range(at: 2), in: prompt),
            let calories = Int(prompt[caloriesRange]),
            let protein = Int(prompt[proteinRange])
        else {
            return "I couldn't generate a reply right now. Please try again."
        }

        let calorieStatus = calories < 0 ? "\(abs(calories)) kcal over" : "\(calories) kcal left"
        let proteinStatus = protein < 0 ? "\(abs(protein)) g over your protein target" : "\(protein) g protein left"
        return "You've got \(calorieStatus) and \(proteinStatus) today. Use that to guide your next meal."
    }

    private func loadAssetsIfNeeded() async -> SmolLMLoadedAssets? {
        if let assets { return assets }
        if let loadingTask { return await loadingTask.value }

        let task = Task.detached(priority: .utility) { () -> SmolLMLoadedAssets? in
            guard
                let modelURL = Bundle.main.url(
                    forResource: "smollm2_135m_instruct_only_logits",
                    withExtension: "mlmodelc",
                    subdirectory: "Models"
                ) ?? Bundle.main.url(forResource: "smollm2_135m_instruct_only_logits", withExtension: "mlmodelc"),
                let tokenizerURL = Bundle.main.url(
                    forResource: "tokenizer",
                    withExtension: "json",
                    subdirectory: "Models/tokenizer"
                ) ?? Bundle.main.url(
                    forResource: "smollm2_135m_instruct_tokenizer",
                    withExtension: "json",
                    subdirectory: "Models"
                ) ?? Bundle.main.url(forResource: "smollm2_135m_instruct_tokenizer", withExtension: "json"),
                let tokenizer = try? SmolLMTokenizer(contentsOf: tokenizerURL)
            else { return nil }

            do {
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .all
                let model = try MLModel(contentsOf: modelURL, configuration: configuration)
                return SmolLMLoadedAssets(model: model, tokenizer: tokenizer)
            } catch {
                return nil
            }
        }
        loadingTask = task
        let loaded = await task.value
        loadingTask = nil
        assets = loaded
        isModelLoaded = loaded != nil
        return loaded
    }

}

/// Minimal Hugging Face GPT-2 byte-level BPE tokenizer for the bundled SmolLM vocabulary.
private struct SmolLMTokenizer: Sendable {
    private struct File: Decodable {
        struct Model: Decodable {
            let vocab: [String: Int]
            let merges: MergeList
        }
        struct MergeList: Decodable {
            let values: [String]

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let stringMerges = try? container.decode([String].self) {
                    values = stringMerges
                } else {
                    values = try container.decode([[String]].self).map { $0.joined(separator: " ") }
                }
            }
        }
        struct AddedToken: Decodable {
            let id: Int
            let content: String
        }
        let model: Model
        let addedTokens: [AddedToken]

        enum CodingKeys: String, CodingKey {
            case model
            case addedTokens = "added_tokens"
        }
    }

    private let vocabulary: [String: Int]
    private let tokenStrings: [Int: String]
    private let mergeRanks: [String: Int]
    private let byteToUnicode: [UInt8: UnicodeScalar]
    private let unicodeToByte: [UnicodeScalar: UInt8]
    let endOfTextID: Int
    let endOfTurnID: Int

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(File.self, from: data)
        vocabulary = file.model.vocab
        tokenStrings = Dictionary(uniqueKeysWithValues: file.model.vocab.map { ($0.value, $0.key) })
        mergeRanks = Dictionary(uniqueKeysWithValues: file.model.merges.values.enumerated().map { ($0.element, $0.offset) })

        let maps = Self.byteMaps()
        byteToUnicode = maps.forward
        unicodeToByte = maps.reverse
        let specials = Dictionary(uniqueKeysWithValues: file.addedTokens.map { ($0.content, $0.id) })
        endOfTextID = specials["<|endoftext|>"] ?? 0
        endOfTurnID = specials["<|im_end|>"] ?? 2
    }

    func encode(_ text: String) -> [Int] {
        let pattern = #"(?i:'s|'t|'re|'ve|'m|'ll|'d)| ?\p{L}+| ?\p{N}| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let pieces = expression.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }

        return pieces.flatMap { piece -> [Int] in
            let byteLevel = String(String.UnicodeScalarView(piece.utf8.compactMap { byteToUnicode[$0] }))
            return bpe(byteLevel).map { vocabulary[$0] ?? endOfTextID }
        }
    }

    func encodePrompt(_ prompt: String, maxTokens: Int) -> [Int] {
        guard
            let queryMarker = prompt.range(of: "Query: '", options: .caseInsensitive),
            let answerMarker = prompt.range(of: "Short answer:", options: .caseInsensitive),
            queryMarker.upperBound <= answerMarker.lowerBound
        else {
            return Array(encode(prompt).suffix(maxTokens))
        }

        let telemetryPrefix = encode(String(prompt[..<queryMarker.lowerBound]))
        let queryLead = encode(String(prompt[queryMarker.lowerBound..<queryMarker.upperBound]))
        let queryTokens = encode(String(prompt[queryMarker.upperBound..<answerMarker.lowerBound]))
        let answerLead = encode(String(prompt[answerMarker.lowerBound...]))

        // Keep the live telemetry at the end of the prefix and reserve space for
        // the user's query and answer cue in the model's fixed 32-token context.
        let queryBudget = min(16, queryTokens.count)
        let prefixBudget = max(0, maxTokens - queryLead.count - answerLead.count - queryBudget)
        let boundedPrefix = Array(telemetryPrefix.suffix(prefixBudget))
        let availableForQuery = max(0, maxTokens - boundedPrefix.count - queryLead.count - answerLead.count)
        let boundedQuery = Array(queryTokens.prefix(availableForQuery))
        return Array((boundedPrefix + queryLead + boundedQuery + answerLead).prefix(maxTokens))
    }

    func decode(_ ids: [Int]) -> String {
        var bytes: [UInt8] = []
        for id in ids {
            guard let token = tokenStrings[id], !token.hasPrefix("<|") else { continue }
            for scalar in token.unicodeScalars {
                if let byte = unicodeToByte[scalar] { bytes.append(byte) }
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func bpe(_ token: String) -> [String] {
        var symbols = token.unicodeScalars.map(String.init)
        guard symbols.count > 1 else { return symbols }

        while symbols.count > 1 {
            var selectedIndex: Int?
            var selectedRank = Int.max
            for index in 0..<(symbols.count - 1) {
                let pair = symbols[index] + " " + symbols[index + 1]
                if let rank = mergeRanks[pair], rank < selectedRank {
                    selectedRank = rank
                    selectedIndex = index
                }
            }
            guard let index = selectedIndex else { break }
            symbols[index] += symbols[index + 1]
            symbols.remove(at: index + 1)
        }
        return symbols
    }

    private static func byteMaps() -> (forward: [UInt8: UnicodeScalar], reverse: [UnicodeScalar: UInt8]) {
        var visible = Array(UInt8(33)...UInt8(126))
            + Array(UInt8(161)...UInt8(172))
            + Array(UInt8(174)...UInt8(255))
        var codePoints = visible.map(Int.init)
        var extra = 0
        for byte in 0...255 where !visible.contains(UInt8(byte)) {
            visible.append(UInt8(byte))
            codePoints.append(256 + extra)
            extra += 1
        }

        var forward: [UInt8: UnicodeScalar] = [:]
        var reverse: [UnicodeScalar: UInt8] = [:]
        for (byte, codePoint) in zip(visible, codePoints) {
            guard let scalar = UnicodeScalar(codePoint) else { continue }
            forward[byte] = scalar
            reverse[scalar] = byte
        }
        return (forward, reverse)
    }
}
