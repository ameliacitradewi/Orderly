import Foundation

/// Supplies evidence-gathering actions that are fully determined by trusted workflow
/// state. These steps do not require model judgment, so executing them directly avoids
/// paying for an LLM turn whose result would be deterministically redirected anyway.
///
/// This planner never creates cleanup proposals, never chooses arbitrary paths, and
/// only uses F/G references derived from the current candidate/environment.
struct AgentDeterministicEvidencePlanner {
    func nextDecision(
        candidate: AnalysisCandidate,
        environment: AgentEnvironment,
        observations: [AgentObservation]
    ) -> AgentDecision? {
        let candidateObservations = observations.filter {
            $0.candidateID == candidate.id
        }

        // Candidate inspection is a bounded read-only observation with no open-ended
        // judgment. When fast paths are enabled, expose trusted F/G references before
        // asking the model to reason about the candidate.
        guard candidateObservations.contains(where: { $0.type == .candidate }) else {
            return AgentDecision(
                action: .inspectCandidate,
                candidateID: candidate.id,
                fileReferences: [],
                reason: "Expose trusted candidate metadata before model reasoning."
            )
        }

        guard let evidence = environment.evidenceByCandidate[candidate.id] else {
            return nil
        }

        // Exact-duplicate candidates already come from deterministic SHA grouping, but
        // the safety invariant still requires an explicit verifiedDuplicate comparison
        // observation. Compare the designated keeper against each remaining copy. This
        // is read-only and deterministic; the finding is built separately only after
        // every required comparison verifies the SHA relationship.
        if candidate.type == .duplicate,
           let keeper = Self.duplicateKeeper(in: evidence) {
            let completedPairs = Self.comparedDuplicatePairKeys(
                candidateObservations,
                evidence: evidence
            )
            for file in evidence.files where file.fileID != keeper.fileID {
                let pairKey = Self.fileIDPairKey(keeper.fileID, file.fileID)
                if !completedPairs.contains(pairKey) {
                    return AgentDecision(
                        action: .compareFiles,
                        candidateID: candidate.id,
                        fileReferences: [keeper.reference, file.reference],
                        reason: "Verify the deterministic SHA duplicate relationship against the designated keeper."
                    )
                }
            }
        }

        let localFiles = evidence.files
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

    private static func comparedDuplicatePairKeys(
        _ observations: [AgentObservation],
        evidence: CandidateEvidence
    ) -> Set<String> {
        let candidateIDs = Set(evidence.files.map(\.fileID))
        return Set(observations.compactMap { observation -> String? in
            guard observation.type == .comparison,
                  let ids = observation.comparison?.fileIDs,
                  ids.count == 2,
                  Set(ids).isSubset(of: candidateIDs) else {
                return nil
            }
            return fileIDPairKey(ids[0], ids[1])
        })
    }

    private static func fileIDPairKey(_ first: UUID, _ second: UUID) -> String {
        [first.uuidString, second.uuidString].sorted().joined(separator: "|")
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
