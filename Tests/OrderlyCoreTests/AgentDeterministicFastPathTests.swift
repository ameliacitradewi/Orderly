import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class AgentDeterministicFastPathTests: XCTestCase {
    private final class NeverLLM: LLMService {
        private(set) var calls = 0

        func generate(prompt: String) async throws -> String {
            calls += 1
            throw TestError.unexpectedLLMCall
        }
    }

    private enum TestError: Error {
        case unexpectedLLMCall
    }

    func testExactDuplicateCompletesWithoutLLMWhenFastPathsEnabled() async throws {
        let fixture = duplicateFixture()
        let llm = NeverLLM()
        let agent = OrderlyAgent(
            llm: llm,
            deterministicFastPaths: true
        )

        let state = try await agent.run(
            analysis: fixture.analysis,
            evidence: [fixture.evidence]
        )

        XCTAssertEqual(llm.calls, 0)
        XCTAssertEqual(state.findings.count, 1)
        XCTAssertEqual(state.observations.count, 2)
        XCTAssertEqual(state.executedToolCalls.count, 2)

        let finding = try XCTUnwrap(state.findings.first)
        XCTAssertEqual(finding.relationship, .exactDuplicate)
        XCTAssertEqual(finding.confidence, 1.0, accuracy: 0.0001)

        let proposals = Dictionary(
            uniqueKeysWithValues: finding.proposals.map {
                ($0.fileReference, $0)
            }
        )
        XCTAssertEqual(proposals["F1"]?.disposition, .keep)
        XCTAssertEqual(proposals["F2"]?.disposition, .trash)
        XCTAssertTrue(proposals["F2"]?.reason.contains("SHA256-verified exact duplicate") == true)
        XCTAssertFalse(proposals["F2"]?.reason.contains("no explicit keep permission") == true)
    }

    func testDeterministicFindingRequiresVerifiedComparison() {
        let fixture = duplicateFixture()
        let planner = AgentDeterministicFindingPlanner()

        let withoutComparison = planner.finding(
            candidate: fixture.candidate,
            evidence: fixture.evidence,
            observations: []
        )
        XCTAssertNil(withoutComparison)

        let falseComparison = AgentObservation(
            type: .comparison,
            candidateID: fixture.candidate.id,
            content: "verifiedDuplicate=false",
            comparison: FileComparisonObservation(
                fileIDs: fixture.candidate.fileIDs,
                verifiedDuplicate: false
            )
        )
        XCTAssertNil(
            planner.finding(
                candidate: fixture.candidate,
                evidence: fixture.evidence,
                observations: [falseComparison]
            )
        )
    }

    private func duplicateFixture() -> (
        analysis: AnalysisResult,
        evidence: CandidateEvidence,
        candidate: AnalysisCandidate
    ) {
        let root = URL(fileURLWithPath: "/tmp/orderly-deterministic-duplicate")
        let groupID = UUID()
        let keeperID = UUID()
        let copyID = UUID()
        let sha = String(repeating: "a", count: 64)

        var keeper = FileMetadata(
            id: keeperID,
            url: root.appendingPathComponent("notes-keeper.txt"),
            name: "notes-keeper.txt",
            extensionName: "txt",
            size: 100,
            createdAt: nil,
            modifiedAt: Date(timeIntervalSince1970: 2),
            accessedAt: nil,
            isDirectory: false,
            isHidden: false,
            uti: nil
        )
        keeper.classification = .document
        keeper.duplicateGroupID = groupID
        keeper.duplicateSHA256 = sha
        keeper.duplicateKeeperID = keeperID
        keeper.duplicateCopyCount = 2

        var copy = FileMetadata(
            id: copyID,
            url: root.appendingPathComponent("notes-copy.txt"),
            name: "notes-copy.txt",
            extensionName: "txt",
            size: 100,
            createdAt: nil,
            modifiedAt: Date(timeIntervalSince1970: 1),
            accessedAt: nil,
            isDirectory: false,
            isHidden: false,
            uti: nil
        )
        copy.classification = .document
        copy.duplicateGroupID = groupID
        copy.duplicateSHA256 = sha
        copy.duplicateKeeperID = keeperID
        copy.duplicateCopyCount = 2

        let candidate = AnalysisCandidate(
            id: UUID(),
            type: .duplicate,
            fileIDs: [keeperID, copyID],
            confidence: 1,
            reason: "Verified duplicate fixture"
        )
        let evidence = CandidateEvidence(
            candidateID: candidate.id,
            files: [
                CandidateFileEvidence(
                    fileID: keeperID,
                    reference: "F1",
                    name: keeper.name,
                    tag: .document,
                    size: keeper.size,
                    modifiedAt: keeper.modifiedAt,
                    relativePath: keeper.name,
                    allowedDispositions: [.keep],
                    isInstallerCandidate: false,
                    duplicateCopyCount: 2,
                    duplicateKeeperName: keeper.name,
                    duplicateKeeperModifiedAt: keeper.modifiedAt
                ),
                CandidateFileEvidence(
                    fileID: copyID,
                    reference: "F2",
                    name: copy.name,
                    tag: .document,
                    size: copy.size,
                    modifiedAt: copy.modifiedAt,
                    relativePath: copy.name,
                    allowedDispositions: [.keep, .trash, .review],
                    isInstallerCandidate: false,
                    duplicateCopyCount: 2,
                    duplicateKeeperName: keeper.name,
                    duplicateKeeperModifiedAt: keeper.modifiedAt
                )
            ]
        )
        let analysis = AnalysisResult(
            analyzedFolder: root,
            totalFiles: 2,
            totalSize: 200,
            fileTypes: [],
            duplicateGroups: [],
            candidates: [candidate],
            analyzedAt: Date(timeIntervalSince1970: 3),
            files: [keeper, copy],
            unreadableHashCount: 0
        )

        return (analysis, evidence, candidate)
    }
}
