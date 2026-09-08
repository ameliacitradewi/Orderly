import Foundation
import MLXLLM
import MLXLMCommon

final class QwenMLXService: LLMService {
    private let modelManager: QwenModelManager

    init(modelManager: QwenModelManager = .shared) {
        self.modelManager = modelManager
    }

    func generate(prompt: String) async throws -> String {
        let model = try await modelManager.modelContainer()

        // Each candidate gets a clean transcript while the model stays in memory.
        let session = ChatSession(
            model,
            generateParameters: GenerateParameters(
                maxTokens: 650,
                temperature: 0
            ),
            additionalContext: ["enable_thinking": false]
        )

        return try await session.respond(to: prompt)
    }
}
