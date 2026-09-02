//
//  ExecutionPlan.swift
//  Orderly
//
//  ClutterBot Data Model v1 — user's approved subset of a CleanupPlan.
//  Only selectedActionIDs are executed; unselected actions are never run.
//

import Foundation

struct ExecutionPlan: Codable, Hashable, Sendable {
    let cleanupPlanID: UUID
    let selectedActionIDs: [UUID]

    init(cleanupPlanID: UUID, selectedActionIDs: [UUID]) {
        self.cleanupPlanID = cleanupPlanID
        self.selectedActionIDs = selectedActionIDs
    }
}
