import Foundation
import FoundationModels

enum PCCSmokeTest {
    static func run() async throws -> String {
        print("======== PCC FOUNDATION MODEL SMOKE START ========")

        let model = PrivateCloudComputeLanguageModel()
        guard model.isAvailable else {
            throw PCCSmokeTestError.privateCloudComputeUnavailable
        }

        let session = LanguageModelSession(model: model)
        let response = try await session.respond(
            to: """
            You are running inside Orderly, a macOS file cleanup application.
            Reply with exactly: PCC_OK
            """,
            options: GenerationOptions(sampling: .greedy),
            contextOptions: ContextOptions(reasoningLevel: .light)
        )

        print("======== PCC FOUNDATION MODEL RESPONSE ========")
        print(response.content)

        return response.content
    }
}

enum PCCSmokeTestError: LocalizedError {
    case privateCloudComputeUnavailable

    var errorDescription: String? {
        "Private Cloud Compute is unavailable on this Mac right now."
    }
}
