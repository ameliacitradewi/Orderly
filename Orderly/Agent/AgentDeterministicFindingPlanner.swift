import Foundation

/// Builds findings only when the entire conclusion is already fixed by trusted,
/// deterministic evidence. The first fast path is exact duplicates: SHA verification,
/// designated keeper metadata, and the cleanup allowlist fully determine the safe
/// proposal. Semantic/grouping candidates still require model reasoning.
struct AgentDeterministicFindingPlanner {
    func finding(
        candidate: AnalysisCandidate,
        evidence: CandidateEvidence,
        observations: [AgentObservation]
    ) -> AgentFinding? {
        guard candidate.type == .duplicate,
              evidence.files.count >= 2,
              let keeper = Self.duplicateKeeper(in: evidence) else {
            return nil
        }

        let candidateObservations = observations.filter {
            $0.candidateID == candidate.id && $0.type == .comparison
        }

        var cited: [AgentEvidenceReference] = []
        for file in evidence.files where file.fileID != keeper.fileID {
            guard let verification = candidateObservations.first(where: { observation in
                guard let comparison = observation.comparison,
                      comparison.verifiedDuplicate,
                      comparison.fileIDs.count == 2 else {
                    return false
                }
                return Set(comparison.fileIDs) == Set([keeper.fileID, file.fileID])
            }) else {
                return nil
            }

            cited.append(
                AgentEvidenceReference(
                    observationID: verification.id,
                    description: "SHA256 verification confirms \(file.reference) is an exact duplicate of designated keeper \(keeper.reference)."
                )
            )
        }

        guard !cited.isEmpty else { return nil }

        let proposals = evidence.files.map { file -> AgentFileProposal in
            if file.fileID == keeper.fileID {
                return AgentFileProposal(
                    fileReference: file.reference,
                    disposition: .keep,
                    reason: "Designated keeper for this SHA256-verified duplicate group."
                )
            }

            if file.allowedDispositions.contains(.trash) {
                return AgentFileProposal(
                    fileReference: file.reference,
                    disposition: .trash,
                    reason: "SHA256-verified exact duplicate of designated keeper \(keeper.reference); this copy is eligible for trash."
                )
            }

            if file.allowedDispositions.contains(.review) {
                return AgentFileProposal(
                    fileReference: file.reference,
                    disposition: .review,
                    reason: "Exact duplicate is verified, but trash is not allowed for this file; review it instead."
                )
            }

            return AgentFileProposal(
                fileReference: file.reference,
                disposition: .keep,
                reason: "Exact duplicate is verified, but the cleanup allowlist requires keeping this file."
            )
        }

        return AgentFinding(
            candidateID: candidate.id,
            relationship: .exactDuplicate,
            summary: "SHA256 verification confirms the candidate files are exact duplicates.",
            evidence: cited,
            proposals: proposals,
            confidence: 1.0
        )
    }

    private static func duplicateKeeper(
        in evidence: CandidateEvidence
    ) -> CandidateFileEvidence? {
        let keeperNames = Set(evidence.files.compactMap(\.duplicateKeeperName))
        if keeperNames.count == 1,
           let name = keeperNames.first {
            let matches = evidence.files.filter { $0.name == name }
            if matches.count == 1 {
                return matches[0]
            }
        }

        let protected = evidence.files.filter {
            !$0.allowedDispositions.contains(.trash)
        }
        return protected.count == 1 ? protected[0] : nil
    }
}
