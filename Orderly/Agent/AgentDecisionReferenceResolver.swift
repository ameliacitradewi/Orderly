import Foundation

/// Repairs bounded agent decisions without expanding filesystem authority.
///
/// Normal behavior only fills missing references or canonicalizes a local F alias to
/// the trusted G identity of the same file. After the validator explicitly rejects a
/// cross-file semantic claim for missing semantic evidence, this resolver may also
/// redirect the next invalid/non-semantic action to the minimum read-only semantic
/// inspection/comparison needed to resolve that feedback. It never selects an outside
/// path, never changes a cleanup proposal, and stops forcing recovery when semantic
/// evidence has been gathered or the required content is unavailable.
struct AgentDecisionReferenceResolver {
    func resolve(
        _ decision: AgentDecision,
        candidate: AnalysisCandidate,
        environment: AgentEnvironment,
        observations: [AgentObservation]
    ) -> AgentDecision {
        guard decision.action != .inspectCandidate else {
            return decision
        }

        let candidateObservations = observations.filter {
            $0.candidateID == candidate.id
        }
        let localFiles = environment.evidenceByCandidate[candidate.id]?.files ?? []
        let localReferences = localFiles.map(\.reference).sorted()
        let localGlobalReferences = Set(localFiles.compactMap {
            environment.globalReferenceByFileID[$0.fileID]
        })
        let localToGlobal = Dictionary(
            uniqueKeysWithValues: localFiles.compactMap { file -> (String, String)? in
                guard let global = environment.globalReferenceByFileID[file.fileID] else {
                    return nil
                }
                return (file.reference, global)
            }
        )
        let visibleGlobalReferences = environment.visibleGlobalReferences(
            candidateID: candidate.id,
            observations: observations
        ).sorted()

        let inspectedContent = candidateObservations.compactMap(\.contentObservation)
        let inspectedLocalPDFs = Set(inspectedContent.compactMap(\.localReference))
        let inspectedGlobalPDFs = Set(inspectedContent.map(\.globalReference))
        let unavailablePDFs = Set(
            candidateObservations
                .filter { $0.type == .error }
                .flatMap { $0.unavailablePDFReferences ?? [] }
        )
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

        let candidatePDFs = Set(
            candidateObservations
                .filter { $0.type == .candidate }
                .flatMap { $0.pdfFileReferences ?? [] }
        )
        let availableLocalPDFs = candidatePDFs
            .subtracting(inspectedLocalPDFs)
            .subtracting(unavailablePDFs)
            .sorted()

        let candidateImages = Set(
            candidateObservations
                .filter { $0.type == .candidate }
                .flatMap { $0.imageFileReferences ?? [] }
        )
        let availableLocalImages = candidateImages
            .subtracting(inspectedLocalImages)
            .subtracting(unavailableImages)
            .sorted()

        let exposedGlobalPDFs = Set(
            candidateObservations
                .filter { $0.type != .error }
                .flatMap { $0.pdfGlobalReferences ?? [] }
        )
        let availableExternalPDFs = exposedGlobalPDFs
            .subtracting(localGlobalReferences)
            .subtracting(inspectedGlobalPDFs)
            .subtracting(unavailablePDFs)
            .sorted()

        let exposedGlobalImages = Set(
            candidateObservations
                .filter { $0.type != .error }
                .flatMap { $0.imageGlobalReferences ?? [] }
        )
        let availableExternalImages = exposedGlobalImages
            .subtracting(localGlobalReferences)
            .subtracting(inspectedGlobalImages)
            .subtracting(unavailableImages)
            .sorted()

        if let recovered = semanticRecoveryDecision(
            original: decision,
            candidateObservations: candidateObservations,
            candidatePDFs: candidatePDFs,
            availableLocalPDFs: availableLocalPDFs,
            inspectedGlobalPDFs: inspectedGlobalPDFs,
            comparedDocumentPairKeys: comparedDocumentPairKeys,
            candidateImages: candidateImages,
            availableLocalImages: availableLocalImages,
            inspectedGlobalImages: inspectedGlobalImages,
            comparedImagePairKeys: comparedImagePairKeys,
            localGlobalReferences: localGlobalReferences
        ) {
            print("======== AGENT SEMANTIC RECOVERY ========")
            print("Original action:", decision.action.rawValue)
            print("Recovery action:", recovered.action.rawValue)
            print("Recovery fileReferences:", recovered.fileReferences)
            return recovered
        }

        // Qwen sometimes correctly selects a G-only comparison action but copies the
        // local F aliases from the image/PDF observations. Canonicalize only when every
        // resulting G reference is already eligible for that exact comparison. An
        // invalid, ambiguous, or uninspected explicit reference is intentionally left
        // untouched so ToolRouter can reject it and provide bounded feedback.
        if !decision.fileReferences.isEmpty,
           let canonical = canonicalizeExplicitGlobalComparisonReferences(
               decision,
               localToGlobal: localToGlobal,
               localGlobalReferences: localGlobalReferences,
               visibleGlobalReferences: Set(visibleGlobalReferences),
               inspectedGlobalPDFs: inspectedGlobalPDFs,
               inspectedGlobalImages: inspectedGlobalImages,
               comparedDocumentPairKeys: comparedDocumentPairKeys,
               comparedImagePairKeys: comparedImagePairKeys
           ) {
            print("======== AGENT REFERENCE CANONICALIZATION ========")
            print("Action:", decision.action.rawValue)
            print("Original fileReferences:", decision.fileReferences)
            print("Canonical G references:", canonical)
            return replacingReferences(in: decision, with: canonical)
        }

        guard decision.fileReferences.isEmpty else {
            return decision
        }

        let repairedReferences: [String]?
        switch decision.action {
        case .inspectFile, .findRelatedFiles:
            repairedReferences = exactlyOne(localReferences)

        case .inspectPDFContent:
            repairedReferences = exactlyOne(availableLocalPDFs)

        case .inspectImageContent:
            repairedReferences = exactlyOne(availableLocalImages)

        case .inspectGlobalFile:
            repairedReferences = exactlyOne(visibleGlobalReferences)

        case .inspectGlobalPDFContent:
            repairedReferences = exactlyOne(availableExternalPDFs)

        case .inspectGlobalImageContent:
            repairedReferences = exactlyOne(availableExternalImages)

        case .compareFiles:
            repairedReferences = localReferences.count == 2
                ? localReferences
                : nil

        case .compareGlobalFiles:
            let visible = visibleGlobalReferences
            repairedReferences = visible.count == 2
                && !Set(visible).isDisjoint(with: localGlobalReferences)
                ? visible
                : nil

        case .compareDocumentContent:
            let inspected = inspectedGlobalPDFs.sorted()
            let key = Self.pairKey(inspected)
            repairedReferences = inspected.count == 2
                && !Set(inspected).isDisjoint(with: localGlobalReferences)
                && !comparedDocumentPairKeys.contains(key)
                ? inspected
                : nil

        case .compareImageContent:
            let inspected = inspectedGlobalImages.sorted()
            let key = Self.pairKey(inspected)
            repairedReferences = inspected.count == 2
                && !Set(inspected).isDisjoint(with: localGlobalReferences)
                && !comparedImagePairKeys.contains(key)
                ? inspected
                : nil

        case .inspectCandidate, .finishCandidate:
            repairedReferences = nil
        }

        guard let repairedReferences else {
            return decision
        }

        print("======== AGENT ARGUMENT REPAIR ========")
        print("Action:", decision.action.rawValue)
        print("Filled fileReferences:", repairedReferences)

        return replacingReferences(in: decision, with: repairedReferences)
    }

    /// A validator rejection is a bounded signal that the agent tried to make a
    /// semantic cross-file claim from metadata only. Recovery is intentionally
    /// deterministic: inspect remaining local files one at a time, then compare one
    /// trusted candidate pair. If inspection is unavailable, no action is forced and
    /// the model can finish conservatively with review/keep.
    private func semanticRecoveryDecision(
        original: AgentDecision,
        candidateObservations: [AgentObservation],
        candidatePDFs: Set<String>,
        availableLocalPDFs: [String],
        inspectedGlobalPDFs: Set<String>,
        comparedDocumentPairKeys: Set<String>,
        candidateImages: Set<String>,
        availableLocalImages: [String],
        inspectedGlobalImages: Set<String>,
        comparedImagePairKeys: Set<String>,
        localGlobalReferences: Set<String>
    ) -> AgentDecision? {
        guard let triggerIndex = candidateObservations.lastIndex(where: {
            $0.type == .error && Self.requiresSemanticRecovery($0.content)
        }) else {
            return nil
        }

        let afterTrigger = candidateObservations.dropFirst(triggerIndex + 1)
        let imageComparisonAfterTrigger = afterTrigger.contains {
            $0.type == .imageSemanticComparison
        }
        let documentComparisonAfterTrigger = afterTrigger.contains {
            $0.type == .documentComparison
        }

        if candidateImages.count >= 2,
           !imageComparisonAfterTrigger {
            if Self.isValidInspectionChoice(
                original,
                action: .inspectImageContent,
                allowedReferences: availableLocalImages
            ) {
                return nil
            }

            if let next = availableLocalImages.first {
                return replacingAction(
                    in: original,
                    with: .inspectImageContent,
                    references: [next],
                    reason: "Validator recovery requires visual evidence before another semantic cross-file conclusion."
                )
            }

            let inspectedCandidateImages = inspectedGlobalImages.intersection(
                localGlobalReferences
            )
            if let pair = Self.firstUncomparedPair(
                in: inspectedCandidateImages,
                completedPairKeys: comparedImagePairKeys
            ) {
                if Self.isValidPairChoice(
                    original,
                    action: .compareImageContent,
                    allowedPair: pair
                ) {
                    return nil
                }
                return replacingAction(
                    in: original,
                    with: .compareImageContent,
                    references: pair,
                    reason: "Validator recovery requires a semantic image comparison before another cross-file visual conclusion."
                )
            }
        }

        if candidatePDFs.count >= 2,
           !documentComparisonAfterTrigger {
            if Self.isValidInspectionChoice(
                original,
                action: .inspectPDFContent,
                allowedReferences: availableLocalPDFs
            ) {
                return nil
            }

            if let next = availableLocalPDFs.first {
                return replacingAction(
                    in: original,
                    with: .inspectPDFContent,
                    references: [next],
                    reason: "Validator recovery requires document content evidence before another semantic cross-file conclusion."
                )
            }

            let inspectedCandidatePDFs = inspectedGlobalPDFs.intersection(
                localGlobalReferences
            )
            if let pair = Self.firstUncomparedPair(
                in: inspectedCandidatePDFs,
                completedPairKeys: comparedDocumentPairKeys
            ) {
                if Self.isValidPairChoice(
                    original,
                    action: .compareDocumentContent,
                    allowedPair: pair
                ) {
                    return nil
                }
                return replacingAction(
                    in: original,
                    with: .compareDocumentContent,
                    references: pair,
                    reason: "Validator recovery requires a semantic document comparison before another cross-file conclusion."
                )
            }
        }

        return nil
    }

    private static func requiresSemanticRecovery(_ content: String) -> Bool {
        let markers = [
            "Cross-file semantic claims such as visual similarity",
            "A related finding requires a cited semantic document or image comparison",
            "requires cited semantic comparisons that connect every candidate file"
        ]
        return markers.contains { content.contains($0) }
    }

    private static func isValidInspectionChoice(
        _ decision: AgentDecision,
        action: AgentAction,
        allowedReferences: [String]
    ) -> Bool {
        guard decision.action == action,
              decision.fileReferences.count == 1,
              let reference = decision.fileReferences.first else {
            return false
        }
        return allowedReferences.contains(reference)
    }

    private static func isValidPairChoice(
        _ decision: AgentDecision,
        action: AgentAction,
        allowedPair: [String]
    ) -> Bool {
        decision.action == action
            && Set(decision.fileReferences) == Set(allowedPair)
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

    private func canonicalizeExplicitGlobalComparisonReferences(
        _ decision: AgentDecision,
        localToGlobal: [String: String],
        localGlobalReferences: Set<String>,
        visibleGlobalReferences: Set<String>,
        inspectedGlobalPDFs: Set<String>,
        inspectedGlobalImages: Set<String>,
        comparedDocumentPairKeys: Set<String>,
        comparedImagePairKeys: Set<String>
    ) -> [String]? {
        guard decision.fileReferences.count == 2 else { return nil }

        let canonical = decision.fileReferences.map {
            localToGlobal[$0] ?? $0
        }
        guard canonical != decision.fileReferences,
              Set(canonical).count == 2,
              !Set(canonical).isDisjoint(with: localGlobalReferences) else {
            return nil
        }

        switch decision.action {
        case .compareGlobalFiles:
            return Set(canonical).isSubset(of: visibleGlobalReferences)
                ? canonical
                : nil

        case .compareDocumentContent:
            guard Set(canonical).isSubset(of: inspectedGlobalPDFs),
                  !comparedDocumentPairKeys.contains(Self.pairKey(canonical)) else {
                return nil
            }
            return canonical

        case .compareImageContent:
            guard Set(canonical).isSubset(of: inspectedGlobalImages),
                  !comparedImagePairKeys.contains(Self.pairKey(canonical)) else {
                return nil
            }
            return canonical

        default:
            return nil
        }
    }

    private func replacingAction(
        in decision: AgentDecision,
        with action: AgentAction,
        references: [String],
        reason: String
    ) -> AgentDecision {
        AgentDecision(
            action: action,
            candidateID: decision.candidateID,
            fileReferences: references,
            reason: reason,
            finding: nil
        )
    }

    private func replacingReferences(
        in decision: AgentDecision,
        with references: [String]
    ) -> AgentDecision {
        AgentDecision(
            action: decision.action,
            candidateID: decision.candidateID,
            fileReferences: references,
            reason: decision.reason,
            finding: decision.finding
        )
    }

    private func exactlyOne(_ references: [String]) -> [String]? {
        references.count == 1 ? references : nil
    }

    private static func pairKey(_ references: [String]) -> String {
        references.sorted().joined(separator: "|")
    }
}
