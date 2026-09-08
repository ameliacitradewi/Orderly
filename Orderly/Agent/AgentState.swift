import Foundation

enum AgentStatus: String, Codable, Sendable {
    case ready
    case investigating
    case completed
    case failed
}

struct AgentState: Sendable {
    let goal: String
    var pendingCandidates: [AnalysisCandidate]
    var currentCandidate: AnalysisCandidate?
    var observations: [AgentObservation] = []
    var executedToolCalls: Set<AgentToolCallSignature> = []
    var findings: [AgentFinding] = []
    var iteration: Int = 0
    var status: AgentStatus = .ready
}
