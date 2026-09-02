//
//  FileTypeSummary.swift
//  Orderly
//

import Foundation

struct FileTypeSummary: Codable, Identifiable, Hashable, Sendable {
    var id: String {
        type.rawValue
    }

    let type: FileType
    let count: Int
    let totalSize: Int64
}
