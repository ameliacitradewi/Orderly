//
//  DuplicateGroup.swift
//  Orderly
//

import Foundation

struct DuplicateGroup: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let files: [UUID]
    let fileSize: Int64
    let detectionMethod: DuplicateDetectionMethod
}

enum DuplicateDetectionMethod: String, Codable, Hashable, Sendable {
    case exactHash
    case byteComparison
}
