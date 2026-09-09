import Foundation

/// Repairs only missing tool arguments when there is exactly one safe, typed choice.
/// The model still chooses the action; this layer never chooses between competing files.
struct AgentDecisionReferenceResolver {
    func resolve(
        _ decision: AgentDecision,
        candidate: AnalysisCandidate,
        environment: AgentEnvironment,
        observations: [AgentObservation]
    ) -> AgentDecision {
        guard decision.action != .inspectCandidate,
              decision.action != .finishCandidate,
              decision.fileReferences.isEmpty else {
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

        return AgentDecision(
            action: decision.action,
            candidateID: decision.candidateID,
            fileReferences: repairedReferences,
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
