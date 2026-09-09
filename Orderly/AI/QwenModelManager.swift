import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

actor QwenModelManager {
    static let shared = QwenModelManager()
    static let modelName = "Qwen3-8B-4bit"

    private var loadingTask: Task<ModelContainer, Error>?
    private var inferenceTail: Task<Void, Never>?

    /// Keeps the successfully loaded container alive and shares the same in-flight
    /// task when more than one request arrives during the initial model load.
    func modelContainer() async throws -> ModelContainer {
        if let loadingTask {
            return try await loadingTask.value
        }

        print("======== LOADING QWEN ========")
        let startedAt = Date()

        let task = Task<ModelContainer, Error> {
            try await #huggingFaceLoadModelContainer(
                configuration: LLMRegistry.qwen3_8b_4bit
            )
        }
        loadingTask = task

        do {
            let container = try await task.value
            let duration = Date().timeIntervalSince(startedAt)
            await LocalModelRuntimeMetrics.shared.recordQwenLoad(
                seconds: duration,
                residentBytes: ResidentMemorySampler.currentBytes()
            )
            print("======== QWEN READY ========")
            print("Model:", Self.modelName)
            return container
        } catch {
            loadingTask = nil
            throw error
        }
    }

    /// MLX model weights are shared, but inference requests are intentionally
    /// serialized. Independent ChatSession instances still get clean transcripts,
    /// while two app tasks cannot drive the same ModelContainer concurrently.
    func generate(prompt: String) async throws -> String {
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
                    maxTokens: 650,
                    temperature: 0
                ),
                additionalContext: ["enable_thinking": false]
            )
            let response = try await session.respond(to: prompt)
            await LocalModelRuntimeMetrics.shared.recordQwenInference(
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
