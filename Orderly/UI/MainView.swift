//
//  MainView.swift
//  Orderly
//

import SwiftUI
import AppKit

struct MainView: View {

    @State private var selectedFolder: URL?
    @State private var files: [FileMetadata] = []

    @State private var isScanning = false
    @State private var isAnalyzing = false
    @State private var analysisResult: AnalysisResult?
    @State private var modelCleanupPlan: ModelCleanupPlan?
    @State private var cleanupPlan: CleanupPlan?
    @State private var isAIAnalyzing = false
    @State private var aiError: String?
    @State private var errorMessage: String?

    private let securityAccess = SecurityScopedAccess()
    private let bookmarkStore = BookmarkStore()
    private let analysisEngine = AnalysisEngine()
    private let modelSession = OrderlyModelSession()
    private let cleanupPlanner = CleanupPlanner()

    var body: some View {

        ZStack {

            OrderlyTheme.background
                .ignoresSafeArea()

            sessionContent
        }
        .frame(
            minWidth: 760,
            minHeight: 560
        )
        .overlay(alignment: .bottom) {

            if let errorMessage {

                OrderlyCard {
                    Label(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(
                        OrderlyTheme.destructive
                    )
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder
    private var sessionContent: some View {

        if let selectedFolder {

            if isScanning {

                ScanningView(
                    folder: selectedFolder,
                    files: files,
                    progress: nil
                )

            } else if isAnalyzing {

                progressView(
                    title: "Analyzing files...",
                    message: "Orderly is identifying file types, duplicates, and cleanup candidates."
                )

            } else if isAIAnalyzing {

                progressView(
                    title: "Building your declutter plan...",
                    message: "The on-device model is reviewing the candidates conservatively."
                )

            } else if let cleanupPlan {

                CleanupPlanView(
                    plan: cleanupPlan,
                    files: files
                )

            } else if let aiError {

                VStack(spacing: 16) {

                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            OrderlyTheme.warning
                        )

                    Text("Orderly couldn't build a plan")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(aiError)
                        .foregroundStyle(
                            OrderlyTheme.secondaryText
                        )
                        .multilineTextAlignment(.center)

                    Button("Choose Another Folder") {
                        chooseFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OrderlyTheme.accent)
                }
                .padding(40)

            } else {

                progressView(
                    title: "Preparing...",
                    message: "Orderly is getting the selected folder ready."
                )
            }

        } else {

            EmptyStateView(
                onSelectFolder: chooseFolder
            )
        }
    }

    private func progressView(
        title: String,
        message: String
    ) -> some View {

        VStack(spacing: 14) {

            ProgressView()
                .controlSize(.small)
                .tint(OrderlyTheme.accent)

            Text(title)
                .font(.headline)

            Text(message)
                .foregroundStyle(
                    OrderlyTheme.secondaryText
                )
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(40)
    }

    private func chooseFolder() {

        let panel = NSOpenPanel()

        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK,
           let url = panel.url {
            selectFolder(url)
        }
    }

    private func selectFolder(_ url: URL) {

        errorMessage = nil
        files = []
        analysisResult = nil
        modelCleanupPlan = nil
        cleanupPlan = nil
        aiError = nil
        isAIAnalyzing = false

        guard securityAccess.startAccessing(url) else {

            errorMessage =
                "Orderly could not access this folder."

            return
        }

        selectedFolder = url

        do {

            try bookmarkStore.saveBookmark(
                for: url
            )

            scanFolder(url)

        } catch {

            errorMessage =
                error.localizedDescription
        }
    }

    private func scanFolder(_ url: URL) {

        isScanning = true
        isAnalyzing = false

        Task {

            do {

                let scannedFiles =
                    try await Task.detached {
                        try await FileSystemService().scanDirectory(
                            at: url
                        )
                    }.value

                await MainActor.run {

                    files = scannedFiles
                    isScanning = false
                    isAnalyzing = true
                }

                let result = await analysisEngine.analyze(
                    folder: url,
                    files: scannedFiles
                )

                print("======== ANALYSIS ========")
                print("Duplicate groups:", result.duplicateGroups.count)
                print("Candidates:", result.candidates.count)

                for candidate in result.candidates {
                    print(
                        "Candidate:",
                        candidate.id,
                        candidate.type.rawValue,
                        candidate.fileIDs.count,
                        candidate.confidence
                    )
                }

                await MainActor.run {

                    analysisResult = result
                    isAnalyzing = false
                    isAIAnalyzing = true
                }

                do {

                    let modelPlan = try await modelSession.analyze(
                        analysis: result
                    )

                    print("======== MODEL PLAN ========")
                    print("Summary:", modelPlan.summary)
                    print("Recommendations:", modelPlan.recommendations.count)

                    for recommendation in modelPlan.recommendations {
                        print(
                            "Recommendation:",
                            recommendation.candidateID,
                            recommendation.intent.rawValue,
                            recommendation.title
                        )
                    }

                    let plan = cleanupPlanner.createPlan(
                        folder: url,
                        files: scannedFiles,
                        analysis: result,
                        modelPlan: modelPlan
                    )

                    print("======== CLEANUP PLAN ========")
                    print("Actions:", plan.actions.count)

                    for action in plan.actions {
                        print(
                            "Action:",
                            action.type.rawValue,
                            action.title,
                            action.fileIDs.count
                        )
                    }

                    await MainActor.run {

                        modelCleanupPlan = modelPlan
                        cleanupPlan = plan
                        isAIAnalyzing = false
                    }

                } catch {

                    await MainActor.run {

                        aiError = error.localizedDescription
                        isAIAnalyzing = false
                    }
                }

            } catch {

                await MainActor.run {

                    errorMessage =
                        error.localizedDescription

                    isScanning = false
                    isAnalyzing = false
                }
            }
        }
    }
}
