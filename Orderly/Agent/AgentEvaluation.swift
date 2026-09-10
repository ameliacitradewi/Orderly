import Foundation

/// Local, telemetry-free quality metrics for one completed (or partially completed)
/// agent run. This intentionally measures orchestration behavior only; it does not
/// make cleanup decisions or weaken any validator boundary.
struct AgentEvaluationReport: Codable, Sendable, Equatable {
    let candidateCount: Int
    let findingCount: Int
    let completionRate: Double
    let candidateFailureCount: Int
    let agentSuccessRate: Double
    let totalAgentSteps: Int
    let maxStepsPerCandidate: Int
    let averageStepsPerCandidate: Double
    let toolCallCount: Int
    let toolCallsByAction: [String: Int]
    let observationCount: Int
    let errorObservationCount: Int
    let repeatedToolRejectionCount: Int
    let proposalCount: Int
    let reviewProposalCount: Int
    let trashProposalCount: Int

    var invalidOrFeedbackObservationRate: Double {
        guard observationCount > 0 else { return 0 }
        return Double(errorObservationCount) / Double(observationCount)
    }

    var fallbackRate: Double {
        guard candidateCount > 0 else { return 0 }
        return Double(candidateFailureCount) / Double(candidateCount)
    }
}

struct AgentEvaluator {
    func evaluate(
        state: AgentState,
        analysis: AnalysisResult
    ) -> AgentEvaluationReport {
        let toolCalls = Array(state.executedToolCalls)
        let toolCallsByAction = Dictionary(
            grouping: toolCalls,
            by: { $0.action.rawValue }
        ).mapValues(\.count)
        let proposals = state.findings.flatMap(\.proposals)
        let errorObservations = state.observations.filter { $0.type == .error }
        let repeatedToolRejections = errorObservations.filter {
            $0.content.contains("Rejected repeated tool request:")
        }

        // Every non-fatal investigation action produces exactly one observation.
        // A successful finishCandidate produces the finding instead. Therefore
        // observations + findings is a stable run-level step count without adding
        // mutable instrumentation to the safety-critical agent loop.
        let stepsByCandidate: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: analysis.candidates.map { candidate in
                let observationSteps = state.observations.filter {
                    $0.candidateID == candidate.id
                }.count
                let finishSteps = state.findings.contains {
                    $0.candidateID == candidate.id
                } ? 1 : 0
                return (candidate.id, observationSteps + finishSteps)
            }
        )
        let totalSteps = stepsByCandidate.values.reduce(0, +)
        let candidateCount = analysis.candidates.count
        let completionRate = candidateCount == 0
            ? 1
            : Double(state.findings.count) / Double(candidateCount)
        let candidateFailureCount = state.candidateFailures.count
        let successfulCandidates = max(0, candidateCount - candidateFailureCount)
        let agentSuccessRate = candidateCount == 0
            ? 1
            : Double(successfulCandidates) / Double(candidateCount)
        let averageSteps = candidateCount == 0
            ? 0
            : Double(totalSteps) / Double(candidateCount)

        return AgentEvaluationReport(
            candidateCount: candidateCount,
            findingCount: state.findings.count,
            completionRate: completionRate,
            candidateFailureCount: candidateFailureCount,
            agentSuccessRate: agentSuccessRate,
            totalAgentSteps: totalSteps,
            maxStepsPerCandidate: stepsByCandidate.values.max() ?? 0,
            averageStepsPerCandidate: averageSteps,
            toolCallCount: toolCalls.count,
            toolCallsByAction: toolCallsByAction,
            observationCount: state.observations.count,
            errorObservationCount: errorObservations.count,
            repeatedToolRejectionCount: repeatedToolRejections.count,
            proposalCount: proposals.count,
            reviewProposalCount: proposals.filter { $0.disposition == .review }.count,
            trashProposalCount: proposals.filter { $0.disposition == .trash }.count
        )
    }
}

extension AgentEvaluationReport {
    func debugSummary() -> String {
        let actionSummary = toolCallsByAction
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")

        return """
        candidates=\(candidateCount)
        findings=\(findingCount)
        completionRate=\(Self.number(completionRate))
        isolatedCandidateFailures=\(candidateFailureCount)
        agentSuccessRate=\(Self.number(agentSuccessRate))
        fallbackRate=\(Self.number(fallbackRate))
        agentSteps=\(totalAgentSteps)
        maxStepsPerCandidate=\(maxStepsPerCandidate)
        averageStepsPerCandidate=\(Self.number(averageStepsPerCandidate))
        toolCalls=\(toolCallCount)
        toolCallsByAction=\(actionSummary.isEmpty ? "none" : actionSummary)
        observations=\(observationCount)
        errorObservations=\(errorObservationCount)
        invalidOrFeedbackObservationRate=\(Self.number(invalidOrFeedbackObservationRate))
        repeatedToolRejections=\(repeatedToolRejectionCount)
        proposals=\(proposalCount)
        reviewProposals=\(reviewProposalCount)
        trashProposals=\(trashProposalCount)
        """
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
