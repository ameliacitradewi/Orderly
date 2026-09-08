import Foundation

nonisolated struct FileMetadata: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    let extensionName: String
    let size: Int64
    let createdAt: Date?
    let modifiedAt: Date?
    let accessedAt: Date?
    let isDirectory: Bool
    let isHidden: Bool
    let uti: String?

    var classification: FileType? = nil
    var duplicateGroupID: UUID? = nil
    var duplicateSHA256: String? = nil
    var duplicateKeeperID: UUID? = nil
    var duplicateCopyCount: Int = 0

    var fileType: FileType {
        classification ?? ExtensionCatalog.category(for: ExtensionCatalog.key(for: name)) ?? .other
    }

    var tags: [String] {
        [fileType.tagName] + (duplicateGroupID == nil ? [] : ["SHA256 Duplicate"])
    }
}
