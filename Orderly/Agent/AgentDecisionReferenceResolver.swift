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

        let candidatePDFs = Set(
            candidateObservations
                .filter { $0.type == .candidate }
                .flatMap { $0.pdfFileReferences ?? [] }
        )
        let availableLocalPDFs = candidatePDFs
            .subtracting(inspectedLocalPDFs)
            .subtracting(unavailablePDFs)
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

        let repairedReferences: [String]?
        switch decision.action {
        case .inspectFile, .findRelatedFiles:
            repairedReferences = exactlyOne(localReferences)

        case .inspectPDFContent:
            repairedReferences = exactlyOne(availableLocalPDFs)

        case .inspectGlobalFile:
            repairedReferences = exactlyOne(visibleGlobalReferences)

        case .inspectGlobalPDFContent:
            repairedReferences = exactlyOne(availableExternalPDFs)

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
            repairedReferences = inspected.count == 2
                && !Set(inspected).isDisjoint(with: localGlobalReferences)
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
}
