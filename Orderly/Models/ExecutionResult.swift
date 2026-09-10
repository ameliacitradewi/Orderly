import Foundation

nonisolated struct ExecutionProgress: Sendable {
    let completedActions: Int
    let totalActions: Int
    let currentMessage: String

    var fraction: Double {
        guard totalActions > 0 else { return 0 }
        return Double(completedActions) / Double(totalActions)
    }
}

nonisolated struct ExecutionResult: Sendable {
    let planID: UUID
    let records: [ExecutionRecord]
    let startedAt: Date
    let finishedAt: Date
    let wasCancelled: Bool

    init(
        planID: UUID,
        records: [ExecutionRecord],
        startedAt: Date,
        finishedAt: Date,
        wasCancelled: Bool = false
    ) {
        self.planID = planID
        self.records = records
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.wasCancelled = wasCancelled
    }

    var succeededCount: Int {
        records.filter { $0.status == .succeeded }.count
    }

    var skippedCount: Int {
        records.filter { $0.status == .skipped }.count
    }

    var failedCount: Int {
        records.filter { $0.status == .failed }.count
    }

    var reclaimedBytes: Int64 {
        records
            .filter {
                $0.status == .succeeded
                    && $0.operation == .trash
            }
            .reduce(0) { $0 + $1.fileSize }
    }

    /// A safely skipped stale item still means the approved plan was not fully applied.
    var isFullySuccessful: Bool {
        !wasCancelled && skippedCount == 0 && failedCount == 0
    }
}

nonisolated struct ExecutionRecord: Identifiable, Sendable {
    let id: UUID
    let actionID: UUID
    let fileID: UUID?
    let operation: CleanupActionType
    let sourceURL: URL?
    let resultingURL: URL?
    let fileSize: Int64
    let status: ExecutionRecordStatus
    let message: String
}

nonisolated enum ExecutionRecordStatus: Sendable {
    case succeeded
    /// No mutation was attempted because current filesystem state could not be
    /// revalidated against the approved cleanup session.
    case skipped
    /// A mutation was attempted (or its destination preparation began) and failed.
    case failed
}
