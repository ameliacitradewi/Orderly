//
//  CleanupPlan.swift
//  Orderly
//
//  ClutterBot Data Model v1 — AI-generated cleanup proposal for user review.
//  Default selection is determined by the Policy Engine (confidence + risk + action type), not AI alone.
//

import Foundation

struct CleanupPlan: Identifiable, Codable, Hashable, Sendable {
    let id: UUID

    let folder: URL

    let summary: String

    let actions: [CleanupAction]

    let createdAt: Date

}
