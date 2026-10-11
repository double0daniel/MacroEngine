import Combine
import CoreML
import Foundation

private struct SmolLMLoadedAssets: @unchecked Sendable {
    let model: MLModel
    let tokenizer: SmolLMTokenizer
}

private struct QwenGeneratedResponse: Sendable {
    let text: String
    let tokenCount: Int
}

private final class SmolLMInferenceRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<QwenGeneratedResponse?, Never>?
    private var inferenceTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var finished = false

    func install(_ continuation: CheckedContinuation<QwenGeneratedResponse?, Never>) {
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

    func installTimeout(_ timeoutTask: Task<Void, Never>) {
        lock.lock()
        if finished {
            lock.unlock()
            timeoutTask.cancel()
        } else {
            self.timeoutTask = timeoutTask
            lock.unlock()
        }
    }

    func finish(_ value: QwenGeneratedResponse?) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        let timeoutTask = self.timeoutTask
        self.continuation = nil
        self.timeoutTask = nil
        inferenceTask = nil
        lock.unlock()
        timeoutTask?.cancel()
        continuation?.resume(returning: value)
    }

    func timeout() {
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
        timeoutTask = nil
        lock.unlock()
        inferenceTask?.cancel()
        continuation?.resume(returning: nil)
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
        let timeoutTask = self.timeoutTask
        self.continuation = nil
        self.inferenceTask = nil
        self.timeoutTask = nil
        lock.unlock()
        inferenceTask?.cancel()
        timeoutTask?.cancel()
        continuation?.resume(returning: nil)
    }
}

private enum SmolLMModelRunner {
    private static let maximumContextTokens = 128
    private static let maximumGenerationTokens = 25
    private static let maximumGenerationDuration = 6.0

    static func generate(prompt: String, model: MLModel, tokenizer: SmolLMTokenizer) throws -> QwenGeneratedResponse? {
        guard #available(iOS 18.0, *) else { return nil }
        let inputTokens = tokenizer.encodePrompt(
            prompt,
            maxTokens: maximumContextTokens - maximumGenerationTokens
        )
        guard !inputTokens.isEmpty else { return nil }

        // Each request gets a fresh KV cache so prior questions cannot affect it.
        let state = model.makeState()
        var nextInputTokens = inputTokens
        var pastTokenCount = 0
        var generated: [Int] = []
        let generationStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<maximumGenerationTokens {
            guard !Task.isCancelled else { return nil }
            guard ProcessInfo.processInfo.systemUptime - generationStart < maximumGenerationDuration else { break }
            guard pastTokenCount + nextInputTokens.count <= maximumContextTokens else { break }
            let ids = try tokenArray(nextInputTokens)
            let mask = try causalMask(
                pastTokenCount: pastTokenCount,
                inputTokenCount: nextInputTokens.count
            )

            let provider = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": ids,
                "causal_mask": mask
            ])
            let output: MLFeatureProvider
            do {
                output = try model.prediction(from: provider, using: state)
            } catch {
                print("MacroEngine Core ML prediction failed: \(error)")
                return nil
            }
            guard !Task.isCancelled else { return nil }
            guard ProcessInfo.processInfo.systemUptime - generationStart < maximumGenerationDuration else { break }
            guard let logits = output.featureValue(for: "logits")?.multiArrayValue else { return nil }

            let position = nextInputTokens.count - 1
            let nextToken = greedyToken(logits, position: position)
            if nextToken == 151_645 || nextToken == 151_643
                || nextToken == tokenizer.endOfTextID || nextToken == tokenizer.endOfTurnID { break }
            generated.append(nextToken)

            if generated.count >= 5, endsFirstSentence(tokenizer.decode(generated)) { break }
            pastTokenCount += nextInputTokens.count
            nextInputTokens = [nextToken]
        }

        guard generated.count >= 3 else {
            return QwenGeneratedResponse(text: "", tokenCount: generated.count)
        }
        let answer = firstSentence(tokenizer.decode(generated))
        guard !answer.isEmpty, answer.count <= 600 else {
            return QwenGeneratedResponse(text: "", tokenCount: generated.count)
        }
        return QwenGeneratedResponse(text: answer, tokenCount: generated.count)
    }

    private static func tokenArray(_ tokens: [Int]) throws -> MLMultiArray {
        let array = try MLMultiArray(
            shape: [NSNumber(value: 1), NSNumber(value: tokens.count)],
            dataType: .int32
        )
        for (index, token) in tokens.enumerated() {
            array[[NSNumber(value: 0), NSNumber(value: index)]] = NSNumber(value: token)
        }
        return array
    }

    private static func causalMask(pastTokenCount: Int, inputTokenCount: Int) throws -> MLMultiArray {
        let totalTokenCount = pastTokenCount + inputTokenCount
        let mask = try MLMultiArray(
            shape: [
                NSNumber(value: 1), NSNumber(value: 1),
                NSNumber(value: inputTokenCount), NSNumber(value: totalTokenCount)
            ],
            dataType: .float16
        )
        for queryIndex in 0..<inputTokenCount {
            for keyIndex in 0..<totalTokenCount {
                let isFutureToken = keyIndex > pastTokenCount + queryIndex
                let value = isFutureToken ? -65_504.0 : 0.0
                mask[[NSNumber(value: 0), NSNumber(value: 0), NSNumber(value: queryIndex), NSNumber(value: keyIndex)]] = NSNumber(value: value)
            }
        }
        return mask
    }

    private static func greedyToken(_ logits: MLMultiArray, position: Int) -> Int {
        let vocabularySize = logits.shape.last?.intValue ?? 0
        guard vocabularySize > 0 else { return 0 }
        var bestToken = 0
        var bestLogit = -Double.infinity
        for token in 0..<vocabularySize {
            let value = logits[[NSNumber(value: 0), NSNumber(value: position), NSNumber(value: token)]].doubleValue
            if value.isFinite, value > bestLogit {
                bestLogit = value
                bestToken = token
            }
        }
        return bestToken
    }

    private static func endsFirstSentence(_ text: String) -> Bool {
        text.contains("\n") || text.contains(where: { ".!?".contains($0) })
    }

    private static func firstSentence(_ text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        let end = cleaned.firstIndex(where: { ".!?\n".contains($0) })
        let sentence = end.map { String(cleaned[...$0]) } ?? cleaned
        let result = sentence.replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }
        return ".!?".contains(result.last ?? " ") ? result : result + "."
    }
}

/// On-device runner for the bundled Qwen 2.5 0.5B Core ML model.
/// The model and tokenizer are loaded off the main thread. Calls wait for an
/// in-progress model load before attempting inference.
@MainActor
final class SmolLMInferenceService: ObservableObject {
    static let shared = SmolLMInferenceService()

    @Published private(set) var isModelLoaded = false
    @Published private(set) var isModelUnavailable = false

    private var assets: SmolLMLoadedAssets?
    private var loadingTask: Task<SmolLMLoadedAssets?, Never>?

    private init() {}

    /// Lazily loads assets for the first query and runs greedy prediction away from the main thread.
    /// The Qwen graph accepts sequences up to 2,048 tokens; this service caps
    /// each prompt plus response at 128 tokens.
    func generateResponse(
        prompt: String,
        remainingCalories: Int,
        remainingProtein: Int,
        userQuery: String
    ) async -> String {
        let fallback = telemetryFallback(
            remainingCalories: remainingCalories,
            remainingProtein: remainingProtein
        )
        let race = SmolLMInferenceRace()
        let result: QwenGeneratedResponse? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                race.install(continuation)
                let inferenceTask = Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self, let loadedAssets = await self.loadAssetsIfNeeded() else {
                        race.finish(nil)
                        return
                    }
                    guard !Task.isCancelled else { return }
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
                let timeoutTask = Task.detached(priority: .userInitiated) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    race.timeout()
                }
                race.installTimeout(timeoutTask)
            }
        } onCancel: {
            // Return to the UI immediately, then stop the detached decode after
            // any currently executing Core ML prediction pass completes.
            race.cancel()
        }
        guard let result else { return fallback }
        let response = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.tokenCount >= 3, !response.isEmpty else {
            print("Qwen produced empty generation")
            return queryAwareFallback(for: userQuery)
        }
        return response
    }

    private func telemetryFallback(remainingCalories: Int, remainingProtein: Int) -> String {
        let calories = remainingCalories > 0 ? "\(remainingCalories) kcal" : "calories"
        let protein = remainingProtein > 0 ? "\(remainingProtein)g protein" : "protein"
        return "You have \(calories) and \(protein) left today. Start with a protein-rich meal like chicken breast, eggs, or Greek yogurt!"
    }

    private func queryAwareFallback(for userQuery: String) -> String {
        let query = userQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return "Let's keep it simple: choose chicken, eggs, or Greek yogurt for a protein-rich option today."
        }
        let shortQuery = String(query.prefix(72)).trimmingCharacters(in: .whitespacesAndNewlines)
        return "For ‘\(shortQuery)’, try a protein-rich option like chicken, eggs, or Greek yogurt."
    }

    private func loadAssetsIfNeeded() async -> SmolLMLoadedAssets? {
        if let assets { return assets }
        if let loadingTask { return await loadingTask.value }

        let task = Task.detached(priority: .userInitiated) { () -> SmolLMLoadedAssets? in
            guard
                let modelURL = Bundle.main.url(
                    forResource: "Qwen2.5-0.5B-Instruct-4bit",
                    withExtension: "mlmodelc",
                    subdirectory: "Models/qwen_0_5b"
                ) ?? Bundle.main.url(forResource: "Qwen2.5-0.5B-Instruct-4bit", withExtension: "mlmodelc"),
                let tokenizerURL = Bundle.main.url(
                    forResource: "tokenizer",
                    withExtension: "json",
                    subdirectory: "Models/qwen_0_5b"
                ) ?? Bundle.main.url(forResource: "tokenizer", withExtension: "json"),
                let tokenizer = try? SmolLMTokenizer(contentsOf: tokenizerURL)
            else { return nil }

            do {
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .all
                let model = try MLModel(contentsOf: modelURL, configuration: configuration)
                return SmolLMLoadedAssets(model: model, tokenizer: tokenizer)
            } catch {
                print("MacroEngine could not load the Qwen Core ML model: \(error)")
                return nil
            }
        }
        loadingTask = task
        let loaded = await task.value
        loadingTask = nil
        assets = loaded
        isModelLoaded = loaded != nil
        isModelUnavailable = loaded == nil
        return loaded
    }

}

/// Minimal Hugging Face byte-level BPE tokenizer for the bundled Qwen vocabulary.
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
    private let specialTokenIDs: [String: Int]
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
        specialTokenIDs = specials.merging([
            "<|im_start|>": 151_644,
            "<|im_end|>": 151_645,
            "<|endoftext|>": 151_643
        ]) { configured, _ in configured }
        endOfTextID = specials["<|endoftext|>"] ?? 151_643
        endOfTurnID = specials["<|im_end|>"] ?? 151_645
    }

    func encode(_ text: String) -> [Int] {
        let specialTokens = specialTokenIDs.keys.sorted { $0.count > $1.count }
        var result: [Int] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            var nextMatch: (range: Range<String.Index>, token: String)?
            for specialToken in specialTokens {
                guard let range = text.range(of: specialToken, range: cursor..<text.endIndex) else { continue }
                if nextMatch == nil || range.lowerBound < nextMatch!.range.lowerBound {
                    nextMatch = (range, specialToken)
                }
            }

            guard let nextMatch else {
                result.append(contentsOf: encodeOrdinary(String(text[cursor...])))
                break
            }

            if cursor < nextMatch.range.lowerBound {
                result.append(contentsOf: encodeOrdinary(String(text[cursor..<nextMatch.range.lowerBound])))
            }
            if let tokenID = specialTokenIDs[nextMatch.token] {
                result.append(tokenID)
            }
            cursor = nextMatch.range.upperBound
        }
        return result
    }

    private func encodeOrdinary(_ text: String) -> [Int] {
        let pattern = #"(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}{1,3}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+"#
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
            let userMarker = prompt.range(of: "<|im_start|>user\n"),
            let assistantMarker = prompt.range(of: "<|im_end|>\n<|im_start|>assistant\n", range: userMarker.upperBound..<prompt.endIndex)
        else { return Array(encode(prompt).prefix(maxTokens)) }

        let systemTokens = encode(String(prompt[..<userMarker.lowerBound]))
        let userHeaderTokens = encode(String(prompt[userMarker.lowerBound..<userMarker.upperBound]))
        let userContentTokens = encode(String(prompt[userMarker.upperBound..<assistantMarker.lowerBound]))
        let assistantHeaderTokens = encode(String(prompt[assistantMarker.lowerBound...]))
        let contentBudget = max(0, maxTokens - systemTokens.count - userHeaderTokens.count - assistantHeaderTokens.count)

        return systemTokens
            + userHeaderTokens
            + Array(userContentTokens.prefix(contentBudget))
            + assistantHeaderTokens
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
