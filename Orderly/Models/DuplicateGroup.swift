import Foundation

nonisolated struct DuplicateGroup: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let files: [UUID]
    let fileSize: Int64
    let detectionMethod: DuplicateDetectionMethod
    /// Legacy compatibility field. pcc-full stores a PCC content-group marker here instead of SHA256.
    let sha256: String
    /// Nil when any modification date is unavailable; never guess which copy is newest.
    let keeperID: UUID?
}

nonisolated enum DuplicateDetectionMethod: String, Codable, Hashable, Sendable {
    case exactHash
    case byteComparison
    case pccContent
    case pccVisualContent
}

nonisolated struct DuplicateScan: Sendable {
    let files: [FileMetadata]
    let groups: [DuplicateGroup]
    let unreadableCount: Int
}
