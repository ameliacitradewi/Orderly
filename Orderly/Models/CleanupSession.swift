//
//  CleanupSession.swift
//  Orderly
//
//  ClutterBot Data Model v1 — one cleanup session with its own identity and lifecycle.
//

import Foundation

enum CleanupSessionStatus: String, Codable, Hashable, Sendable {
    case idle
    case scanning
    case analyzing
    case planning
    case reviewing
    case executing
    case completed
    case partiallyCompleted
    case failed
    case undone
}

struct CleanupSession: Identifiable, Codable, Hashable, Sendable {
    let id: UUID

    let folder: URL

    let startedAt: Date

    var analysisResult: AnalysisResult?
    var cleanupPlan: CleanupPlan?
    var executionPlan: ExecutionPlan?

    var status: CleanupSessionStatus

    init(
        id: UUID = UUID(),
        folder: URL,
        startedAt: Date = .now,
        analysisResult: AnalysisResult? = nil,
        cleanupPlan: CleanupPlan? = nil,
        executionPlan: ExecutionPlan? = nil,
        status: CleanupSessionStatus = .idle
    ) {
        self.id = id
        self.folder = folder
        self.startedAt = startedAt
        self.analysisResult = analysisResult
        self.cleanupPlan = cleanupPlan
        self.executionPlan = executionPlan
        self.status = status
    }
}
