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
    @State private var scanTask: Task<Void, Never>?
    @State private var isAnalyzing = false
    @State private var analysisResult: AnalysisResult?
    @State private var modelCleanupPlan: ModelCleanupPlan?
    @State private var cleanupPlan: CleanupPlan?
    @State private var isAIAnalyzing = false
    @State private var isExecuting = false
    @State private var executionProgress =
        ExecutionProgress(
            completedActions: 0,
            totalActions: 0,
            currentMessage: ""
        )
    @State private var executionResult:
        ExecutionResult?
    @State private var aiError: String?
    @State private var errorMessage: String?

    private let securityAccess = SecurityScopedAccess()
    private let bookmarkStore = BookmarkStore()
    private let analysisEngine = AnalysisEngine()
    private let evidenceEngine = EvidenceEngine()
    private let agent = OrderlyAgent(
        llm: QwenMLXService(),
        visionLanguageService: FastVLMVisionService()
    )
    private let agentPlanAdapter = AgentPlanAdapter()
    private let cleanupPlanner = CleanupPlanner()
    private let executionEngine = ExecutionEngine()

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
                    message: "Orderly is tagging extensions and checking files for SHA256 duplicates."
                )

            } else if isAIAnalyzing {

                progressView(
                    title: "Building your declutter plan...",
                    message: "The on-device model is preparing Delete and Organize recommendations."
                )

            } else if isExecuting {

                ExecutionProgressView(
                    progress: executionProgress
                )

            } else if let executionResult {

                CompletionView(
                    result: executionResult,
                    onChooseAnotherFolder: {
                        resetSession()
                    }
                )

            } else if let cleanupPlan {

                CleanupPlanView(
                    plan: cleanupPlan,
                    files: files,
                    onExecute: { executionPlan in
                        executePlan(
                            executionPlan
                        )
                    }
                )
                .onAppear {
                    print("======== CLEANUP PLAN VIEW APPEARED ========")
                }

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

        resetSession()

        do {

            try bookmarkStore.saveBookmark(
                for: url
            )

            selectedFolder = url

            scanFolder(url)

        } catch {

            errorMessage =
                error.localizedDescription
        }
    }

    private func scanFolder(_ url: URL) {

        isScanning = true
        isAnalyzing = false

        scanTask?.cancel()
        scanTask = Task {

            guard securityAccess.startAccessing(
                url
            ) else {

                await MainActor.run {

                    aiError = "Orderly could not access this folder."

                    isScanning = false
                    isAnalyzing = false
                }

                return
            }

            defer {
                securityAccess.stopAccessing(
                    url
                )
            }

            do {

                let scannedFiles = try await FileSystemService().scanDirectory(at: url)
                try Task.checkCancellation()

                await MainActor.run {

                    files = scannedFiles
                    isScanning = false
                    isAnalyzing = true
                }

                let result = try await analysisEngine.analyze(
                    folder: url,
                    files: scannedFiles
                )

                try Task.checkCancellation()
                files = result.files

                let evidence = evidenceEngine.buildEvidence(
                    candidates: result.candidates,
                    files: result.files,
                    duplicateGroups: result.duplicateGroups,
                    rootFolder: url
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

                    let agentState = try await agent.run(
                        analysis: result,
                        evidence: evidence
                    )
                    let modelPlan = agentPlanAdapter.makeModelPlan(
                        state: agentState,
                        analysis: result
                    )

                    print("======== MODEL PLAN ========")
                    print("Summary:", modelPlan.summary)
                    print("Recommendations:", modelPlan.recommendations.count)

                    for recommendation in modelPlan.recommendations {
                        print(
                            "Recommendation:",
                            recommendation.candidateID,
                            recommendation.title
                        )

                        for decision in recommendation.fileDecisions {
                            print(
                                "   ",
                                decision.fileReference,
                                "→",
                                decision.disposition.rawValue,
                                "|",
                                decision.reason
                            )
                        }
                    }

                    try Task.checkCancellation()
                    let plan = cleanupPlanner.createPlan(
                        folder: url,
                        files: result.files,
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

                } catch is CancellationError {
                    return
                } catch {
                    print("======== AGENT PLANNING FAILED ========")
                    print(String(reflecting: error))
                    print(error.localizedDescription)

                    await MainActor.run {

                        aiError = error.localizedDescription
                        isAIAnalyzing = false
                    }
                }

            } catch is CancellationError {
                return
            } catch {

                await MainActor.run {

                    aiError = error.localizedDescription

                    isScanning = false
                    isAnalyzing = false
                }
            }
        }
    }

    private func executePlan(
        _ plan: ExecutionPlan
    ) {

        guard let folder = selectedFolder else {
            return
        }

        isExecuting = true
        executionResult = nil
        errorMessage = nil

        executionProgress = ExecutionProgress(
            completedActions: 0,
            totalActions: plan.selectedActions.count,
            currentMessage: "Preparing execution..."
        )

        Task {

            do {

                let result =
                    try await executionEngine.execute(
                        plan: plan,
                        files: files,
                        rootFolder: folder
                    ) { progress in

                        await MainActor.run {
                            executionProgress = progress
                        }
                    }

                await MainActor.run {

                    executionResult = result
                    isExecuting = false
                }

            } catch {

                await MainActor.run {

                    errorMessage =
                        error.localizedDescription

                    isExecuting = false
                }
            }
        }
    }

    private func resetSession() {

        scanTask?.cancel()
        scanTask = nil
        selectedFolder = nil
        files = []

        analysisResult = nil
        modelCleanupPlan = nil
        cleanupPlan = nil

        executionResult = nil
        executionProgress = ExecutionProgress(
            completedActions: 0,
            totalActions: 0,
            currentMessage: ""
        )

        isScanning = false
        isAnalyzing = false
        isAIAnalyzing = false
        isExecuting = false

        aiError = nil
        errorMessage = nil
    }
}
