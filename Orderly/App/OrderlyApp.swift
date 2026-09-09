//
//  OrderlyApp.swift
//  Orderly
//

import Foundation
import SwiftUI

@main
struct OrderlyApp: App {

    var body: some Scene {

        WindowGroup {
#if DEBUG
            if ProcessInfo.processInfo.environment[
                "ORDERLY_MIXED_MODALITY_BENCHMARK"
            ] == "1" {
                MixedModalityBenchmarkView()
            } else if ProcessInfo.processInfo.environment[
                "ORDERLY_QWEN_IMAGE_AGENT_SMOKE"
            ] == "1" {
                HybridImageAgentSmokeView()
            } else if ProcessInfo.processInfo.environment[
                "ORDERLY_FASTVLM_IMAGE_SMOKE"
            ] == "1" {
                FastVLMImageSmokeView()
            } else if ProcessInfo.processInfo.environment[
                "ORDERLY_QWEN_DOCUMENT_SMOKE"
            ] == "1" {
                QwenDocumentSmokeView()
            } else {
                MainView()
            }
#else
            MainView()
#endif
        }
    }
}

#if DEBUG
private enum SmokeStatus {
    case running
    case passed
    case failed(String)
}

private struct MixedModalityBenchmarkView: View {
    @State private var status: SmokeStatus = .running

    var body: some View {
        VStack(spacing: 14) {
            switch status {
            case .running:
                ProgressView()
                Text("Running mixed-modality Orderly benchmark…")
                    .font(.headline)
                Text("Normal UI and cleanup execution are disabled. The benchmark runs exact-duplicate, PDF-revision, and image-variant candidates while measuring local model latency and resident memory.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)

            case .passed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                Text("Mixed-modality benchmark passed")
                    .font(.headline)
                Text("See the Xcode console for quality, model-runtime, and resident-memory reports.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)

            case .failed(let message):
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 34))
                Text("Mixed-modality benchmark failed")
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }
        }
        .padding(40)
        .frame(minWidth: 700, minHeight: 440)
        .task {
            do {
                try await MixedModalityBenchmarkSmoke.run()
                status = .passed
            } catch {
                print("======== MIXED MODALITY BENCHMARK FAILED ========")
                print(String(reflecting: error))
                print(error.localizedDescription)
                status = .failed(error.localizedDescription)
            }
        }
    }
}

private struct HybridImageAgentSmokeView: View {
    @State private var status: SmokeStatus = .running

    var body: some View {
        VStack(spacing: 14) {
            switch status {
            case .running:
                ProgressView()
                Text("Running real hybrid image-agent smoke test…")
                    .font(.headline)
                Text("Normal Orderly analysis is disabled. Qwen will orchestrate bounded image tools using Apple Vision, FastVLM, and structured semantic comparison.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)

            case .passed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                Text("Real hybrid image-agent smoke test passed")
                    .font(.headline)
                Text("See the Xcode console for the full agent/tool trace.")
                    .foregroundStyle(.secondary)

            case .failed(let message):
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 34))
                Text("Real hybrid image-agent smoke test failed")
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
        }
        .padding(40)
        .frame(minWidth: 680, minHeight: 420)
        .task {
            do {
                try await ImageAgentSmokeTest.run()
                status = .passed
            } catch {
                print("======== REAL HYBRID IMAGE AGENT SMOKE FAILED ========")
                print(String(reflecting: error))
                print(error.localizedDescription)
                status = .failed(error.localizedDescription)
            }
        }
    }
}

private struct FastVLMImageSmokeView: View {
    @State private var status: SmokeStatus = .running

    var body: some View {
        VStack(spacing: 14) {
            switch status {
            case .running:
                ProgressView()
                Text("Running real FastVLM image smoke test…")
                    .font(.headline)
                Text("Normal Orderly analysis is disabled for this debug run. FastVLM will inspect one generated screenshot-like image using the local MLX VLM runtime.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)

            case .passed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                Text("Real FastVLM image smoke test passed")
                    .font(.headline)
                Text("See the Xcode console for deterministic image evidence and the structured visual observation.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)

            case .failed(let message):
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 34))
                Text("Real FastVLM image smoke test failed")
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
        }
        .padding(40)
        .frame(minWidth: 680, minHeight: 420)
        .task {
            do {
                try await FastVLMSmokeTest.runImageSemanticInspection()
                status = .passed
            } catch {
                print("======== REAL FASTVLM IMAGE SMOKE FAILED ========")
                print(String(reflecting: error))
                print(error.localizedDescription)
                status = .failed(error.localizedDescription)
            }
        }
    }
}

private struct QwenDocumentSmokeView: View {
    @State private var status: SmokeStatus = .running

    var body: some View {
        VStack(spacing: 14) {
            switch status {
            case .running:
                ProgressView()
                Text("Running real Qwen document smoke test…")
                    .font(.headline)
                Text("Normal Orderly analysis is disabled for this debug run so the on-device model is exercised by only one agent at a time.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)

            case .passed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                Text("Real Qwen document smoke test passed")
                    .font(.headline)
                Text("See the Xcode console for the full agent trace.")
                    .foregroundStyle(.secondary)

            case .failed(let message):
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 34))
                Text("Real Qwen document smoke test failed")
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
        }
        .padding(40)
        .frame(minWidth: 680, minHeight: 420)
        .task {
            do {
                try await QwenSmokeTest.runDocumentComparison()
                status = .passed
            } catch {
                print("======== REAL QWEN DOCUMENT SMOKE FAILED ========")
                print(String(reflecting: error))
                print(error.localizedDescription)
                status = .failed(error.localizedDescription)
            }
        }
    }
}
#endif
