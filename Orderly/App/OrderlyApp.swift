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
            MainView()
#if DEBUG
                .task {
                    await runRequestedDebugSmokeTest()
                }
#endif
        }
    }

#if DEBUG
    @MainActor
    private func runRequestedDebugSmokeTest() async {
        guard ProcessInfo.processInfo.environment[
            "ORDERLY_QWEN_DOCUMENT_SMOKE"
        ] == "1" else {
            return
        }

        do {
            try await QwenSmokeTest.runDocumentComparison()
        } catch {
            print("======== REAL QWEN DOCUMENT SMOKE FAILED ========")
            print(String(reflecting: error))
            print(error.localizedDescription)
        }
    }
#endif
}
