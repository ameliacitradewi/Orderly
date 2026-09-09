import Foundation

/// Repairs only missing tool arguments when there is exactly one safe, typed choice.
/// It may also canonicalize an explicitly supplied local F reference to the trusted G
/// identity of the *same file* for tools whose contract is G-only. This never chooses
/// a different file or changes the model-selected action.
struct AgentDecisionReferenceResolver {
    func resolve(
        _ decision: AgentDecision,
        candidate: AnalysisCandidate,
        environment: AgentEnvironment,
        observations: [AgentObservation]
    ) -> AgentDecision {
        guard decision.action != .inspectCandidate,
              decision.action != .finishCandidate else {
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
