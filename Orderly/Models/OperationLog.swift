//
//  OperationLog.swift
//  Orderly
//
//  ClutterBot Data Model v1 — audit trail of all operations in a cleanup session for recovery.
//

import Foundation

struct OperationLog: Identifiable, Codable, Hashable, Sendable {
    let id: UUID

    let sessionID: UUID

    let operations: [Operation]

    let createdAt: Date

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        operations: [Operation],
        createdAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.operations = operations
        self.createdAt = createdAt
    }
}
