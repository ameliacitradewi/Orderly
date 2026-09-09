import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class AgentDecisionReferenceResolverTests: XCTestCase {
    private struct Fixture {
        let candidate: AnalysisCandidate
        let environment: AgentEnvironment
        let localFile: FileMetadata
        let externalFile: FileMetadata
        let localGlobalReference: String
        let externalGlobalReference: String
    }

    private func fixture() throws -> Fixture {
        let root = URL(fileURLWithPath: "/tmp/orderly-reference-resolver")
        let local = FileMetadata(
            id: UUID(),
            url: root.appendingPathComponent("proposal-v1.pdf"),
            name: "proposal-v1.pdf",
            extensionName: "pdf",
            size: 100,
            createdAt: nil,
            modifiedAt: Date(timeIntervalSince1970: 1),
            accessedAt: nil,
            isDirectory: false,
            isHidden: false,
            uti: nil
        )
        let external = FileMetadata(
            id: UUID(),
            url: root.appendingPathComponent("proposal-final.pdf"),
            name: "proposal-final.pdf",
            extensionName: "pdf",
            size: 110,
            createdAt: nil,
            modifiedAt: Date(timeIntervalSince1970: 2),
            accessedAt: nil,
            isDirectory: false,
            isHidden: false,
            uti: nil
        )
        let candidate = AnalysisCandidate(
            id: UUID(),
            type: .grouping,
            fileIDs: [local.id],
            confidence: 1,
            reason: "Fixture"
        )
        let evidence = CandidateEvidence(
            candidateID: candidate.id,
            files: [
                CandidateFileEvidence(
                    fileID: local.id,
                    reference: "F1",
                    name: local.name,
                    tag: .document,
                    size: local.size,
                    modifiedAt: local.modifiedAt,
                    relativePath: local.name,
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
            totalSize: 210,
            fileTypes: [],
            duplicateGroups: [],
            candidates: [candidate],
            analyzedAt: Date(timeIntervalSince1970: 3),
            files: [local, external],
            unreadableHashCount: 0
        )
        let environment = AgentEnvironment(
            analysis: analysis,
            evidence: [evidence]
        )
        let localGlobalReference = try XCTUnwrap(
            environment.globalReferenceByFileID[local.id]
        )
        let externalGlobalReference = try XCTUnwrap(
            environment.globalReferenceByFileID[external.id]
        )
        return Fixture(
            candidate: candidate,
            environment: environment,
            localFile: local,
            externalFile: external,
            localGlobalReference: localGlobalReference,
            externalGlobalReference: externalGlobalReference
        )
    }

    private func decision(_ action: AgentAction) -> AgentDecision {
        AgentDecision(
            action: action,
            candidateID: nil,
            fileReferences: [],
            reason: "Fixture"
        )
    }

    private func inspectedContentObservations(
        fixture: Fixture
    ) -> [AgentObservation] {
        let localContent = ContentObservation(
            fileID: fixture.localFile.id,
            localReference: "F1",
            globalReference: fixture.localGlobalReference,
            contentType: "application/pdf",
            pageCount: 1,
            extractedCharacterCount: 10,
            excerpt: "proposal text",
            truncated: false
        )
        let externalContent = ContentObservation(
            fileID: fixture.externalFile.id,
            localReference: nil,
            globalReference: fixture.externalGlobalReference,
            contentType: "application/pdf",
            pageCount: 1,
            extractedCharacterCount: 12,
            excerpt: "proposal final text",
            truncated: false
        )
        return [
            AgentObservation(
                type: .candidate,
                candidateID: fixture.candidate.id,
                content: "overview",
                globalReferences: [fixture.localGlobalReference]
            ),
            AgentObservation(
                type: .content,
                candidateID: fixture.candidate.id,
                content: "local content",
                contentObservation: localContent,
                globalReferences: [fixture.localGlobalReference]
            ),
            AgentObservation(
                type: .content,
                candidateID: fixture.candidate.id,
                content: "external content",
                contentObservation: externalContent,
                globalReferences: [fixture.externalGlobalReference]
            )
        ]
    }

    func testResolverFillsUniqueLocalReferenceForDiscovery() throws {
        let fixture = try fixture()
        let resolved = AgentDecisionReferenceResolver().resolve(
            decision(.findRelatedFiles),
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: []
        )

        XCTAssertEqual(resolved.fileReferences, ["F1"])
    }

    func testResolverFillsUniqueObservedExternalPDFReference() throws {
        let fixture = try fixture()
        let observations = [
            AgentObservation(
                type: .candidate,
                candidateID: fixture.candidate.id,
                content: "overview",
                globalReferences: [fixture.localGlobalReference],
                pdfFileReferences: ["F1"],
                pdfGlobalReferences: [fixture.localGlobalReference]
            ),
            AgentObservation(
                type: .discovery,
                candidateID: fixture.candidate.id,
                content: "related result",
                globalReferences: [
                    fixture.localGlobalReference,
                    fixture.externalGlobalReference
                ],
                pdfGlobalReferences: [fixture.externalGlobalReference]
            )
        ]

        let resolved = AgentDecisionReferenceResolver().resolve(
            decision(.inspectGlobalPDFContent),
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: observations
        )

        XCTAssertEqual(
            resolved.fileReferences,
            [fixture.externalGlobalReference]
        )
    }

    func testResolverFillsTwoInspectedPDFReferencesForDocumentComparison() throws {
        let fixture = try fixture()
        let observations = inspectedContentObservations(fixture: fixture)

        let resolved = AgentDecisionReferenceResolver().resolve(
            decision(.compareDocumentContent),
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: observations
        )

        XCTAssertEqual(
            Set(resolved.fileReferences),
            Set([
                fixture.localGlobalReference,
                fixture.externalGlobalReference
            ])
        )
    }

    func testResolverDoesNotRepairAlreadyComparedDocumentPair() throws {
        let fixture = try fixture()
        var observations = inspectedContentObservations(fixture: fixture)
        observations.append(
            AgentObservation(
                type: .documentComparison,
                candidateID: fixture.candidate.id,
                content: "semanticRelationship=sameDocumentRevision",
                globalReferences: [
                    fixture.externalGlobalReference,
                    fixture.localGlobalReference
                ],
                documentComparison: DocumentComparisonObservation(
                    fileIDs: [fixture.externalFile.id, fixture.localFile.id],
                    globalReferences: [
                        fixture.externalGlobalReference,
                        fixture.localGlobalReference
                    ],
                    deterministic: DeterministicDocumentComparison(
                        tokenOverlap: 0.8,
                        shingleSimilarity: 0.6,
                        lengthDifference: 0.1,
                        comparedCharacterCount: 22
                    ),
                    semantic: DocumentSemanticAssessment(
                        relationship: .sameDocumentRevision,
                        summary: "The documents appear to be revisions of the same proposal.",
                        confidence: 0.9
                    )
                )
            )
        )

        let resolved = AgentDecisionReferenceResolver().resolve(
            decision(.compareDocumentContent),
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: observations
        )

        XCTAssertTrue(resolved.fileReferences.isEmpty)
    }

    func testResolverDoesNotOverrideExplicitReferences() throws {
        let fixture = try fixture()
        let explicit = AgentDecision(
            action: .findRelatedFiles,
            candidateID: fixture.candidate.id,
            fileReferences: ["F999"],
            reason: "Fixture"
        )

        let resolved = AgentDecisionReferenceResolver().resolve(
            explicit,
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: []
        )

        XCTAssertEqual(resolved.fileReferences, ["F999"])
    }
}
