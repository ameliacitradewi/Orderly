import Foundation

final class QwenMLXService: LLMService {
    private let modelManager: QwenModelManager

    init(modelManager: QwenModelManager = .shared) {
        self.modelManager = modelManager
    }

    func generate(prompt: String) async throws -> String {
        try await modelManager.generate(prompt: prompt)
    }
}
