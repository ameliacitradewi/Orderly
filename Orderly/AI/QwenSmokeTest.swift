//
//  QwenSmokeTest.swift
//  Orderly
//
//  Created by Amelia Citra on 08/09/26.
//

import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

enum QwenSmokeTest {

    static func run() async throws -> String {

        print("======== QWEN LOAD START ========")

        let model = try await #huggingFaceLoadModelContainer(
            configuration: LLMRegistry.qwen3_8b_4bit
        )

        print("======== QWEN MODEL LOADED ========")

        let session = ChatSession(model)

        let response = try await session.respond(
            to: """
            You are running inside Orderly, a macOS file cleanup application.
            Reply with exactly: QWEN_OK
            """
        )

        print("======== QWEN RESPONSE ========")
        print(response)

        return response
    }
}
