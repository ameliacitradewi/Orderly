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

        // Metadata, filenames, timestamps, and SHA non-matches can rule out some exact
        // duplicate hypotheses, but cannot establish a cross-file semantic relationship.
        // Keep this check relationship-agnostic because a model can otherwise put an
        // unsupported visual/session/topic claim inside a grouping or uncertain finding.
        if candidate.fileIDs.count > 1,
           finding.assertsCrossFileSemanticRelationship,
           !hasRelatedDocumentComparison,
           !hasRelatedImageComparison {
            issues.append(
                "Cross-file semantic claims such as visual similarity, shared session/project/topic/subject, or image/document variants require a cited semantic comparison. Metadata-only evidence cannot establish that relationship."
            )
        }

        // A category batch is not a semantic cluster. If the natural-language finding
        // claims that *all* candidate files share a topic/project/subject, the cited
        // semantic comparisons must form one connected evidence graph covering every
        // candidate file. Inspecting or comparing only F1/F2 cannot justify a claim
        // about uninspected F3/F4.
        if candidate.fileIDs.count > 1,
           finding.assertsUniversalSemanticGrouping,
           !Self.hasConnectedSemanticSupport(
               for: candidate.fileIDs,
               in: citedObservations
           ) {
            issues.append(
                "A claim that all candidate files share the same topic, project, subject, session, or semantic relationship requires cited semantic comparisons that connect every candidate file. Do not generalize from only a subset of files."
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

    private static func hasConnectedSemanticSupport(
        for candidateFileIDs: [UUID],
        in observations: [AgentObservation]
    ) -> Bool {
        guard candidateFileIDs.count > 1 else { return true }

        var adjacency: [UUID: Set<UUID>] = [:]

        func connect(_ fileIDs: [UUID]) {
            guard fileIDs.count >= 2 else { return }
            for leftIndex in 0..<(fileIDs.count - 1) {
                for rightIndex in (leftIndex + 1)..<fileIDs.count {
                    let left = fileIDs[leftIndex]
                    let right = fileIDs[rightIndex]
                    adjacency[left, default: []].insert(right)
                    adjacency[right, default: []].insert(left)
                }
            }
        }

        for observation in observations {
            if observation.type == .documentComparison,
               let comparison = observation.documentComparison {
                switch comparison.semantic.relationship {
                case .sameDocumentRevision, .sameTopic:
                    connect(comparison.fileIDs)
                case .unrelated, .uncertain:
                    break
                }
            }

            if observation.type == .imageSemanticComparison,
               let comparison = observation.imageSemanticComparison {
                switch comparison.semantic.relationship {
                case .sameImageVariant, .sameScene, .sameSubject:
                    connect(comparison.fileIDs)
                case .unrelated, .uncertain:
                    break
                }
            }
        }

        guard let start = candidateFileIDs.first else { return true }
        var visited: Set<UUID> = [start]
        var queue: [UUID] = [start]

        while let current = queue.first {
            queue.removeFirst()
            for neighbor in adjacency[current] ?? [] where !visited.contains(neighbor) {
                visited.insert(neighbor)
                queue.append(neighbor)
            }
        }

        return candidateFileIDs.allSatisfy(visited.contains)
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

    var assertsCrossFileSemanticRelationship: Bool {
        let patterns = [
            #"\bvisual\s+similarity\s+(suggests|indicates|shows|supports|implies)\b"#,
            #"\bvisually\s+(similar|related)\b"#,
            #"\bsimilar\s+(ui|screens?|scenes?|subjects?|content|images?|documents?|screenshots?)\b"#,
            #"\b(same|shared)\s+(session|project|topic|subject|scene|screen|content)\b"#,
            #"\b(images?|screenshots?|documents?)\s+(are\s+)?(variants?|related)\b"#,
            #"\bvariants?\s+of\s+(the\s+)?same\b"#
        ]
        let texts = [summary] + proposals.map(\.reason)

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

    var assertsUniversalSemanticGrouping: Bool {
        let patterns = [
            #"\ball\s+(candidate\s+)?files?\b.*\b(related|same\s+(topic|project|subject|session|scene))\b"#,
            #"\b(all|these)\s+files?\b.*\bshare(s|d)?\s+(the\s+)?same\s+(topic|project|subject|session)\b"#,
            #"\bfiles?\b.*\bshare(s|d)?\s+(the\s+)?same\s+(topic|project|subject|session)\b"#,
            #"\brelated\s+to\s+the\s+same\s+(topic|project|subject|session)\b"#
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
