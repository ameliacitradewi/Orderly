import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

/// Shared, serialized loader for the visual specialist. Orderly deliberately keeps
/// this separate from QwenModelManager so the text agent and VLM have independent
/// lifetimes and can be benchmarked/replaced independently.
actor FastVLMModelManager {
    static let shared = FastVLMModelManager()

    /// Use the FastVLM configuration that mlx-swift-lm 3.31.4 supports directly.
    /// We start with the maintained 0.5B BF16 build for the first real-device smoke
    /// test instead of depending on an unpinned third-party 1.5B MLX conversion.
    static let modelName = "FastVLM-0.5B-bf16"

    private var loadingTask: Task<ModelContainer, Error>?
    private var inferenceTail: Task<Void, Never>?

    func modelContainer() async throws -> ModelContainer {
        if let loadingTask {
            return try await loadingTask.value
        }

        print("======== LOADING FASTVLM ========")
        let startedAt = Date()

        let task = Task<ModelContainer, Error> {
            try await VLMModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: VLMRegistry.fastvlm
            )
        }
        loadingTask = task

        do {
            let container = try await task.value
            let duration = Date().timeIntervalSince(startedAt)
            await LocalModelRuntimeMetrics.shared.recordFastVLMLoad(
                seconds: duration,
                residentBytes: ResidentMemorySampler.currentBytes()
            )
            print("======== FASTVLM READY ========")
            print("Model:", Self.modelName)
            return container
        } catch {
            loadingTask = nil
            throw error
        }
    }

    /// ChatSession is intentionally fresh per inspection and requests are serialized.
    /// Image contents are treated as untrusted input by StructuredImageSemanticAnalyzer.
    func generate(prompt: String, imageURL: URL) async throws -> String {
        let predecessor = inferenceTail

        let generation = Task<String, Error> {
            if let predecessor {
                await predecessor.value
            }

            try Task.checkCancellation()
            let model = try await self.modelContainer()
            let startedAt = Date()
            let session = ChatSession(
                model,
                generateParameters: GenerateParameters(
                    maxTokens: 220,
                    temperature: 0
                )
            )
            let response = try await session.respond(
                to: prompt,
                image: .url(imageURL)
            )
            await LocalModelRuntimeMetrics.shared.recordFastVLMInference(
                seconds: Date().timeIntervalSince(startedAt)
            )
            return response
        }

        inferenceTail = Task {
            _ = try? await generation.value
        }

        return try await generation.value
    }
}

/// Concrete adapter used by Orderly's model-agnostic image semantic layer.
final class FastVLMVisionService: VisionLanguageService {
    private let modelManager: FastVLMModelManager

    init(modelManager: FastVLMModelManager = .shared) {
        self.modelManager = modelManager
    }

    func generate(prompt: String, imageURL: URL) async throws -> String {
        try await modelManager.generate(
            prompt: prompt,
            imageURL: imageURL
        )
    }
}
