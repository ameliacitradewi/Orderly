import Foundation

struct ExecutionProgress: Sendable {

    let completedActions: Int
    let totalActions: Int
    let currentMessage: String

    var fraction: Double {

        guard totalActions > 0 else {
            return 0
        }

        return Double(completedActions)
            / Double(totalActions)
    }
}

struct ExecutionResult: Sendable {

    let planID: UUID

    let records: [ExecutionRecord]

    let startedAt: Date
    let finishedAt: Date

    var succeededCount: Int {

        records.filter {
            $0.status == .succeeded
        }.count
    }

    var failedCount: Int {

        records.filter {
            $0.status == .failed
        }.count
    }

    var reclaimedBytes: Int64 {

        records
            .filter {
                $0.status == .succeeded
                    && $0.operation == .trash
            }
            .reduce(0) {
                $0 + $1.fileSize
            }
    }

    var isFullySuccessful: Bool {
        failedCount == 0
    }
}

struct ExecutionRecord: Identifiable, Sendable {

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

enum ExecutionRecordStatus: Sendable {
    case succeeded
    case failed
}
