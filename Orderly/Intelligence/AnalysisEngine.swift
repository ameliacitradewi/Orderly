//
//  AnalysisEngine.swift
//  Orderly
//

import Foundation

final class AnalysisEngine {

    private let classifier = FileClassifier()
    private let duplicateDetector = DuplicateDetector()
    private let clutterAnalyzer = ClutterAnalyzer()

    func analyze(
        folder: URL,
        files: [FileMetadata]
    ) async -> AnalysisResult {

        let totalSize = files.reduce(
            Int64(0)
        ) {
            $0 + $1.size
        }

        let fileTypes = classifier.summarize(
            files: files
        )

        let duplicateGroups =
            await duplicateDetector.findDuplicates(
                in: files
            )

        let candidates =
            clutterAnalyzer.analyze(
                files: files,
                duplicateGroups: duplicateGroups
            )

        return AnalysisResult(
            analyzedFolder: folder,
            totalFiles: files.count,
            totalSize: totalSize,
            fileTypes: fileTypes,
            duplicateGroups: duplicateGroups,
            candidates: candidates,
            analyzedAt: Date()
        )
    }
}
