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

    func generate(prompt: String) async throws -> String {
        let predecessor = inferenceTail

        let generation = Task<String, Error> {
            if let predecessor {
                await predecessor.value
            }

            try Task.checkCancellation()
            let model = try await self.modelContainer()
            let purpose = Self.inferencePurpose(for: prompt)
            let session = ChatSession(
                model,
                generateParameters: GenerateParameters(
                    maxTokens: Self.maxTokens(for: purpose),
                    temperature: 0
                ),
                additionalContext: ["enable_thinking": false]
            )

            let firstStartedAt = Date()
            var response = try await session.respond(to: prompt)
            await LocalModelRuntimeMetrics.shared.recordQwenInference(
                seconds: Date().timeIntervalSince(firstStartedAt),
                purpose: purpose,
                promptCharacters: prompt.count,
                outputCharacters: response.count
            )

            if Self.expectsJSONObject(prompt),
               !Self.containsValidJSONObject(response) {
                print("======== QWEN STRUCTURED RESPONSE RETRY ========")
                print("Previous JSON response was incomplete or malformed; regenerating once.")

                let retryPrompt = """
                Your previous response was incomplete or invalid JSON.
                Regenerate the complete JSON object requested by the previous instruction.
                Preserve the same intended action and evidence, but keep summary, evidence descriptions, and proposal reasons concise.
                Output one complete JSON object only, with no markdown or commentary.
                """
                let retryStartedAt = Date()
                response = try await session.respond(to: retryPrompt)
                await LocalModelRuntimeMetrics.shared.recordQwenInference(
                    seconds: Date().timeIntervalSince(retryStartedAt),
                    purpose: purpose,
                    promptCharacters: retryPrompt.count,
                    outputCharacters: response.count
                )
            }

            return response
        }

        inferenceTail = Task {
            _ = try? await generation.value
        }

        return try await generation.value
    }

    private static func inferencePurpose(for prompt: String) -> QwenInferencePurpose {
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

    private static func maxTokens(for purpose: QwenInferencePurpose) -> Int {
        switch purpose {
        case .documentSemantic, .imageStructuring, .imageRelationship:
            return 320
        case .agentDecision:
            return 1_200
        }
    }

    private static func expectsJSONObject(_ prompt: String) -> Bool {
        prompt.range(
            of: "return json only",
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    private static func containsValidJSONObject(_ response: String) -> Bool {
        let stripped = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let first = stripped.firstIndex(of: "{"),
              let last = stripped.lastIndex(of: "}"),
              first <= last,
              let data = String(stripped[first...last]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any] else {
            return false
        }
        return true
    }
}
