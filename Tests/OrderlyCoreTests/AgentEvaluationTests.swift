import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class AgentEvaluationTests: XCTestCase {
    func testEvaluatorSummarizesCompletedAndPartialCandidateTraces() {
        let first = AnalysisCandidate(
            id: UUID(),
            type: .grouping,
            fileIDs: [UUID()],
            confidence: 1,
            reason: "first"
        )
        let second = AnalysisCandidate(
            id: UUID(),
            type: .grouping,
            fileIDs: [UUID()],
            confidence: 1,
            reason: "second"
        )
        let analysis = AnalysisResult(
            analyzedFolder: URL(fileURLWithPath: "/tmp/orderly-evaluation"),
            totalFiles: 2,
            totalSize: 200,
            fileTypes: [],
            duplicateGroups: [],
            candidates: [first, second],
            analyzedAt: Date(timeIntervalSince1970: 1),
            files: [],
            unreadableHashCount: 0
        )

        var state = AgentState(
            goal: "Fixture",
            pendingCandidates: [second]
        )
        state.status = .investigating
        state.observations = [
            AgentObservation(
                type: .candidate,
                candidateID: first.id,
                content: "first overview"
            ),
            AgentObservation(
                type: .imageContent,
                candidateID: first.id,
                content: "first image inspected"
            ),
            AgentObservation(
                type: .error,
                candidateID: first.id,
                content: "Rejected repeated tool request: inspectImageContent:F1."
            ),
            AgentObservation(
                type: .candidate,
                candidateID: second.id,
                content: "second overview"
            )
        ]
        state.executedToolCalls = [
            AgentToolCallSignature(
                action: .inspectCandidate,
                candidateID: first.id,
                fileReferences: []
            ),
            AgentToolCallSignature(
                action: .inspectImageContent,
                candidateID: first.id,
                fileReferences: ["F1"]
            ),
            AgentToolCallSignature(
                action: .inspectCandidate,
                candidateID: second.id,
                fileReferences: []
            )
        ]
        state.findings = [
            AgentFinding(
                candidateID: first.id,
                relationship: .uncertain,
                summary: "Review the first candidate.",
                evidence: [
                    AgentEvidenceReference(
                        observationID: state.observations[1].id,
                        description: "The image was inspected."
                    )
                ],
                proposals: [
                    AgentFileProposal(
                        fileReference: "F1",
                        disposition: .review,
                        reason: "Insufficient cleanup evidence."
                    )
                ],
                confidence: 0.7
            )
        ]

        let report = AgentEvaluator().evaluate(
            state: state,
            analysis: analysis
        )

        XCTAssertEqual(report.candidateCount, 2)
        XCTAssertEqual(report.findingCount, 1)
        XCTAssertEqual(report.completionRate, 0.5, accuracy: 0.0001)
        XCTAssertEqual(report.candidateFailureCount, 0)
        XCTAssertEqual(report.agentSuccessRate, 1, accuracy: 0.0001)
        XCTAssertEqual(report.fallbackRate, 0, accuracy: 0.0001)
        XCTAssertEqual(report.totalAgentSteps, 5)
        XCTAssertEqual(report.maxStepsPerCandidate, 4)
        XCTAssertEqual(report.averageStepsPerCandidate, 2.5, accuracy: 0.0001)
        XCTAssertEqual(report.toolCallCount, 3)
        XCTAssertEqual(report.toolCallsByAction["inspectCandidate"], 2)
        XCTAssertEqual(report.toolCallsByAction["inspectImageContent"], 1)
        XCTAssertEqual(report.observationCount, 4)
        XCTAssertEqual(report.errorObservationCount, 1)
        XCTAssertEqual(report.repeatedToolRejectionCount, 1)
        XCTAssertEqual(report.invalidOrFeedbackObservationRate, 0.25, accuracy: 0.0001)
        XCTAssertEqual(report.proposalCount, 1)
        XCTAssertEqual(report.reviewProposalCount, 1)
        XCTAssertEqual(report.trashProposalCount, 0)
        XCTAssertTrue(report.debugSummary().contains("completionRate=0.500"))
        XCTAssertTrue(report.debugSummary().contains("agentSuccessRate=1.000"))
    }

    func testEvaluatorSeparatesCompletedFallbackFromAgentSuccess() {
        let candidate = AnalysisCandidate(
            id: UUID(),
            type: .grouping,
            fileIDs: [UUID()],
            confidence: 1,
            reason: "fallback"
        )
        let analysis = AnalysisResult(
            analyzedFolder: URL(fileURLWithPath: "/tmp/orderly-fallback-evaluation"),
            totalFiles: 1,
            totalSize: 1,
            fileTypes: [],
            duplicateGroups: [],
            candidates: [candidate],
            analyzedAt: Date(timeIntervalSince1970: 1),
            files: [],
            unreadableHashCount: 0
        )
        let observation = AgentObservation(
            type: .candidate,
            candidateID: candidate.id,
            content: "safe fallback"
        )
        var state = AgentState(goal: "Fallback", pendingCandidates: [])
        state.status = .completed
        state.observations = [observation]
        state.findings = [
            AgentFinding(
                candidateID: candidate.id,
                relationship: .uncertain,
                summary: "Fallback",
                evidence: [
                    AgentEvidenceReference(
                        observationID: observation.id,
                        description: "Fallback activated."
                    )
                ],
                proposals: [],
                confidence: 0
            )
        ]
        state.candidateFailures = [
            AgentCandidateFailure(
                candidateID: candidate.id,
                errorType: "FixtureError",
                message: "fixture"
            )
        ]

        let report = AgentEvaluator().evaluate(
            state: state,
            analysis: analysis
        )

        XCTAssertEqual(report.completionRate, 1, accuracy: 0.0001)
        XCTAssertEqual(report.candidateFailureCount, 1)
        XCTAssertEqual(report.agentSuccessRate, 0, accuracy: 0.0001)
        XCTAssertEqual(report.fallbackRate, 1, accuracy: 0.0001)
    }

    func testEvaluatorHandlesEmptyAnalysis() {
        let analysis = AnalysisResult(
            analyzedFolder: URL(fileURLWithPath: "/tmp/orderly-empty-evaluation"),
            totalFiles: 0,
            totalSize: 0,
            fileTypes: [],
            duplicateGroups: [],
            candidates: [],
            analyzedAt: Date(timeIntervalSince1970: 1),
            files: [],
            unreadableHashCount: 0
        )
        var state = AgentState(goal: "Empty", pendingCandidates: [])
        state.status = .completed

        let report = AgentEvaluator().evaluate(
            state: state,
            analysis: analysis
        )

        XCTAssertEqual(report.completionRate, 1)
        XCTAssertEqual(report.agentSuccessRate, 1)
        XCTAssertEqual(report.fallbackRate, 0)
        XCTAssertEqual(report.totalAgentSteps, 0)
        XCTAssertEqual(report.averageStepsPerCandidate, 0)
        XCTAssertEqual(report.invalidOrFeedbackObservationRate, 0)
    }
}
