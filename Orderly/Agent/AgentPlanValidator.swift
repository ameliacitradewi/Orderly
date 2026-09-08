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

        let availableObservationIDs = Set(
            observations
                .filter { $0.candidateID == candidate.id }
                .map(\.id)
        )
        let citedObservationIDs = Set(
            finding.evidence.map(\.observationID)
        )

        if finding.evidence.isEmpty {
            issues.append("Finding must cite at least one observation.")
        }
        if finding.evidence.count != citedObservationIDs.count {
            issues.append("Duplicate evidence references were returned.")
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

        return issues
    }
}
