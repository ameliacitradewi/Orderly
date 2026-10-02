import Foundation
import FoundationModels

enum PCCSmokeTest {
    static func run() async throws -> String {
        print("======== PCC FOUNDATION MODEL SMOKE START ========")

        let response = try await AppleFoundationModelService(
            reasoningLevel: .light
        ).generate(
            prompt: """
            You are running inside Orderly, a macOS file cleanup application.
            Reply with exactly: PCC_OK
            """
        )

        print("======== PCC FOUNDATION MODEL RESPONSE ========")
        print(response)

        return response
    }
}
