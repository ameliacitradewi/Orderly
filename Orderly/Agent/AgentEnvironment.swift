import Foundation

struct AgentEnvironment: Sendable {
    let analysis: AnalysisResult
    let evidenceByCandidate: [UUID: CandidateEvidence]
    let catalog: GlobalFileCatalog

    var filesByGlobalReference: [String: FileMetadata] { catalog.filesByGlobalReference }
    var globalReferenceByFileID: [UUID: String] { catalog.globalReferenceByFileID }

    init(
        analysis: AnalysisResult,
        evidence: [CandidateEvidence]
    ) {
        self.analysis = analysis
        self.catalog = GlobalFileCatalog(files: analysis.files)
        self.evidenceByCandidate = Dictionary(
            uniqueKeysWithValues: evidence.map {
                ($0.candidateID, $0)
            }
        )
    }

    /// Only references exposed by trusted tools for this investigation are usable.
    func visibleGlobalReferences(candidateID: UUID, observations: [AgentObservation]) -> Set<String> {
        Set(observations.filter { $0.candidateID == candidateID && $0.type != .error }
            .flatMap { $0.globalReferences ?? [] })
    }
}
