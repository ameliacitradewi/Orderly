//
//  FileCategory.swift
//  Orderly
//
//  ClutterBot Data Model v1 — AI-assisted file grouping with confidence and source attribution.
//

import Foundation

enum ClassificationSource: String, Codable, Hashable, Sendable {
    case deterministic
    case foundationModel
    case hybrid
}

struct FileCategory: Identifiable, Codable, Hashable, Sendable {
    let id: UUID

    let name: String

    let fileIDs: [UUID]

    let confidence: Double

    let source: ClassificationSource

    init(
        id: UUID = UUID(),
        name: String,
        fileIDs: [UUID],
        confidence: Double,
        source: ClassificationSource
    ) {
        self.id = id
        self.name = name
        self.fileIDs = fileIDs
        self.confidence = confidence
        self.source = source
    }
}
