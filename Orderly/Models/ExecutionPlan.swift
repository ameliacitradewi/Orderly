//
//  ExecutionPlan.swift
//  Orderly
//
//  User-approved operations derived from a CleanupPlan.
//

import Foundation

struct ExecutionPlan: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let cleanupPlanID: UUID
    let selectedActions: [ExecutionAction]

    let createdAt: Date

    init(
        id: UUID = UUID(),
        cleanupPlanID: UUID,
        selectedActions: [ExecutionAction],
        createdAt: Date = .now
    ) {
        self.id = id
        self.cleanupPlanID = cleanupPlanID
        self.selectedActions = selectedActions
        self.createdAt = createdAt
    }
}

struct ExecutionAction: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let sourceActionID: UUID
    let type: CleanupActionType
    let fileIDs: [UUID]
    let destination: URL?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        sourceActionID: UUID,
        type: CleanupActionType,
        fileIDs: [UUID],
        destination: URL?,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sourceActionID = sourceActionID
        self.type = type
        self.fileIDs = fileIDs
        self.destination = destination
        self.createdAt = createdAt
    }
}
