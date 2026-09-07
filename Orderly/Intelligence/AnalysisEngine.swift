import Foundation

@MainActor
final class AnalysisEngine {
    private let classifier = FileClassifier()
    private let duplicateDetector = DuplicateDetector()
    private let clutterAnalyzer = ClutterAnalyzer()

    func analyze(folder: URL, files: [FileMetadata]) async throws -> AnalysisResult {
        // Each stage is awaited. Classification sessions leave scope before byte hashing.
        let classified = try await classifier.classify(files: files)
        let duplicates = try await duplicateDetector.findDuplicates(in: classified)
        let candidates = clutterAnalyzer.analyze(files: duplicates.files, duplicateGroups: duplicates.groups)
        return AnalysisResult(
            analyzedFolder: folder, totalFiles: files.count,
            totalSize: files.reduce(0) { $0 + $1.size },
            fileTypes: classifier.summarize(files: duplicates.files),
            duplicateGroups: duplicates.groups, candidates: candidates, analyzedAt: Date(),
            files: duplicates.files, unreadableHashCount: duplicates.unreadableCount
        )
    }
}
