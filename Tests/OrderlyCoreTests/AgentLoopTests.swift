import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class AgentLoopTests: XCTestCase {
    private static let evidencePlaceholderID = UUID(
        uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"
    )!

    private final class ScriptedLLM: LLMService {
        private var responses: [String]
        private(set) var prompts: [String] = []

        init(responses: [String]) {
            self.responses = responses
        }

        func generate(prompt: String) async throws -> String {
            prompts.append(prompt)
            guard !responses.isEmpty else {
                throw ScriptedLLMError.missingResponse
            }

            let response = responses.removeFirst()
            let latestObservationID = prompt
                .split(separator: "\n")
                .compactMap { line -> UUID? in
                    let value = line.trimmingCharacters(in: .whitespaces)
                    guard value.hasPrefix("id=") else { return nil }
                    return UUID(uuidString: String(value.dropFirst(3)))
                }
                .last

            guard let latestObservationID else { return response }
            return response.replacingOccurrences(
                of: AgentLoopTests.evidencePlaceholderID.uuidString,
                with: latestObservationID.uuidString
            )
        }
    }

    private final class StubContentInspectionService:
        ContentInspectionService,
        @unchecked Sendable {
        private(set) var calls: [URL] = []

        func inspectPDF(
            at url: URL,
            fileReference: String,
            maxExcerptCharacters: Int
        ) throws -> ContentObservation {
            calls.append(url)
            return ContentObservation(
                fileReference: fileReference,
                contentType: "application/pdf",
                pageCount: 3,
                extractedCharacterCount: 120,
                excerpt: "Annual Financial Report 2026 revenue and operating results.",
                truncated: false
            )
        }
    }

    private enum ScriptedLLMError: Error {
        case missingResponse
    }

    private func fixture(
        candidateCount: Int = 1
    ) -> (
        analysis: AnalysisResult,
        evidence: [CandidateEvidence],
        candidates: [AnalysisCandidate]
    ) {
        let candidates = (0..<candidateCount).map { index in
            AnalysisCandidate(
                id: UUID(),
                type: .grouping,
                fileIDs: [UUID()],
                confidence: 1,
                reason: "Candidate \(index + 1)"
            )
        }
        let evidence = candidates.enumerated().map { index, candidate in
            CandidateEvidence(
                candidateID: candidate.id,
                files: [
                    CandidateFileEvidence(
                        fileID: candidate.fileIDs[0],
                        reference: "F1",
                        name: "file-\(index + 1).pdf",
                        tag: .document,
                        size: Int64(index + 10),
                        modifiedAt: Date(timeIntervalSince1970: Double(index + 1)),
                        relativePath: "file-\(index + 1).pdf",
                        allowedDispositions: [.keep, .move, .review],
                        isInstallerCandidate: false,
                        duplicateCopyCount: 0,
                        duplicateKeeperName: nil,
                        duplicateKeeperModifiedAt: nil
                    )
                ]
            )
        }
        let root = URL(fileURLWithPath: "/tmp/agent-loop-fixture")
        let files = candidates.enumerated().map { index, candidate in
            FileMetadata(
                id: candidate.fileIDs[0],
                url: root.appendingPathComponent("file-\(index + 1).pdf"),
                name: "file-\(index + 1).pdf",
                extensionName: "pdf",
                size: Int64(index + 10),
                createdAt: nil,
                modifiedAt: Date(timeIntervalSince1970: Double(index + 1)),
                accessedAt: nil,
                isDirectory: false,
                isHidden: false,
                uti: nil
            )
        }
        let analysis = AnalysisResult(
            analyzedFolder: root,
            totalFiles: candidateCount,
            totalSize: Int64(candidateCount),
            fileTypes: [],
            duplicateGroups: [],
            candidates: candidates,
            analyzedAt: Date(timeIntervalSince1970: 10),
            files: files,
            unreadableHashCount: 0
        )
        return (analysis, evidence, candidates)
    }

    private func finding(
        candidateID: UUID,
        summary: String = "The candidate is a document grouping.",
        confidence: Double = 0.9,
        evidenceDescription: String = "The file is tagged Documents."
    ) -> AgentFinding {
        AgentFinding(
            candidateID: candidateID,
            relationship: .grouping,
            summary: summary,
            evidence: [
                AgentEvidenceReference(
                    observationID: Self.evidencePlaceholderID,
                    description: evidenceDescription
                )
            ],
            proposals: [
                AgentFileProposal(
                    fileReference: "F1",
                    disposition: .move,
                    reason: "Organize the document."
                )
            ],
            confidence: confidence
        )
    }

    private func response(
        action: AgentAction,
        candidateID: UUID,
        references: [String] = [],
        finding: AgentFinding? = nil
    ) throws -> String {
        let decision = AgentDecision(
            action: action,
            candidateID: candidateID,
            fileReferences: references,
            reason: "Scripted next step",
            finding: finding
        )
        let data = try JSONEncoder().encode(decision)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    func testOuterLoopInvestigatesEveryCandidateAndCarriesOnlyCurrentContext() async throws {
        let fixture = fixture(candidateCount: 2)
        let first = fixture.candidates[0]
        let second = fixture.candidates[1]
        let llm = ScriptedLLM(responses: [
            try response(action: .inspectCandidate, candidateID: first.id),
            try response(
                action: .finishCandidate,
                candidateID: first.id,
                finding: finding(
                    candidateID: first.id,
                    summary: "The first candidate is a document grouping.",
                    confidence: 0.8
                )
            ),
            try response(action: .inspectCandidate, candidateID: second.id),
            try response(
                action: .finishCandidate,
                candidateID: second.id,
                finding: finding(
                    candidateID: second.id,
                    summary: "The second candidate is a document grouping."
                )
            )
        ])

        let state = try await OrderlyAgent(llm: llm).run(
            analysis: fixture.analysis,
            evidence: fixture.evidence
        )

        XCTAssertEqual(state.status, .completed)
        XCTAssertNil(state.currentCandidate)
        XCTAssertTrue(state.pendingCandidates.isEmpty)
        XCTAssertEqual(state.findings.map(\.candidateID), [first.id, second.id])
        XCTAssertEqual(state.observations.count, 2)
        XCTAssertEqual(llm.prompts.count, 4)

        XCTAssertTrue(llm.prompts[0].contains("inspectCandidate is available"))
        XCTAssertTrue(llm.prompts[1].contains("inspectCandidate has already been used"))
        XCTAssertTrue(llm.prompts[1].contains("Observation:"))
        XCTAssertTrue(llm.prompts[1].contains("name=file-1.pdf"))
        XCTAssertTrue(llm.prompts[2].contains("PREVIOUS OBSERVATIONS:\n\nNone."))
        XCTAssertFalse(llm.prompts[2].contains("name=file-1.pdf"))
        XCTAssertTrue(llm.prompts[3].contains("name=file-2.pdf"))
    }

    func testAgentRejectsDecisionForAnotherCandidate() async throws {
        let fixture = fixture()
        let llm = ScriptedLLM(responses: [
            try response(
                action: .inspectCandidate,
                candidateID: UUID()
            )
        ])

        do {
            _ = try await OrderlyAgent(llm: llm).run(
                analysis: fixture.analysis,
                evidence: fixture.evidence
            )
            XCTFail("Expected wrongCandidate")
        } catch {
            guard case AgentError.wrongCandidate = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(llm.prompts.count, 1)
    }

    func testAgentStopsAfterEightToolIterations() async throws {
        let fixture = fixture()
        let candidate = fixture.candidates[0]
        let repeated = try response(
            action: .inspectCandidate,
            candidateID: candidate.id
        )
        let llm = ScriptedLLM(
            responses: Array(repeating: repeated, count: 8)
        )

        do {
            _ = try await OrderlyAgent(llm: llm).run(
                analysis: fixture.analysis,
                evidence: fixture.evidence
            )
            XCTFail("Expected maximumIterationsReached")
        } catch {
            guard case AgentError.maximumIterationsReached = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(llm.prompts.count, 8)
        XCTAssertTrue(
            llm.prompts[2].contains("Rejected repeated tool request")
        )
        XCTAssertTrue(llm.prompts[7].contains("MUST choose finishCandidate"))
    }

    func testFinishRequiresFindingAndValidConfidence() async throws {
        let fixture = fixture()
        let candidate = fixture.candidates[0]

        let missingFindingLLM = ScriptedLLM(responses: [
            try response(
                action: .finishCandidate,
                candidateID: candidate.id
            )
        ])
        do {
            _ = try await OrderlyAgent(llm: missingFindingLLM).run(
                analysis: fixture.analysis,
                evidence: fixture.evidence
            )
            XCTFail("Expected finishWithoutFinding")
        } catch {
            guard case AgentError.finishWithoutFinding = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let invalidConfidenceLLM = ScriptedLLM(responses: [
            try response(
                action: .finishCandidate,
                candidateID: candidate.id,
                finding: finding(
                    candidateID: candidate.id,
                    confidence: 1.1
                )
            )
        ])
        do {
            _ = try await OrderlyAgent(llm: invalidConfidenceLLM).run(
                analysis: fixture.analysis,
                evidence: fixture.evidence
            )
            XCTFail("Expected invalidConfidence")
        } catch {
            guard case AgentError.invalidConfidence = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testAgentRejectsUnsafeStructuredFinding() async throws {
        let fixture = fixture()
        let candidate = fixture.candidates[0]
        let unsafeFinding = AgentFinding(
            candidateID: candidate.id,
            relationship: .grouping,
            summary: "Delete a unique document.",
            evidence: [
                AgentEvidenceReference(
                    observationID: Self.evidencePlaceholderID,
                    description: "The file is unique."
                )
            ],
            proposals: [
                AgentFileProposal(
                    fileReference: "F1",
                    disposition: .trash,
                    reason: "Unneeded."
                )
            ],
            confidence: 0.9
        )
        let llm = ScriptedLLM(responses: [
            try response(
                action: .finishCandidate,
                candidateID: candidate.id,
                finding: unsafeFinding
            )
        ])

        do {
            _ = try await OrderlyAgent(llm: llm).run(
                analysis: fixture.analysis,
                evidence: fixture.evidence
            )
            XCTFail("Expected invalidFinding")
        } catch {
            guard case AgentError.invalidFinding(let issues) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(
                issues.contains("trash is not allowed for F1.")
            )
        }
    }

    func testAgentInspectsAmbiguousPDFThenUsesContentToMove() async throws {
        let fixture = fixture()
        let candidate = fixture.candidates[0]
        let llm = ScriptedLLM(responses: [
            try response(
                action: .inspectCandidate,
                candidateID: candidate.id
            ),
            try response(
                action: .inspectPDFContent,
                candidateID: candidate.id,
                references: ["F1"]
            ),
            try response(
                action: .finishCandidate,
                candidateID: candidate.id,
                finding: finding(
                    candidateID: candidate.id,
                    summary: "The PDF is a financial report suitable for Documents.",
                    confidence: 0.93,
                    evidenceDescription: "The PDF excerpt identifies an Annual Financial Report."
                )
            )
        ])
        let contentService = StubContentInspectionService()
        let agent = OrderlyAgent(
            llm: llm,
            toolRouter: ToolRouter(
                contentInspectionService: contentService
            )
        )

        let state = try await agent.run(
            analysis: fixture.analysis,
            evidence: fixture.evidence
        )

        XCTAssertEqual(contentService.calls.count, 1)
        XCTAssertEqual(state.findings.first?.proposals.first?.disposition, .move)
        XCTAssertTrue(llm.prompts[2].contains("type=content"))
        XCTAssertTrue(llm.prompts[2].contains("Annual Financial Report 2026"))
        XCTAssertEqual(
            state.findings.first?.evidence.first?.observationID,
            state.observations.last?.id
        )
    }

    func testRepeatedPDFInspectionIsRejectedWithoutReadingAgain() async throws {
        let fixture = fixture()
        let candidate = fixture.candidates[0]
        let llm = ScriptedLLM(responses: [
            try response(action: .inspectCandidate, candidateID: candidate.id),
            try response(
                action: .inspectPDFContent,
                candidateID: candidate.id,
                references: ["F1"]
            ),
            try response(
                action: .inspectPDFContent,
                candidateID: candidate.id,
                references: ["F1"]
            ),
            try response(
                action: .finishCandidate,
                candidateID: candidate.id,
                finding: finding(candidateID: candidate.id)
            )
        ])
        let contentService = StubContentInspectionService()

        let state = try await OrderlyAgent(
            llm: llm,
            toolRouter: ToolRouter(
                contentInspectionService: contentService
            )
        ).run(
            analysis: fixture.analysis,
            evidence: fixture.evidence
        )

        XCTAssertEqual(contentService.calls.count, 1)
        XCTAssertEqual(state.executedToolCalls.count, 2)
        XCTAssertTrue(state.observations.contains {
            $0.type == .error
                && $0.content.contains("already been performed")
        })
    }

    func testDecisionDecoderAcceptsFencedStructuredJSON() throws {
        let candidateID = UUID()
        let json = try response(
            action: .finishCandidate,
            candidateID: candidateID,
            finding: finding(
                candidateID: candidateID,
                summary: "Enough evidence."
            )
        )
        let decoded = try AgentDecisionDecoder().decode(
            "Some preface\n```json\n\(json)\n```"
        )

        XCTAssertEqual(decoded.action, .finishCandidate)
        XCTAssertEqual(decoded.candidateID, candidateID)
        XCTAssertEqual(decoded.finding?.summary, "Enough evidence.")
        XCTAssertEqual(decoded.finding?.confidence, 0.9)
    }
}
