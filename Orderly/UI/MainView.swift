//
//  MainView.swift
//  Orderly
//

import SwiftUI

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

        VStack(spacing: 24) {

            VStack(spacing: 8) {

                Text("Orderly")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(
                    selectedFolder?.path
                    ?? "Choose a folder to organize"
                )
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            FolderPickerView { folderURL in
                selectFolder(folderURL)
            }

            if isScanning {

                ProgressView("Scanning...")
                    .controlSize(.small)

            } else if isAnalyzing {

                ProgressView("Analyzing files...")
                    .controlSize(.small)

            } else if selectedFolder != nil {

                Text(
                    "\(files.count) files found"
                )
                .font(.headline)
            }

            if let result = analysisResult {

                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {

                    Text("Analysis")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(
                        "\(result.totalFiles) files • " +
                        ByteCountFormatter.string(
                            fromByteCount: result.totalSize,
                            countStyle: .file
                        )
                    )

                    ForEach(result.fileTypes) { summary in

                        HStack {

                            Text(
                                summary.type.rawValue.capitalized
                            )

                            Spacer()

                            Text("\(summary.count)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    Text(
                        "\(result.duplicateGroups.count) duplicate groups"
                    )

                    Text(
                        "\(temporaryFileCount(in: result)) temporary-file candidates"
                    )
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if isAIAnalyzing {

                ProgressView(
                    "Orderly is understanding your files..."
                )
            }

            if let cleanupPlan {

                CleanupPlanView(
                    plan: cleanupPlan,
                    files: files
                )
            }

            if let aiError {

                Text(aiError)
                    .foregroundStyle(.red)
            }

            if !files.isEmpty {

                List(files) { file in

                    HStack {

                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {

                            Text(file.name)
                                .fontWeight(.medium)

                            Text(
                                relativePath(for: file.url)
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(
                            alignment: .trailing,
                            spacing: 4
                        ) {

                            Text(file.fileType.rawValue.capitalized)

                            Text(
                                ByteCountFormatter
                                    .string(
                                        fromByteCount: file.size,
                                        countStyle: .file
                                    )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 300)
            }

            if let errorMessage {

                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Spacer()
        }
        .padding(32)
        .frame(
            minWidth: 700,
            minHeight: 500
        )
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

    private func temporaryFileCount(
        in result: AnalysisResult
    ) -> Int {

        result.candidates
            .filter { $0.type == .temporary }
            .reduce(0) { $0 + $1.fileIDs.count }
    }

    private func relativePath(
        for fileURL: URL
    ) -> String {

        guard let selectedFolder else {
            return fileURL.path
        }

        let folderPath =
            selectedFolder.path

        let filePath =
            fileURL.path

        if filePath.hasPrefix(folderPath) {

            let relative =
                String(
                    filePath.dropFirst(
                        folderPath.count
                    )
                )

            return relative
                .trimmingCharacters(
                    in: CharacterSet(
                        charactersIn: "/"
                    )
                )
        }

        return filePath
    }
}
