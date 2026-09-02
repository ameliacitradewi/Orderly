//
//  Operation.swift
//  Orderly
//
//  ClutterBot Data Model v1 — one filesystem mutation recorded for recovery/undo.
//  Inverse mapping: move↔move back, rename↔rename back, trash↔restore
//

import Foundation

enum OperationType: String, Codable, Hashable, Sendable {
    case createFolder
    case move
    case rename
    case trash
    case restore
}

enum OperationStatus: String, Codable, Hashable, Sendable {
    case pending
    case completed
    case failed
    case reversed
}

struct Operation: Identifiable, Codable, Hashable, Sendable {
    let id: UUID

    let actionID: UUID

    let type: OperationType

    let sourceURL: URL
    let destinationURL: URL?

    let timestamp: Date

    let status: OperationStatus

    init(
        id: UUID = UUID(),
        actionID: UUID,
        type: OperationType,
        sourceURL: URL,
        destinationURL: URL? = nil,
        timestamp: Date = .now,
        status: OperationStatus = .pending
    ) {
        self.id = id
        self.actionID = actionID
        self.type = type
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.timestamp = timestamp
        self.status = status
    }
}
