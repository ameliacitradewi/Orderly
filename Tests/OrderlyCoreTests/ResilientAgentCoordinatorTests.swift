import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class ResilientAgentCoordinatorTests: XCTestCase {
    private enum StubError: Error {
        case plannedFailure
    }

    private final class FailFirstCandidateLLM: LLMService {
        private let failingCandidateID: UUID
        private let succeedingCandidateID: UUID
        private var succeedingCalls = 0

        init(failingCandidateID: UUID, succeedingCandidateID: UUID) {
            self.failingCandidateID = failingCandidateID
            self.succeedingCandidateID = succeedingCandidateID
        }

        func generate(prompt: String) async throws -> String {
            if prompt.contains(failingCandidateID.uuidString) {
                throw StubError.plannedFailure
            }

            guard prompt.contains(succeedingCandidateID.uuidString) else {
                throw StubError.plannedFailure
            }

            succeedingCalls += 1
            if succeedingCalls == 1 {
                return try encode(
                    AgentDecision(
                        action: .inspectCandidate,
                        candidateID: succeedingCandidateID,
                        fileReferences: [],
                        reason: "Inspect the candidate first."
                    )
                )
            }

            guard let observationID = latestFactualObservationID(in: prompt) else {
                throw StubError.plannedFailure
            }

            let finding = AgentFinding(
                candidateID: succeedingCandidateID,
                relationship: .grouping,
                summary: "The single file remains a category grouping candidate.",
                evidence: [
                    AgentEvidenceReference(
                        observationID: observationID,
                        description: "The candidate overview contains the local file and its allowed dispositions."
                    )
                ],
                proposals: [
                    AgentFileProposal(
                        fileReference: "F1",
                        disposition: .review,
                        reason: "Review the file before deciding whether to organize it."
                    )
                ],
                confidence: 0.7
            )
            return try encode(
                AgentDecision(
                    action: .finishCandidate,
                    candidateID: succeedingCandidateID,
                    fileReferences: [],
                    reason: "Enough evidence is available.",
                    finding: finding
                )
            )
        }

        private func encode(_ decision: AgentDecision) throws -> String {
            let data = try JSONEncoder().encode(decision)
            return String(decoding: data, as: UTF8.self)
        }

        private func latestFactualObservationID(in prompt: String) -> UUID? {
            var pending: UUID?
            var latest: UUID?

            for line in prompt.split(separator: "\n") {
                let value = line.trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("id=") {
                    pending = UUID(uuidString: String(value.dropFirst(3)))
                } else if value.hasPrefix("type=") {
                    if value != "type=error" {
                        latest = pending
                    }
                    pending = nil
                }
            }

            return latest
        }
    }

    func testCandidateFailureFallsBackAndLaterCandidateStillCompletes() async throws {
        let fixture = makeFixture()
        let llm = FailFirstCandidateLLM(
            failingCandidateID: fixture.candidates[0].id,
            succeedingCandidateID: fixture.candidates[1].id
        )
        let coordinator = ResilientAgentCoordinator(
            agent: OrderlyAgent(
                llm: llm,
                toolRouter: ToolRouter()
            )
        )

        let state = try await coordinator.run(
            analysis: fixture.analysis,
            evidence: fixture.evidence
        )

        XCTAssertEqual(state.status, .completed)
        XCTAssertTrue(state.pendingCandidates.isEmpty)
        XCTAssertEqual(state.findings.count, 2)
        XCTAssertEqual(state.candidateFailures.count, 1)
        XCTAssertEqual(
            state.candidateFailures.first?.candidateID,
            fixture.candidates[0].id
        )

        let fallback = try XCTUnwrap(
            state.findings.first { $0.candidateID == fixture.candidates[0].id }
        )
        XCTAssertEqual(fallback.relationship, .uncertain)
        XCTAssertEqual(fallback.confidence, 0)
        XCTAssertEqual(fallback.proposals.count, 1)
        XCTAssertEqual(fallback.proposals[0].disposition, .review)
        XCTAssertFalse(
            fallback.proposals.contains { $0.disposition == .trash }
        )

        let successful = try XCTUnwrap(
            state.findings.first { $0.candidateID == fixture.candidates[1].id }
        )
        XCTAssertEqual(successful.relationship, .grouping)

        let report = AgentEvaluator().evaluate(
            state: state,
            analysis: fixture.analysis
        )
        XCTAssertEqual(report.completionRate, 1, accuracy: 0.0001)
        XCTAssertEqual(report.candidateFailureCount, 1)
        XCTAssertEqual(report.agentSuccessRate, 0.5, accuracy: 0.0001)
        XCTAssertEqual(report.fallbackRate, 0.5, accuracy: 0.0001)
    }

    func testFallbackKeepsFileWhenReviewIsUnavailable() async throws {
        let candidate = AnalysisCandidate(
            id: UUID(),
            type: .duplicate,
            fileIDs: [UUID()],
            confidence: 1,
            reason: "keeper fixture"
        )
        let root = URL(fileURLWithPath: "/tmp/orderly-resilient-keeper")
        let file = FileMetadata(
            id: candidate.fileIDs[0],
            url: root.appendingPathComponent("keeper.txt"),
            name: "keeper.txt",
            extensionName: "txt",
            size: 10,
            createdAt: nil,
            modifiedAt: Date(timeIntervalSince1970: 1),
            accessedAt: nil,
            isDirectory: false,
            isHidden: false,
            uti: nil
        )
        let candidateEvidence = CandidateEvidence(
            candidateID: candidate.id,
            files: [
                CandidateFileEvidence(
                    fileID: file.id,
                    reference: "F1",
                    name: file.name,
                    tag: .document,
                    size: file.size,
                    modifiedAt: file.modifiedAt,
                    relativePath: file.name,
                    allowedDispositions: [.keep],
                    isInstallerCandidate: false,
                    duplicateCopyCount: 1,
                    duplicateKeeperName: file.name,
                    duplicateKeeperModifiedAt: file.modifiedAt
                )
            ]
        )
        let analysis = AnalysisResult(
            analyzedFolder: root,
            totalFiles: 1,
            totalSize: file.size,
            fileTypes: [],
            duplicateGroups: [],
            candidates: [candidate],
            analyzedAt: Date(timeIntervalSince1970: 2),
            files: [file],
            unreadableHashCount: 0
        )
        let coordinator = ResilientAgentCoordinator(
            agent: OrderlyAgent(
                llm: AlwaysFailLLM(),
                toolRouter: ToolRouter()
            )
        )

        let state = try await coordinator.run(
            analysis: analysis,
            evidence: [candidateEvidence]
        )

        XCTAssertEqual(state.findings.first?.relationship, .uncertain)
        XCTAssertEqual(state.findings.first?.proposals.first?.disposition, .keep)
        XCTAssertEqual(state.candidateFailures.count, 1)
    }

    private final class AlwaysFailLLM: LLMService {
        func generate(prompt: String) async throws -> String {
            throw StubError.plannedFailure
        }
    }

    private func makeFixture() -> (
        analysis: AnalysisResult,
        evidence: [CandidateEvidence],
        candidates: [AnalysisCandidate]
    ) {
        let root = URL(fileURLWithPath: "/tmp/orderly-resilient-agent")
        let candidates = (0..<2).map { index in
            AnalysisCandidate(
                id: UUID(),
                type: .grouping,
                fileIDs: [UUID()],
                confidence: 1,
                reason: "Candidate \(index + 1)"
            )
        }
        let files = candidates.enumerated().map { index, candidate in
            FileMetadata(
                id: candidate.fileIDs[0],
                url: root.appendingPathComponent("file-\(index + 1).txt"),
                name: "file-\(index + 1).txt",
                extensionName: "txt",
                size: Int64(10 + index),
                createdAt: nil,
                modifiedAt: Date(timeIntervalSince1970: Double(index + 1)),
                accessedAt: nil,
                isDirectory: false,
                isHidden: false,
                uti: nil
            )
        }
        let evidence = zip(candidates, files).map { candidate, file in
            CandidateEvidence(
                candidateID: candidate.id,
                files: [
                    CandidateFileEvidence(
                        fileID: file.id,
                        reference: "F1",
                        name: file.name,
                        tag: .document,
                        size: file.size,
                        modifiedAt: file.modifiedAt,
                        relativePath: file.name,
                        allowedDispositions: [.keep, .move, .review],
                        isInstallerCandidate: false,
                        duplicateCopyCount: 0,
                        duplicateKeeperName: nil,
                        duplicateKeeperModifiedAt: nil
                    )
                ]
            )
        }
        let analysis = AnalysisResult(
            analyzedFolder: root,
            totalFiles: files.count,
            totalSize: files.reduce(0) { $0 + $1.size },
            fileTypes: [],
            duplicateGroups: [],
            candidates: candidates,
            analyzedAt: Date(timeIntervalSince1970: 10),
            files: files,
            unreadableHashCount: 0
        )
        return (analysis, evidence, candidates)
    }
}
