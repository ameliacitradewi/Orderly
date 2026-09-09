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

        if finding.relationship == .related,
           !hasRelatedDocumentComparison {
            issues.append(
                "A related finding requires a cited document comparison whose semantic result is sameDocumentRevision or sameTopic and includes a current-candidate file."
            )
        }

        if finding.assertsDuplicateRelationship,
           !hasVerifiedDuplicateObservation {
            issues.append(
                "Duplicate claims require a cited observation with verifiedDuplicate=true."
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
}
