import Foundation

/// Builds findings only when the conclusion is already fixed by trusted typed evidence
/// plus the cleanup allowlist. Fast paths are deliberately narrow:
/// - exact duplicates require SHA verification and designated keeper evidence;
/// - semantic relationships may only resolve to non-destructive review/keep proposals.
///
/// This planner never invents filesystem targets, never turns visual/document similarity
/// into deletion authority, and every returned finding is still validated by
/// `AgentPlanValidator` before it can leave the agent loop.
struct AgentDeterministicFindingPlanner {
    func finding(
        candidate: AnalysisCandidate,
        evidence: CandidateEvidence,
        observations: [AgentObservation]
    ) -> AgentFinding? {
        if let duplicate = exactDuplicateFinding(
            candidate: candidate,
            evidence: evidence,
            observations: observations
        ) {
            return duplicate
        }

        return semanticNonDestructiveFinding(
            candidate: candidate,
            evidence: evidence,
            observations: observations
        )
    }

    private func exactDuplicateFinding(
        candidate: AnalysisCandidate,
        evidence: CandidateEvidence,
        observations: [AgentObservation]
    ) -> AgentFinding? {
        guard candidate.type == .duplicate,
              evidence.files.count >= 2,
              let keeper = Self.duplicateKeeper(in: evidence),
              keeper.allowedDispositions.contains(.keep) else {
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

    /// Once a typed semantic comparison already establishes a connected relationship
    /// across every local candidate file, a second general-purpose model turn adds no
    /// cleanup authority when destructive actions are unavailable. In that narrow case
    /// the safe outcome is fixed: review where permitted, otherwise keep.
    private func semanticNonDestructiveFinding(
        candidate: AnalysisCandidate,
        evidence: CandidateEvidence,
        observations: [AgentObservation]
    ) -> AgentFinding? {
        guard candidate.type != .duplicate,
              evidence.files.count >= 2,
              evidence.files.allSatisfy({ !$0.allowedDispositions.contains(.trash) }),
              evidence.files.allSatisfy({
                  $0.allowedDispositions.contains(.review)
                      || $0.allowedDispositions.contains(.keep)
              }) else {
            return nil
        }

        let candidateIDs = Set(candidate.fileIDs)
        guard candidateIDs == Set(evidence.files.map(\.fileID)) else {
            return nil
        }

        let supports = observations.compactMap { observation -> SemanticSupport? in
            guard observation.candidateID == candidate.id else { return nil }

            if observation.type == .documentComparison,
               let comparison = observation.documentComparison,
               comparison.semantic.confidence.isFinite,
               (0...1).contains(comparison.semantic.confidence),
               Self.isEntirelyLocal(comparison.fileIDs, candidateIDs: candidateIDs) {
                let description: String
                switch comparison.semantic.relationship {
                case .sameDocumentRevision:
                    description = "Semantic document comparison classifies the compared files as revisions of the same underlying document."
                case .sameTopic:
                    description = "Semantic document comparison classifies the compared files as related by topic without establishing a revision relationship."
                case .unrelated, .uncertain:
                    return nil
                }
                return SemanticSupport(
                    observationID: observation.id,
                    fileIDs: comparison.fileIDs,
                    description: description,
                    confidence: comparison.semantic.confidence,
                    modality: .document
                )
            }

            if observation.type == .imageSemanticComparison,
               let comparison = observation.imageSemanticComparison,
               comparison.semantic.confidence.isFinite,
               (0...1).contains(comparison.semantic.confidence),
               Self.isEntirelyLocal(comparison.fileIDs, candidateIDs: candidateIDs) {
                let description: String
                switch comparison.semantic.relationship {
                case .sameImageVariant:
                    description = "Semantic image comparison classifies the compared images as variants of the same underlying image or screen."
                case .sameScene:
                    description = "Semantic image comparison classifies the compared images as the same scene or screen-state family."
                case .sameSubject:
                    description = "Semantic image comparison classifies the compared images as sharing the same main subject."
                case .unrelated, .uncertain:
                    return nil
                }
                return SemanticSupport(
                    observationID: observation.id,
                    fileIDs: comparison.fileIDs,
                    description: description,
                    confidence: comparison.semantic.confidence,
                    modality: .image
                )
            }

            return nil
        }

        guard !supports.isEmpty,
              Self.connectsEveryCandidateFile(
                  supports: supports,
                  candidateIDs: candidateIDs
              ) else {
            return nil
        }

        let cited = supports.map {
            AgentEvidenceReference(
                observationID: $0.observationID,
                description: $0.description
            )
        }
        let confidence = supports.map(\.confidence).min() ?? 0
        let modalities = Set(supports.map(\.modality))

        let summary: String
        if modalities == [.document] {
            summary = "Cited semantic document comparison classifies the candidate files as related."
        } else if modalities == [.image] {
            summary = "Cited semantic image comparison classifies the candidate files as related visual content."
        } else {
            summary = "Cited semantic comparisons classify the candidate files as related."
        }

        let proposals = evidence.files.map { file -> AgentFileProposal in
            if file.allowedDispositions.contains(.review) {
                return AgentFileProposal(
                    fileReference: file.reference,
                    disposition: .review,
                    reason: "Semantic relationship evidence is non-destructive and does not establish cleanup authority; review this file before any action."
                )
            }

            return AgentFileProposal(
                fileReference: file.reference,
                disposition: .keep,
                reason: "Semantic relationship evidence is non-destructive, and this file's allowlist requires keeping it."
            )
        }

        return AgentFinding(
            candidateID: candidate.id,
            relationship: .related,
            summary: summary,
            evidence: cited,
            proposals: proposals,
            confidence: confidence
        )
    }

    private struct SemanticSupport {
        enum Modality: Hashable {
            case document
            case image
        }

        let observationID: UUID
        let fileIDs: [UUID]
        let description: String
        let confidence: Double
        let modality: Modality
    }

    private static func isEntirelyLocal(
        _ fileIDs: [UUID],
        candidateIDs: Set<UUID>
    ) -> Bool {
        let ids = Set(fileIDs)
        return ids.count >= 2 && ids.isSubset(of: candidateIDs)
    }

    private static func connectsEveryCandidateFile(
        supports: [SemanticSupport],
        candidateIDs: Set<UUID>
    ) -> Bool {
        guard let start = candidateIDs.first else { return false }
        var adjacency: [UUID: Set<UUID>] = [:]

        for support in supports {
            let ids = Array(Set(support.fileIDs))
            guard ids.count >= 2 else { continue }
            for leftIndex in 0..<(ids.count - 1) {
                for rightIndex in (leftIndex + 1)..<ids.count {
                    let left = ids[leftIndex]
                    let right = ids[rightIndex]
                    adjacency[left, default: []].insert(right)
                    adjacency[right, default: []].insert(left)
                }
            }
        }

        var visited: Set<UUID> = [start]
        var queue: [UUID] = [start]
        while let current = queue.first {
            queue.removeFirst()
            for neighbor in adjacency[current] ?? [] where !visited.contains(neighbor) {
                visited.insert(neighbor)
                queue.append(neighbor)
            }
        }
        return candidateIDs.isSubset(of: visited)
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
