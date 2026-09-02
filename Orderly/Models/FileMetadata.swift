//
//  FileMetadata.swift
//  Orderly
//

import Foundation

struct FileMetadata: Identifiable, Codable, Hashable, Sendable {
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

    var fileType: FileType {
        FileType.from(fileExtension: extensionName)
    }
}
