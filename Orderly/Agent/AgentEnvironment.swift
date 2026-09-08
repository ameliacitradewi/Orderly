import Foundation

struct AgentEnvironment: Sendable {
    let analysis: AnalysisResult
    let evidenceByCandidate: [UUID: CandidateEvidence]

    init(
        analysis: AnalysisResult,
        evidence: [CandidateEvidence]
    ) {
        self.analysis = analysis
        self.evidenceByCandidate = Dictionary(
            uniqueKeysWithValues: evidence.map {
                ($0.candidateID, $0)
            }
        )
    }
}
