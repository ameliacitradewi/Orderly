import Foundation

struct FileDecisionBatch: Codable, Sendable {
    let fileDecisions: [ModelFileDecision]
}
