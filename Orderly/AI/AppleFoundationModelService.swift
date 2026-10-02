import Foundation
import FoundationModels

/// Text-model adapter for Orderly's agentic workflow.
///
/// On macOS 27 and later this routes each request to Apple's Foundation Model
/// running in Private Cloud Compute. A fresh session is used per request because
/// Orderly already carries the relevant agent state in the prompt and doesn't
/// need hidden conversational history between tool-planning turns.
final class AppleFoundationModelService: LLMService {
    static let modelName = "Apple Foundation Model (Private Cloud Compute)"

    private let reasoningLevel: ContextOptions.ReasoningLevel

    init(reasoningLevel: ContextOptions.ReasoningLevel = .moderate) {
        self.reasoningLevel = reasoningLevel
    }

    func generate(prompt: String) async throws -> String {
        try Task.checkCancellation()

        let model = PrivateCloudComputeLanguageModel()
        guard model.isAvailable else {
            throw AppleFoundationModelServiceError.privateCloudComputeUnavailable
        }

        let session = LanguageModelSession(model: model)
        let startedAt = Date()

        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(sampling: .greedy),
            contextOptions: ContextOptions(reasoningLevel: reasoningLevel)
        )

        let content = response.content
        await LocalModelRuntimeMetrics.shared.recordFoundationInference(
            seconds: Date().timeIntervalSince(startedAt),
            purpose: Self.inferencePurpose(for: prompt),
            promptCharacters: prompt.count,
            outputCharacters: content.count
        )

        return content
    }

    private static func inferencePurpose(
        for prompt: String
    ) -> FoundationInferencePurpose {
        if prompt.contains("You are a semantic document comparison component inside Orderly.") {
            return .documentSemantic
        }
        if prompt.contains("You convert visual observations into typed metadata for Orderly.") {
            return .imageStructuring
        }
        if prompt.contains("You classify the relationship between two images for Orderly.") {
            return .imageRelationship
        }
        return .agentDecision
    }
}

enum AppleFoundationModelServiceError: LocalizedError {
    case privateCloudComputeUnavailable

    var errorDescription: String? {
        switch self {
        case .privateCloudComputeUnavailable:
            return "Apple Foundation Models on Private Cloud Compute are unavailable on this Mac right now."
        }
    }
}


/// Multimodal adapter for image understanding on macOS 27.
///
/// This uses the same Apple Foundation Model on Private Cloud Compute as the
/// text agent, but includes the selected image as a Foundation Models
/// `Attachment`. Keeping image understanding in Foundation Models avoids the
/// separate MLX/Metal runtime in Orderly's production path.
final class AppleFoundationVisionService: VisionLanguageService {
    private let reasoningLevel: ContextOptions.ReasoningLevel

    init(reasoningLevel: ContextOptions.ReasoningLevel = .light) {
        self.reasoningLevel = reasoningLevel
    }

    func generate(
        prompt: String,
        imageURL: URL
    ) async throws -> String {
        try Task.checkCancellation()

        let model = PrivateCloudComputeLanguageModel()
        guard model.isAvailable else {
            throw AppleFoundationModelServiceError.privateCloudComputeUnavailable
        }

        let session = LanguageModelSession(model: model)
        let startedAt = Date()

        let response = try await session.respond(
            options: GenerationOptions(sampling: .greedy),
            contextOptions: ContextOptions(reasoningLevel: reasoningLevel)
        ) {
            prompt
            Attachment(imageURL: imageURL)
        }

        let content = response.content
        await LocalModelRuntimeMetrics.shared.recordFoundationInference(
            seconds: Date().timeIntervalSince(startedAt),
            purpose: .imageStructuring,
            promptCharacters: prompt.count,
            outputCharacters: content.count
        )

        return content
    }
}
