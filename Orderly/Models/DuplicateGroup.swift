import Foundation

nonisolated struct DuplicateGroup: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let files: [UUID]
    let marker: String
    let keeperID: UUID?
}

nonisolated struct DuplicateScan: Sendable {
    let files: [FileMetadata]
    let groups: [DuplicateGroup]
}
