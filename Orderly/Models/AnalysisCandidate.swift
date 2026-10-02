import Foundation

struct AnalysisCandidate: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let type: CandidateType
    let fileIDs: [UUID]
    let confidence: Double
    let reason: String
}

enum CandidateType: String, Codable, Hashable, Sendable {
    case grouping
    case duplicate
    case artifact
}
