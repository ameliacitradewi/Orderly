import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class DocumentComparisonTests: XCTestCase {
    private final class StubContentService: ContentInspectionService, @unchecked Sendable {
        private let excerpts: [String: String]
        private(set) var calls: [String] = []

        init(excerpts: [String: String]) {
            self.excerpts = excerpts
        }

        func inspectPDF(
            at url: URL,
            fileReference: String,
            maxExcerptCharacters: Int
        ) throws -> ContentObservation {
            calls.append(fileReference)
            let text = excerpts[fileReference] ?? ""
            return ContentObservation(
                fileReference: fileReference,
                contentType: "application/pdf",
                pageCount: 1,
                extractedCharacterCount: text.count,
                excerpt: String(text.prefix(maxExcerptCharacters)),
                truncated: text.count > maxExcerptCharacters
            )
        }
    }

    private final class StubSemanticAnalyzer: DocumentSemanticAnalyzing {
        let assessment: DocumentSemanticAssessment
        private(set) var calls = 0

        init(_ assessment: DocumentSemanticAssessment) {
            self.assessment = assessment
        }

        func analyze(
            first: ContentObservation,
            second: ContentObservation,
            deterministic: DeterministicDocumentComparison
        ) async throws -> DocumentSemanticAssessment {
            calls += 1
            return assessment
        }
    }

    private struct Fixture {
        let root: URL
        let analysis: AnalysisResult
        let evidence: [CandidateEvidence]
        let firstCandidate: AnalysisCandidate
        let secondCandidate: AnalysisCandidate
        let firstFile: FileMetadata
        let secondFile: FileMetadata
    }

    private func fixture() -> Fixture {
        let root = URL(fileURLWithPath: "/tmp/orderly-document-comparison-tests")
        let firstID = UUID()
        let secondID = UUID()
        let first = FileMetadata(
            id: firstID,
            url: root.appendingPathComponent("01-proposal-v1.pdf"),
            name: "01-proposal-v1.pdf",
            extensionName: "pdf",
            size: 1_000,
            createdAt: nil,
            modifiedAt: Date(timeIntervalSince1970: 100),
            accessedAt: nil,
            isDirectory: false,
            isHidden: false,
            uti: nil
        )
        let second = FileMetadata(
            id: secondID,
            url: root.appendingPathComponent("02-proposal-final.pdf"),
            name: "02-proposal-final.pdf",
            extensionName: "pdf",
            size: 1_100,
            createdAt: nil,
            modifiedAt: Date(timeIntervalSince1970: 160),
            accessedAt: nil,
            isDirectory: false,
            isHidden: false,
            uti: nil
        )
        let firstCandidate = AnalysisCandidate(
            id: UUID(),
            type: .grouping,
            fileIDs: [firstID],
            confidence: 1,
            reason: "Document category batch"
        )
        let secondCandidate = AnalysisCandidate(
            id: UUID(),
            type: .grouping,
            fileIDs: [secondID],
            confidence: 1,
            reason: "Document category batch"
        )
        let firstEvidence = CandidateEvidence(
            candidateID: firstCandidate.id,
            files: [
                CandidateFileEvidence(
                    fileID: firstID,
                    reference: "F1",
                    name: first.name,
                    tag: .document,
                    size: first.size,
                    modifiedAt: first.modifiedAt,
                    relativePath: first.name,
                    allowedDispositions: [.keep, .move, .review],
                    isInstallerCandidate: false,
                    duplicateCopyCount: 0,
                    duplicateKeeperName: nil,
                    duplicateKeeperModifiedAt: nil
                )
            ]
        )
        let secondEvidence = CandidateEvidence(
            candidateID: secondCandidate.id,
            files: [
                CandidateFileEvidence(
                    fileID: secondID,
                    reference: "F1",
                    name: second.name,
                    tag: .document,
                    size: second.size,
                    modifiedAt: second.modifiedAt,
                    relativePath: second.name,
                    allowedDispositions: [.keep, .move, .review],
                    isInstallerCandidate: false,
                    duplicateCopyCount: 0,
                    duplicateKeeperName: nil,
                    duplicateKeeperModifiedAt: nil
                )
            ]
        )
        let analysis = AnalysisResult(
            analyzedFolder: root,
            totalFiles: 2,
            totalSize: first.size + second.size,
            fileTypes: [],
            duplicateGroups: [],
            candidates: [firstCandidate, secondCandidate],
            analyzedAt: Date(timeIntervalSince1970: 200),
            files: [first, second],
            unreadableHashCount: 0
        )
        return Fixture(
            root: root,
            analysis: analysis,
            evidence: [firstEvidence, secondEvidence],
            firstCandidate: firstCandidate,
            secondCandidate: secondCandidate,
            firstFile: first,
            secondFile: second
        )
    }

    func testDeterministicComparatorSeparatesRevisionLikeAndUnrelatedText() {
        let idA = UUID()
        let idB = UUID()
        let revisionA = ContentObservation(
            fileID: idA,
            localReference: "F1",
            globalReference: "G1",
            contentType: "application/pdf",
            pageCount: 1,
            extractedCharacterCount: 120,
            excerpt: "Project Apollo proposal budget timeline deliverables research methods conclusion",
            truncated: false
        )
        let revisionB = ContentObservation(
            fileID: idB,
            localReference: nil,
            globalReference: "G2",
            contentType: "application/pdf",
            pageCount: 1,
            extractedCharacterCount: 140,
            excerpt: "Project Apollo proposal budget timeline deliverables research methods revised conclusion appendix",
            truncated: false
        )
        let unrelated = ContentObservation(
            fileID: UUID(),
            localReference: nil,
            globalReference: "G3",
            contentType: "application/pdf",
            pageCount: 1,
            extractedCharacterCount: 100,
            excerpt: "Restaurant invoice tax subtotal payment receipt vendor address purchase date",
            truncated: false
        )

        let comparator = DeterministicDocumentComparator()
        let revision = comparator.compare(revisionA, revisionB)
        let different = comparator.compare(revisionA, unrelated)

        XCTAssertGreaterThan(revision.tokenOverlap, different.tokenOverlap)
        XCTAssertGreaterThan(revision.shingleSimilarity, different.shingleSimilarity)
        XCTAssertLessThan(revision.lengthDifference, 0.2)
    }

    func testHybridComparisonUsesObservedPDFContentAndProducesStructuredEvidence() async throws {
        let fixture = fixture()
        let content = StubContentService(excerpts: [
            "F1": "Project Apollo proposal budget timeline deliverables research methods conclusion.",
            "G2": "Project Apollo proposal budget timeline deliverables research methods revised conclusion appendix."
        ])
        let semantic = StubSemanticAnalyzer(
            DocumentSemanticAssessment(
                relationship: .sameDocumentRevision,
                summary: "The second document is a revised version of the same proposal.",
                confidence: 0.94
            )
        )
        let router = ToolRouter(
            contentInspectionService: content,
            documentSemanticAnalyzer: semantic
        )
        let environment = AgentEnvironment(
            analysis: fixture.analysis,
            evidence: fixture.evidence
        )
        let candidateID = fixture.firstCandidate.id

        let overview = try router.execute(
            decision: AgentDecision(
                action: .inspectCandidate,
                candidateID: candidateID,
                fileReferences: [],
                reason: "Inspect candidate"
            ),
            environment: environment
        )
        XCTAssertTrue(overview.globalReferences?.contains("G1") == true)

        let discovery = try router.execute(
            decision: AgentDecision(
                action: .findRelatedFiles,
                candidateID: candidateID,
                fileReferences: ["F1"],
                reason: "Look for another proposal"
            ),
            environment: environment,
            observations: [overview]
        )
        XCTAssertTrue(discovery.globalReferences?.contains("G2") == true)
        XCTAssertTrue(discovery.pdfGlobalReferences?.contains("G2") == true)

        let localContent = try router.execute(
            decision: AgentDecision(
                action: .inspectPDFContent,
                candidateID: candidateID,
                fileReferences: ["F1"],
                reason: "Read local proposal"
            ),
            environment: environment,
            observations: [overview, discovery]
        )
        XCTAssertEqual(localContent.contentObservation?.globalReference, "G1")
        XCTAssertEqual(localContent.contentObservation?.fileID, fixture.firstFile.id)

        let globalContent = try router.execute(
            decision: AgentDecision(
                action: .inspectGlobalPDFContent,
                candidateID: candidateID,
                fileReferences: ["G2"],
                reason: "Read discovered proposal"
            ),
            environment: environment,
            observations: [overview, discovery, localContent]
        )
        XCTAssertEqual(globalContent.contentObservation?.globalReference, "G2")
        XCTAssertNil(globalContent.contentObservation?.localReference)
        XCTAssertEqual(globalContent.contentObservation?.fileID, fixture.secondFile.id)

        let comparison = try await router.executeAsync(
            decision: AgentDecision(
                action: .compareDocumentContent,
                candidateID: candidateID,
                fileReferences: ["G1", "G2"],
                reason: "Determine whether these are revisions"
            ),
            environment: environment,
            observations: [overview, discovery, localContent, globalContent]
        )

        XCTAssertEqual(comparison.type, .documentComparison)
        XCTAssertEqual(
            comparison.documentComparison?.semantic.relationship,
            .sameDocumentRevision
        )
        XCTAssertEqual(comparison.documentComparison?.globalReferences, ["G1", "G2"])
        XCTAssertEqual(semantic.calls, 1)
        XCTAssertEqual(content.calls, ["F1", "G2"])
    }

    func testRelatedFindingRequiresCitedSemanticComparison() async throws {
        let fixture = fixture()
        let content = StubContentService(excerpts: [
            "F1": "Shared proposal body and project plan.",
            "G2": "Shared proposal body and project plan with revisions."
        ])
        let semantic = StubSemanticAnalyzer(
            DocumentSemanticAssessment(
                relationship: .sameDocumentRevision,
                summary: "Revision relationship is supported.",
                confidence: 0.9
            )
        )
        let router = ToolRouter(
            contentInspectionService: content,
            documentSemanticAnalyzer: semantic
        )
        let environment = AgentEnvironment(
            analysis: fixture.analysis,
            evidence: fixture.evidence
        )
        let candidateID = fixture.firstCandidate.id
        let overview = try router.execute(
            decision: AgentDecision(action: .inspectCandidate, candidateID: candidateID,
                                    fileReferences: [], reason: "Inspect"),
            environment: environment
        )
        let discovery = try router.execute(
            decision: AgentDecision(action: .findRelatedFiles, candidateID: candidateID,
                                    fileReferences: ["F1"], reason: "Discover"),
            environment: environment,
            observations: [overview]
        )
        let local = try router.execute(
            decision: AgentDecision(action: .inspectPDFContent, candidateID: candidateID,
                                    fileReferences: ["F1"], reason: "Read local"),
            environment: environment,
            observations: [overview, discovery]
        )
        let external = try router.execute(
            decision: AgentDecision(action: .inspectGlobalPDFContent, candidateID: candidateID,
                                    fileReferences: ["G2"], reason: "Read external"),
            environment: environment,
            observations: [overview, discovery, local]
        )
        let compared = try await router.executeAsync(
            decision: AgentDecision(action: .compareDocumentContent, candidateID: candidateID,
                                    fileReferences: ["G1", "G2"], reason: "Compare"),
            environment: environment,
            observations: [overview, discovery, local, external]
        )

        let proposal = AgentFileProposal(
            fileReference: "F1",
            disposition: .review,
            reason: "A revision relationship exists, but unique revisions are not safe to delete automatically."
        )
        let finding = AgentFinding(
            candidateID: candidateID,
            relationship: .related,
            summary: "The discovered PDF appears to be a revision of the current proposal.",
            evidence: [
                AgentEvidenceReference(
                    observationID: compared.id,
                    description: "Hybrid document comparison classified the pair as the same document revision."
                )
            ],
            proposals: [proposal],
            confidence: 0.9
        )
        let candidateEvidence = try XCTUnwrap(
            environment.evidenceByCandidate[candidateID]
        )
        XCTAssertTrue(
            AgentPlanValidator().validate(
                finding: finding,
                candidate: fixture.firstCandidate,
                evidence: candidateEvidence,
                observations: [overview, discovery, local, external, compared]
            ).isEmpty
        )

        let contentOnlyFinding = AgentFinding(
            candidateID: candidateID,
            relationship: .related,
            summary: "The files are related.",
            evidence: [
                AgentEvidenceReference(
                    observationID: local.id,
                    description: "One PDF was inspected."
                )
            ],
            proposals: [proposal],
            confidence: 0.6
        )
        let issues = AgentPlanValidator().validate(
            finding: contentOnlyFinding,
            candidate: fixture.firstCandidate,
            evidence: candidateEvidence,
            observations: [overview, discovery, local, external]
        )
        XCTAssertTrue(issues.contains {
            $0.contains("requires a cited document comparison")
        })
    }
}
