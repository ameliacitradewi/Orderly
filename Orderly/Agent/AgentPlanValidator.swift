import Foundation

struct AgentPlanValidator {
    func validate(
        finding: AgentFinding,
        candidate: AnalysisCandidate,
        evidence: CandidateEvidence,
        observations: [AgentObservation]
    ) -> [String] {
        var issues: [String] = []

        let expectedReferences = Set(evidence.files.map(\.reference))
        let proposedReferences = Set(finding.proposals.map(\.fileReference))

        if proposedReferences != expectedReferences {
            issues.append(
                "Finding must contain exactly one proposal per candidate file."
            )
        }

        if finding.proposals.count != proposedReferences.count {
            issues.append("Duplicate file proposals were returned.")
        }

        if finding.candidateID != candidate.id {
            issues.append("Finding references the wrong candidate.")
        }

        if !finding.confidence.isFinite
            || !(0...1).contains(finding.confidence) {
            issues.append("Confidence must be between 0 and 1.")
        }

        for proposal in finding.proposals {
            guard let file = evidence.files.first(where: {
                $0.reference == proposal.fileReference
            }) else {
                issues.append(
                    "Unknown file reference \(proposal.fileReference)."
                )
                continue
            }

            guard file.allowedDispositions.contains(
                proposal.disposition
            ) else {
                issues.append(
                    "\(proposal.disposition.rawValue) is not allowed for \(proposal.fileReference)."
                )
                continue
            }
        }

        if candidate.type == .duplicate,
           !finding.proposals.isEmpty,
           finding.proposals.allSatisfy({ $0.disposition == .trash }) {
            issues.append(
                "Agent cannot trash every member of a duplicate group."
            )
        }

        let candidateObservations = observations.filter {
            $0.candidateID == candidate.id
        }
        let availableObservationIDs = Set(
            candidateObservations
                .filter { $0.type != .error }
                .map(\.id)
        )
        let evidenceKeys = finding.evidence.map {
            let description = $0.description
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return "\($0.observationID.uuidString)|\(description)"
        }

        if finding.evidence.isEmpty {
            issues.append("Finding must cite at least one observation.")
        }
        if evidenceKeys.count != Set(evidenceKeys).count {
            issues.append("Duplicate evidence entries were returned.")
        }

        for reference in finding.evidence {
            if !availableObservationIDs.contains(reference.observationID) {
                issues.append(
                    "Unknown observation reference \(reference.observationID.uuidString)."
                )
            }
            if reference.description.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty {
                issues.append("Evidence descriptions cannot be empty.")
            }
        }

        let citedIDs = Set(finding.evidence.map(\.observationID))
        let citedObservations = candidateObservations.filter {
            citedIDs.contains($0.id) && $0.type != .error
        }

        let hasVerifiedDuplicateObservation = citedObservations.contains {
            $0.type == .comparison
                && $0.comparison?.verifiedDuplicate == true
                && !Set($0.comparison?.fileIDs ?? []).isDisjoint(with: candidate.fileIDs)
        }

        let hasSameDocumentRevisionObservation = citedObservations.contains { observation in
            guard observation.type == .documentComparison,
                  let comparison = observation.documentComparison,
                  !Set(comparison.fileIDs).isDisjoint(with: candidate.fileIDs) else {
                return false
            }
            return comparison.semantic.relationship == .sameDocumentRevision
        }

        let hasRelatedDocumentComparison = citedObservations.contains { observation in
            guard observation.type == .documentComparison,
                  let comparison = observation.documentComparison,
                  !Set(comparison.fileIDs).isDisjoint(with: candidate.fileIDs) else {
                return false
            }
            switch comparison.semantic.relationship {
            case .sameDocumentRevision, .sameTopic:
                return true
            case .unrelated, .uncertain:
                return false
            }
        }

        let hasRelatedImageComparison = citedObservations.contains { observation in
            guard observation.type == .imageSemanticComparison,
                  let comparison = observation.imageSemanticComparison,
                  !Set(comparison.fileIDs).isDisjoint(with: candidate.fileIDs) else {
                return false
            }
            switch comparison.semantic.relationship {
            case .sameImageVariant, .sameScene, .sameSubject:
                return true
            case .unrelated, .uncertain:
                return false
            }
        }

        if finding.relationship == .related,
           !hasRelatedDocumentComparison,
           !hasRelatedImageComparison {
            issues.append(
                "A related finding requires a cited semantic document or image comparison whose supported relationship includes a current-candidate file."
            )
        }

        if finding.relationship == .related,
           hasRelatedImageComparison,
           finding.proposals.contains(where: { $0.disposition == .trash }) {
            issues.append(
                "Visual similarity cannot authorize trash; image-related findings must remain non-destructive unless exact duplicate safety is established separately."
            )
        }

        if finding.relationship == .related,
           hasSameDocumentRevisionObservation,
           finding.assertsUnsupportedRevisionOrdering {
            issues.append(
                "Revision comparison establishes a symmetric relationship only; do not claim that one file is the revision, later, newer, older, previous, or final version of the other without trusted structured ordering evidence."
            )
        }

        if finding.assertsDuplicateRelationship,
           !hasVerifiedDuplicateObservation {
            issues.append(
                "Duplicate claims require an observation with verifiedDuplicate=true."
            )
        }

        return issues
    }
}

private extension AgentFinding {
    var assertsDuplicateRelationship: Bool {
        if relationship == .exactDuplicate {
            return true
        }

        let negatedDuplicatePattern = #"\b(no|without)\s+(verified\s+|exact\s+)?duplicates?\b|\bnot\s+(an?\s+)?(verified\s+|exact\s+)?duplicates?\b|\bnot\s+verified\s+as\s+(an?\s+)?duplicates?\b"#
        let duplicateWordPattern = #"\bduplicates?\b"#
        let texts = [summary]
            + evidence.map(\.description)
            + proposals.map(\.reason)

        return texts.contains {
            let withoutNegations = $0.lowercased().replacingOccurrences(
                of: negatedDuplicatePattern,
                with: "",
                options: .regularExpression
            )
            return withoutNegations.range(
                of: duplicateWordPattern,
                options: .regularExpression
            ) != nil
        }
    }

    var assertsUnsupportedRevisionOrdering: Bool {
        let patterns = [
            #"\b(is|appears|seems|looks)\s+(to\s+be\s+)?(a\s+)?revision\s+of\b"#,
            #"\b(later|newer|older|earlier|latest|previous|prior|final)\s+(version|revision|draft|document|file)\b"#,
            #"\b(version|revision)\s+(after|before)\b"#,
            #"\bsupersedes?\b"#
        ]
        let texts = [summary]
            + evidence.map(\.description)
            + proposals.map(\.reason)

        return texts.contains { text in
            let lowercased = text.lowercased()
            return patterns.contains { pattern in
                lowercased.range(
                    of: pattern,
                    options: .regularExpression
                ) != nil
            }
        }
    }
}
