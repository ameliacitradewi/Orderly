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

    /// Persistent run-level counters used only for local evaluation. `iteration`
    /// resets for every candidate, while these dictionaries retain the whole run.
    var stepCountByCandidate: [UUID: Int] = [:]
    var promptCharacterCountByCandidate: [UUID: Int] = [:]
}
