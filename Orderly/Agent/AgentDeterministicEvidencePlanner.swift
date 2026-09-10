import Foundation

/// Supplies only evidence-gathering actions that are already mandatory from trusted
/// workflow state or validator feedback. These steps do not require model judgment,
/// so executing them directly avoids paying for an LLM turn whose result would be
/// deterministically redirected anyway.
///
/// This planner never creates cleanup proposals, never chooses arbitrary paths, and
/// only uses F/G references that were derived from the current candidate/environment.
struct AgentDeterministicEvidencePlanner {
    func nextDecision(
        candidate: AnalysisCandidate,
        environment: AgentEnvironment,
        observations: [AgentObservation]
    ) -> AgentDecision? {
        let candidateObservations = observations.filter {
            $0.candidateID == candidate.id
        }

        // inspectCandidate remains model-visible for normal agent-loop compatibility.
        // Mandatory semantic steps only become eligible after trusted candidate
        // references and typed capabilities have been exposed by that observation.
        guard candidateObservations.contains(where: { $0.type == .candidate }) else {
            return nil
        }

        let localFiles = environment.evidenceByCandidate[candidate.id]?.files ?? []
        let localGlobalReferences = Set(localFiles.compactMap {
            environment.globalReferenceByFileID[$0.fileID]
        })

        let inspectedContent = candidateObservations.compactMap(\.contentObservation)
        let inspectedLocalPDFs = Set(inspectedContent.compactMap(\.localReference))
        let inspectedGlobalPDFs = Set(inspectedContent.map(\.globalReference))
        let unavailablePDFs = Set(
            candidateObservations
                .filter { $0.type == .error }
                .flatMap { $0.unavailablePDFReferences ?? [] }
        )
        let candidatePDFs = Set(
            candidateObservations
                .filter { $0.type == .candidate }
                .flatMap { $0.pdfFileReferences ?? [] }
        )
        let availableLocalPDFs = candidatePDFs
            .subtracting(inspectedLocalPDFs)
            .subtracting(unavailablePDFs)
            .sorted()
        let comparedDocumentPairKeys = Set(
            candidateObservations.compactMap { observation -> String? in
                guard observation.type == .documentComparison,
                      let references = observation.documentComparison?.globalReferences,
                      references.count == 2 else {
                    return nil
                }
                return Self.pairKey(references)
            }
        )

        let imageContent = candidateObservations.compactMap(\.imageSemantic)
        let inspectedLocalImages = Set(imageContent.compactMap(\.localReference))
        let inspectedGlobalImages = Set(imageContent.map(\.globalReference))
        let unavailableImages = Set(
            candidateObservations
                .filter { $0.type == .error }
                .flatMap { $0.unavailableImageReferences ?? [] }
        )
        let candidateImages = Set(
            candidateObservations
                .filter { $0.type == .candidate }
                .flatMap { $0.imageFileReferences ?? [] }
        )
        let availableLocalImages = candidateImages
            .subtracting(inspectedLocalImages)
            .subtracting(unavailableImages)
            .sorted()
        let comparedImagePairKeys = Set(
            candidateObservations.compactMap { observation -> String? in
                guard observation.type == .imageSemanticComparison,
                      let references = observation.imageSemanticComparison?.globalReferences,
                      references.count == 2 else {
                    return nil
                }
                return Self.pairKey(references)
            }
        )

        switch candidate.investigationRequirement {
        case .documentSemantic:
            if let decision = nextDocumentDecision(
                candidateID: candidate.id,
                availableLocalReferences: availableLocalPDFs,
                inspectedGlobalReferences: inspectedGlobalPDFs,
                completedPairKeys: comparedDocumentPairKeys,
                localGlobalReferences: localGlobalReferences,
                reasonPrefix: "Required workflow"
            ) {
                return decision
            }

        case .imageSemantic:
            if let decision = nextImageDecision(
                candidateID: candidate.id,
                availableLocalReferences: availableLocalImages,
                inspectedGlobalReferences: inspectedGlobalImages,
                completedPairKeys: comparedImagePairKeys,
                localGlobalReferences: localGlobalReferences,
                reasonPrefix: "Required workflow"
            ) {
                return decision
            }

        case .automatic:
            break
        }

        // If validation already proved that a semantic cross-file claim lacks the
        // required evidence, gathering that evidence is no longer an open-ended
        // planning choice. Run the minimum bounded recovery path directly instead of
        // asking Qwen for a turn that AgentDecisionReferenceResolver would redirect.
        guard let triggerIndex = candidateObservations.lastIndex(where: {
            $0.type == .error && Self.requiresSemanticRecovery($0.content)
        }) else {
            return nil
        }

        let afterTrigger = candidateObservations.dropFirst(triggerIndex + 1)

        if candidateImages.count >= 2,
           !afterTrigger.contains(where: { $0.type == .imageSemanticComparison }),
           let decision = nextImageDecision(
               candidateID: candidate.id,
               availableLocalReferences: availableLocalImages,
               inspectedGlobalReferences: inspectedGlobalImages,
               completedPairKeys: comparedImagePairKeys,
               localGlobalReferences: localGlobalReferences,
               reasonPrefix: "Validator recovery"
           ) {
            return decision
        }

        if candidatePDFs.count >= 2,
           !afterTrigger.contains(where: { $0.type == .documentComparison }),
           let decision = nextDocumentDecision(
               candidateID: candidate.id,
               availableLocalReferences: availableLocalPDFs,
               inspectedGlobalReferences: inspectedGlobalPDFs,
               completedPairKeys: comparedDocumentPairKeys,
               localGlobalReferences: localGlobalReferences,
               reasonPrefix: "Validator recovery"
           ) {
            return decision
        }

        return nil
    }

    private func nextDocumentDecision(
        candidateID: UUID,
        availableLocalReferences: [String],
        inspectedGlobalReferences: Set<String>,
        completedPairKeys: Set<String>,
        localGlobalReferences: Set<String>,
        reasonPrefix: String
    ) -> AgentDecision? {
        if let next = availableLocalReferences.first {
            return AgentDecision(
                action: .inspectPDFContent,
                candidateID: candidateID,
                fileReferences: [next],
                reason: "\(reasonPrefix) requires document semantic evidence before another planning decision."
            )
        }

        let inspectedCandidateReferences = inspectedGlobalReferences.intersection(
            localGlobalReferences
        )
        guard let pair = Self.firstUncomparedPair(
            in: inspectedCandidateReferences,
            completedPairKeys: completedPairKeys
        ) else {
            return nil
        }

        return AgentDecision(
            action: .compareDocumentContent,
            candidateID: candidateID,
            fileReferences: pair,
            reason: "\(reasonPrefix) requires semantic document comparison before another planning decision."
        )
    }

    private func nextImageDecision(
        candidateID: UUID,
        availableLocalReferences: [String],
        inspectedGlobalReferences: Set<String>,
        completedPairKeys: Set<String>,
        localGlobalReferences: Set<String>,
        reasonPrefix: String
    ) -> AgentDecision? {
        if let next = availableLocalReferences.first {
            return AgentDecision(
                action: .inspectImageContent,
                candidateID: candidateID,
                fileReferences: [next],
                reason: "\(reasonPrefix) requires visual semantic evidence before another planning decision."
            )
        }

        let inspectedCandidateReferences = inspectedGlobalReferences.intersection(
            localGlobalReferences
        )
        guard let pair = Self.firstUncomparedPair(
            in: inspectedCandidateReferences,
            completedPairKeys: completedPairKeys
        ) else {
            return nil
        }

        return AgentDecision(
            action: .compareImageContent,
            candidateID: candidateID,
            fileReferences: pair,
            reason: "\(reasonPrefix) requires semantic image comparison before another planning decision."
        )
    }

    private static func requiresSemanticRecovery(_ content: String) -> Bool {
        let markers = [
            "Cross-file semantic claims such as visual similarity",
            "A related finding requires a cited semantic document or image comparison",
            "requires cited semantic comparisons that connect every candidate file"
        ]
        return markers.contains { content.contains($0) }
    }

    private static func firstUncomparedPair(
        in references: Set<String>,
        completedPairKeys: Set<String>
    ) -> [String]? {
        let sorted = references.sorted()
        guard sorted.count >= 2 else { return nil }

        for leftIndex in 0..<(sorted.count - 1) {
            for rightIndex in (leftIndex + 1)..<sorted.count {
                let pair = [sorted[leftIndex], sorted[rightIndex]]
                if !completedPairKeys.contains(pairKey(pair)) {
                    return pair
                }
            }
        }
        return nil
    }

    private static func pairKey(_ references: [String]) -> String {
        references.sorted().joined(separator: "|")
    }
}
