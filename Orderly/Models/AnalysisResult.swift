import Foundation

struct AnalysisResult: Codable, Hashable, Sendable {
    let analyzedFolder: URL
    let totalFiles: Int
    let duplicateGroups: [DuplicateGroup]
    let candidates: [AnalysisCandidate]
    let analyzedAt: Date
    let files: [FileMetadata]
}
