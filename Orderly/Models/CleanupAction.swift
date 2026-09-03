//
//  CleanupAction.swift
//  Orderly
//
//  ClutterBot Data Model v1 — structured cleanup proposal (no permanent delete).
//  Flow: CleanupAction → Validation → User Approval → Execution
//

import Foundation

enum CleanupActionType: String, Codable, Hashable, Sendable {
    case createFolder
    case move
    case rename
    case trash
}

enum RiskLevel: String, Codable, Hashable, Sendable {
    case low
    case medium
    case high
}

struct CleanupAction: Identifiable, Codable, Hashable, Sendable {
    let id: UUID

    let type: CleanupActionType

    let title: String
    let explanation: String

    let fileIDs: [UUID]

    let destination: URL?

    let riskLevel: RiskLevel

    let confidence: Double

    var isSelected: Bool

    var excludedFileIDs: [UUID]

    var selectedFileIDs: [UUID] {
        fileIDs.filter { fileID in
            !excludedFileIDs.contains(fileID)
        }
    }

    init(
        id: UUID = UUID(),
        type: CleanupActionType,
        title: String,
        explanation: String,
        fileIDs: [UUID],
        destination: URL? = nil,
        riskLevel: RiskLevel,
        confidence: Double,
        isSelected: Bool = false,
        excludedFileIDs: [UUID] = []
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.explanation = explanation
        self.fileIDs = fileIDs
        self.destination = destination
        self.riskLevel = riskLevel
        self.confidence = confidence
        self.isSelected = isSelected
        self.excludedFileIDs = excludedFileIDs
    }
}
