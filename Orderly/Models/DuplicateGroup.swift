import Foundation

nonisolated struct DuplicateGroup: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let files: [UUID]
    let fileSize: Int64
    let detectionMethod: DuplicateDetectionMethod
    /// Legacy compatibility field. pcc-full stores a PCC content-group marker here instead of SHA256.
    let sha256: String
    /// Preferred retained copy. Image duplicate groups choose the highest pixel resolution; other groups use their configured deterministic keeper rule.
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
