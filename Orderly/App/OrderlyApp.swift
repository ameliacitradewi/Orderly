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
                "ORDERLY_PCC_SMOKE"
            ] == "1" {
                PCCSmokeView()
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

private struct PCCSmokeView: View {
    @State private var status: SmokeStatus = .running

    var body: some View {
        VStack(spacing: 14) {
            switch status {
            case .running:
                ProgressView()
                Text("Running PCC Foundation Model smoke test…")
                    .font(.headline)
                Text("Normal Orderly analysis is disabled while this verifies a direct Private Cloud Compute Foundation Model request.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)

            case .passed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                Text("PCC Foundation Model smoke test passed")
                    .font(.headline)
                Text("See the Xcode console for the PCC request and response.")
                    .foregroundStyle(.secondary)

            case .failed(let message):
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 34))
                Text("PCC Foundation Model smoke test failed")
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
                _ = try await PCCSmokeTest.run()
                status = .passed
            } catch {
                print("======== PCC FOUNDATION MODEL SMOKE FAILED ========")
                print(String(reflecting: error))
                print(error.localizedDescription)
                status = .failed(error.localizedDescription)
            }
        }
    }
}
#endif
