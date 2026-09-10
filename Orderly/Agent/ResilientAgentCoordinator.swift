import Foundation

/// Production orchestration wrapper around `OrderlyAgent`.
///
/// Each candidate is investigated independently against the same immutable scan
/// snapshot. A recoverable model/agent failure is converted into a conservative
/// review/keep finding for that candidate so one bad generation cannot discard
/// already-valid findings or prevent later candidates from being processed.
/// Security-boundary violations and cancellation still abort the whole run.
final class ResilientAgentCoordinator {
    private let agent: OrderlyAgent
    private let planValidator = AgentPlanValidator()

    init(agent: OrderlyAgent) {
        self.agent = agent
    }

    func run(
        analysis: AnalysisResult,
        evidence: [CandidateEvidence]
    ) async throws -> AgentState {
        var aggregate = AgentState(
            goal: """
            Safely investigate file clutter and propose one evidence-based
            disposition for every file without changing the filesystem.
            """,
            pendingCandidates: analysis.candidates
        )
        aggregate.status = .investigating

        let evidenceByCandidate = Dictionary(
            uniqueKeysWithValues: evidence.map { ($0.candidateID, $0) }
        )

        for candidate in analysis.candidates {
            try Task.checkCancellation()
            aggregate.currentCandidate = candidate

            guard let candidateEvidence = evidenceByCandidate[candidate.id] else {
                throw ResilientAgentCoordinatorError.missingEvidence(candidate.id)
            }

            let scopedAnalysis = AnalysisResult(
                analyzedFolder: analysis.analyzedFolder,
                totalFiles: analysis.totalFiles,
                totalSize: analysis.totalSize,
                fileTypes: analysis.fileTypes,
                duplicateGroups: analysis.duplicateGroups,
                candidates: [candidate],
                analyzedAt: analysis.analyzedAt,
                files: analysis.files,
                unreadableHashCount: analysis.unreadableHashCount
            )

            do {
                let partial = try await agent.run(
                    analysis: scopedAnalysis,
                    evidence: [candidateEvidence]
                )
                merge(partial, into: &aggregate)
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                if Self.isSecurityBoundaryFailure(error) {
                    throw error
                }

                print("======== CANDIDATE FAILURE ISOLATED ========")
                print("Candidate:", candidate.id)
                print("Error:", String(reflecting: error))
                print(error.localizedDescription)

                let fallback = try makeSafeFallback(
                    candidate: candidate,
                    evidence: candidateEvidence,
                    priorObservations: aggregate.observations
                )
                aggregate.observations.append(fallback.observation)
                aggregate.findings.append(fallback.finding)
                aggregate.candidateFailures.append(
                    AgentCandidateFailure(
                        candidateID: candidate.id,
                        errorType: String(reflecting: type(of: error)),
                        message: error.localizedDescription
                    )
                )

                print("======== SAFE FALLBACK FINDING ========")
                print("Relationship: uncertain")
                for proposal in fallback.finding.proposals {
                    print(
                        proposal.fileReference,
                        "->",
                        proposal.disposition.rawValue,
                        "|",
                        proposal.reason
                    )
                }
            }

            aggregate.pendingCandidates.removeAll { $0.id == candidate.id }
        }

        aggregate.currentCandidate = nil
        aggregate.status = .completed

        print("======== RESILIENT AGENT COMPLETE ========")
        print("Findings:", aggregate.findings.count)
        print("Isolated candidate failures:", aggregate.candidateFailures.count)

        return aggregate
    }

    private func merge(
        _ partial: AgentState,
        into aggregate: inout AgentState
    ) {
        aggregate.observations.append(contentsOf: partial.observations)
        aggregate.executedToolCalls.formUnion(partial.executedToolCalls)
        aggregate.findings.append(contentsOf: partial.findings)
        aggregate.candidateFailures.append(contentsOf: partial.candidateFailures)
        aggregate.iteration = partial.iteration
    }

    private func makeSafeFallback(
        candidate: AnalysisCandidate,
        evidence: CandidateEvidence,
        priorObservations: [AgentObservation]
    ) throws -> (observation: AgentObservation, finding: AgentFinding) {
        let observation = AgentObservation(
            type: .candidate,
            candidateID: candidate.id,
            content: """
            Deterministic production fallback was activated after the model-driven investigation failed.
            candidateType=\(candidate.type.rawValue)
            candidateFileCount=\(evidence.files.count)
            No semantic relationship or deletion safety conclusion was accepted for this candidate.
            """
        )

        let proposals = try evidence.files.map { file -> AgentFileProposal in
            let disposition: FileDisposition
            let reason: String

            if file.allowedDispositions.contains(.review) {
                disposition = .review
                reason = "Investigation did not complete; review this file before any change."
            } else if file.allowedDispositions.contains(.keep) {
                disposition = .keep
                reason = "Investigation did not complete; keep this file as the safe fallback."
            } else {
                throw ResilientAgentCoordinatorError.noSafeFallbackDisposition(
                    file.reference
                )
            }

            return AgentFileProposal(
                fileReference: file.reference,
                disposition: disposition,
                reason: reason
            )
        }

        let finding = AgentFinding(
            candidateID: candidate.id,
            relationship: .uncertain,
            summary: "This candidate could not be fully investigated, so Orderly is using a non-destructive fallback.",
            evidence: [
                AgentEvidenceReference(
                    observationID: observation.id,
                    description: "The model-driven investigation failed and no semantic or deletion-safety conclusion was accepted."
                )
            ],
            proposals: proposals,
            confidence: 0
        )

        let issues = planValidator.validate(
            finding: finding,
            candidate: candidate,
            evidence: evidence,
            observations: priorObservations + [observation]
        )
        guard issues.isEmpty else {
            throw ResilientAgentCoordinatorError.invalidFallbackFinding(issues)
        }

        return (observation, finding)
    }

    private static func isSecurityBoundaryFailure(_ error: Error) -> Bool {
        if let contentError = error as? ContentInspectionError,
           case .fileOutsideAnalyzedFolder = contentError {
            return true
        }

        if let imageError = error as? ImageEvidenceError,
           case .fileOutsideAnalyzedFolder = imageError {
            return true
        }

        return false
    }
}

enum ResilientAgentCoordinatorError: LocalizedError {
    case missingEvidence(UUID)
    case noSafeFallbackDisposition(String)
    case invalidFallbackFinding([String])

    var errorDescription: String? {
        switch self {
        case .missingEvidence(let candidateID):
            return "Candidate evidence is missing for \(candidateID.uuidString)."
        case .noSafeFallbackDisposition(let reference):
            return "No non-destructive fallback disposition is available for \(reference)."
        case .invalidFallbackFinding(let issues):
            return "Safe fallback validation failed: \(issues.joined(separator: "; "))"
        }
    }
}
