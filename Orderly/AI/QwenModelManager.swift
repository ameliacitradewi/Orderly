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

    /// Keeps the successfully loaded container alive and shares the same in-flight
    /// task when more than one request arrives during the initial model load.
    func modelContainer() async throws -> ModelContainer {
        if let loadingTask {
            return try await loadingTask.value
        }

        print("======== LOADING QWEN ========")

        let task = Task<ModelContainer, Error> {
            try await #huggingFaceLoadModelContainer(
                configuration: LLMRegistry.qwen3_8b_4bit
            )
        }
        loadingTask = task

        do {
            let container = try await task.value
            print("======== QWEN READY ========")
            print("Model:", Self.modelName)
            return container
        } catch {
            loadingTask = nil
            throw error
        }
    }
}
