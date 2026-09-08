import Foundation

enum CandidateRelationship: String, Codable, Sendable {
    case exactDuplicate
    case related
    case grouping
    case artifact
    case unrelated
    case uncertain
}

struct AgentFileProposal: Codable, Sendable {
    let fileReference: String
    let disposition: FileDisposition
    let reason: String
}

struct AgentEvidenceReference: Codable, Sendable, Hashable {
    let observationID: UUID
    let description: String
}

struct AgentFinding: Codable, Sendable {
    let candidateID: UUID
    let relationship: CandidateRelationship
    let summary: String
    let evidence: [AgentEvidenceReference]
    let proposals: [AgentFileProposal]
    let confidence: Double
}
