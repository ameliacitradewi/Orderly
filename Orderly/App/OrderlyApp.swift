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
private struct QwenDocumentSmokeView: View {
    private enum Status {
        case running
        case passed
        case failed(String)
    }

    @State private var status: Status = .running

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
