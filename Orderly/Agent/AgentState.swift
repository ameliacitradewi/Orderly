import Foundation

enum AgentStatus: String, Codable, Sendable {
    case ready
    case investigating
    case completed
    case failed
}

/// Records a candidate-level planning failure that was isolated by the production
/// coordinator. The failure is diagnostic only; fallback findings remain
/// non-destructive and are represented separately in `findings`.
struct AgentCandidateFailure: Codable, Sendable, Equatable {
    let candidateID: UUID
    let errorType: String
    let message: String
}

struct AgentState: Sendable {
    let goal: String
    var pendingCandidates: [AnalysisCandidate]
    var currentCandidate: AnalysisCandidate?
    var observations: [AgentObservation] = []
    var executedToolCalls: Set<AgentToolCallSignature> = []
    var findings: [AgentFinding] = []
    var candidateFailures: [AgentCandidateFailure] = []
    var iteration: Int = 0
    var status: AgentStatus = .ready
}
