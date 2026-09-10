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
            let session = ChatSession(
                model,
                generateParameters: GenerateParameters(
                    // Agent finish responses can legitimately contain several file
                    // proposals, so keep the larger ceiling there. Internal semantic
                    // classifiers have tiny fixed schemas and use a smaller bound to
                    // prevent accidental long generations.
                    maxTokens: Self.maxTokens(for: prompt),
                    temperature: 0
                ),
                additionalContext: ["enable_thinking": false]
            )

            let firstStartedAt = Date()
            var response = try await session.respond(to: prompt)
            await LocalModelRuntimeMetrics.shared.recordQwenInference(
                seconds: Date().timeIntervalSince(firstStartedAt),
                promptCharacters: prompt.count,
                outputCharacters: response.count
            )

            // Structured agent/tool prompts are allowed one bounded regeneration when
            // the model returns malformed or truncated JSON. The same ChatSession keeps
            // the original instruction and prior response in context, so the retry does
            // not need to copy untrusted observations into a new prompt. If the second
            // response is still invalid, downstream typed decoders reject it normally.
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

    private static func maxTokens(for prompt: String) -> Int {
        let compactSemanticMarkers = [
            "You are a semantic document comparison component inside Orderly.",
            "You convert visual observations into typed metadata for Orderly.",
            "You classify the relationship between two images for Orderly."
        ]
        if compactSemanticMarkers.contains(where: { prompt.contains($0) }) {
            return 320
        }

        // Four-file finishCandidate responses were previously observed truncating at
        // 650 tokens. Preserve the safe larger ceiling for the general agent loop.
        return 1_200
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
