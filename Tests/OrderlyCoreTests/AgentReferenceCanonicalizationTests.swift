import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class AgentReferenceCanonicalizationTests: XCTestCase {
    func testImageComparisonCanonicalizesInspectedLocalAliasesToGlobalReferences() throws {
        let root = URL(fileURLWithPath: "/tmp/orderly-image-reference-canonicalization")
        let first = metadata(
            id: UUID(),
            url: root.appendingPathComponent("screen-a.png")
        )
        let second = metadata(
            id: UUID(),
            url: root.appendingPathComponent("screen-b.png")
        )
        let candidate = AnalysisCandidate(
            id: UUID(),
            type: .grouping,
            fileIDs: [first.id, second.id],
            confidence: 1,
            reason: "Fixture"
        )
        let evidence = CandidateEvidence(
            candidateID: candidate.id,
            files: [
                candidateFile(first, reference: "F1"),
                candidateFile(second, reference: "F2")
            ]
        )
        let analysis = AnalysisResult(
            analyzedFolder: root,
            totalFiles: 2,
            totalSize: first.size + second.size,
            fileTypes: [],
            duplicateGroups: [],
            candidates: [candidate],
            analyzedAt: Date(timeIntervalSince1970: 3),
            files: [first, second],
            unreadableHashCount: 0
        )
        let environment = AgentEnvironment(
            analysis: analysis,
            evidence: [evidence]
        )
        let g1 = try XCTUnwrap(environment.globalReferenceByFileID[first.id])
        let g2 = try XCTUnwrap(environment.globalReferenceByFileID[second.id])

        let observations = [
            imageObservation(
                file: first,
                localReference: "F1",
                globalReference: g1,
                candidateID: candidate.id
            ),
            imageObservation(
                file: second,
                localReference: "F2",
                globalReference: g2,
                candidateID: candidate.id
            )
        ]
        let decision = AgentDecision(
            action: .compareImageContent,
            candidateID: candidate.id,
            fileReferences: ["F1", "F2"],
            reason: "Compare the two inspected images."
        )

        let resolved = AgentDecisionReferenceResolver().resolve(
            decision,
            candidate: candidate,
            environment: environment,
            observations: observations
        )

        XCTAssertEqual(Set(resolved.fileReferences), Set([g1, g2]))
    }

    func testImageComparisonDoesNotCanonicalizeUninspectedExplicitAlias() throws {
        let root = URL(fileURLWithPath: "/tmp/orderly-image-reference-canonicalization-invalid")
        let first = metadata(
            id: UUID(),
            url: root.appendingPathComponent("screen-a.png")
        )
        let second = metadata(
            id: UUID(),
            url: root.appendingPathComponent("screen-b.png")
        )
        let candidate = AnalysisCandidate(
            id: UUID(),
            type: .grouping,
            fileIDs: [first.id, second.id],
            confidence: 1,
            reason: "Fixture"
        )
        let evidence = CandidateEvidence(
            candidateID: candidate.id,
            files: [
                candidateFile(first, reference: "F1"),
                candidateFile(second, reference: "F2")
            ]
        )
        let analysis = AnalysisResult(
            analyzedFolder: root,
            totalFiles: 2,
            totalSize: first.size + second.size,
            fileTypes: [],
            duplicateGroups: [],
            candidates: [candidate],
            analyzedAt: Date(timeIntervalSince1970: 3),
            files: [first, second],
            unreadableHashCount: 0
        )
        let environment = AgentEnvironment(
            analysis: analysis,
            evidence: [evidence]
        )
        let g1 = try XCTUnwrap(environment.globalReferenceByFileID[first.id])
        let observations = [
            imageObservation(
                file: first,
                localReference: "F1",
                globalReference: g1,
                candidateID: candidate.id
            )
        ]
        let decision = AgentDecision(
            action: .compareImageContent,
            candidateID: candidate.id,
            fileReferences: ["F1", "F2"],
            reason: "Compare before both images were inspected."
        )

        let resolved = AgentDecisionReferenceResolver().resolve(
            decision,
            candidate: candidate,
            environment: environment,
            observations: observations
        )

        XCTAssertEqual(resolved.fileReferences, ["F1", "F2"])
    }

    private func metadata(id: UUID, url: URL) -> FileMetadata {
        FileMetadata(
            id: id,
            url: url,
            name: url.lastPathComponent,
            extensionName: "png",
            size: 1_000,
            createdAt: nil,
            modifiedAt: Date(timeIntervalSince1970: 1),
            accessedAt: nil,
            isDirectory: false,
            isHidden: false,
            uti: "public.png",
            classification: .image
        )
    }

    private func candidateFile(
        _ file: FileMetadata,
        reference: String
    ) -> CandidateFileEvidence {
        CandidateFileEvidence(
            fileID: file.id,
            reference: reference,
            name: file.name,
            tag: .image,
            size: file.size,
            modifiedAt: file.modifiedAt,
            relativePath: file.name,
            allowedDispositions: [.keep, .move, .review],
            isInstallerCandidate: false,
            duplicateCopyCount: 0,
            duplicateKeeperName: nil,
            duplicateKeeperModifiedAt: nil
        )
    }

    private func imageObservation(
        file: FileMetadata,
        localReference: String,
        globalReference: String,
        candidateID: UUID
    ) -> AgentObservation {
        let evidence = ImageEvidenceObservation(
            fileID: file.id,
            localReference: localReference,
            globalReference: globalReference,
            contentType: "public.png",
            width: 100,
            height: 100,
            frameCount: 1,
            orientation: 1
        )
        let semantic = ImageSemanticObservation(
            fileID: file.id,
            localReference: localReference,
            globalReference: globalReference,
            contentKind: .screenshot,
            summary: "A software screen.",
            confidence: 0.9
        )
        return AgentObservation(
            type: .imageContent,
            candidateID: candidateID,
            content: "image content",
            globalReferences: [globalReference],
            imageEvidence: evidence,
            imageSemantic: semantic,
            imageGlobalReferences: [globalReference]
        )
    }
}
