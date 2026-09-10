import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class AgentSemanticRecoveryTests: XCTestCase {
    private struct Fixture {
        let candidate: AnalysisCandidate
        let environment: AgentEnvironment
        let first: FileMetadata
        let second: FileMetadata
        let firstGlobal: String
        let secondGlobal: String
    }

    func testMetadataOnlySemanticRejectionForcesFirstImageInspection() throws {
        let fixture = try makeImageFixture()
        let observations = [
            overview(fixture),
            semanticRejection(fixture)
        ]

        let resolved = AgentDecisionReferenceResolver().resolve(
            finishDecision(fixture),
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: observations
        )

        XCTAssertEqual(resolved.action, .inspectImageContent)
        XCTAssertEqual(resolved.fileReferences, ["F1"])
        XCTAssertNil(resolved.finding)
    }

    func testRecoveryInspectsRemainingImageBeforeComparison() throws {
        let fixture = try makeImageFixture()
        let observations = [
            overview(fixture),
            semanticRejection(fixture),
            imageContent(
                candidateID: fixture.candidate.id,
                file: fixture.first,
                localReference: "F1",
                globalReference: fixture.firstGlobal
            )
        ]

        let resolved = AgentDecisionReferenceResolver().resolve(
            finishDecision(fixture),
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: observations
        )

        XCTAssertEqual(resolved.action, .inspectImageContent)
        XCTAssertEqual(resolved.fileReferences, ["F2"])
    }

    func testRecoveryComparesImagesAfterBothAreInspected() throws {
        let fixture = try makeImageFixture()
        let observations = [
            overview(fixture),
            semanticRejection(fixture),
            imageContent(
                candidateID: fixture.candidate.id,
                file: fixture.first,
                localReference: "F1",
                globalReference: fixture.firstGlobal
            ),
            imageContent(
                candidateID: fixture.candidate.id,
                file: fixture.second,
                localReference: "F2",
                globalReference: fixture.secondGlobal
            )
        ]

        let resolved = AgentDecisionReferenceResolver().resolve(
            finishDecision(fixture),
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: observations
        )

        XCTAssertEqual(resolved.action, .compareImageContent)
        XCTAssertEqual(
            Set(resolved.fileReferences),
            Set([fixture.firstGlobal, fixture.secondGlobal])
        )
    }

    func testRecoveryStopsForcingActionsAfterSemanticComparison() throws {
        let fixture = try makeImageFixture()
        let comparison = imageComparison(fixture)
        let observations = [
            overview(fixture),
            semanticRejection(fixture),
            imageContent(
                candidateID: fixture.candidate.id,
                file: fixture.first,
                localReference: "F1",
                globalReference: fixture.firstGlobal
            ),
            imageContent(
                candidateID: fixture.candidate.id,
                file: fixture.second,
                localReference: "F2",
                globalReference: fixture.secondGlobal
            ),
            comparison
        ]

        let original = finishDecision(fixture)
        let resolved = AgentDecisionReferenceResolver().resolve(
            original,
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: observations
        )

        XCTAssertEqual(resolved.action, .finishCandidate)
        XCTAssertTrue(resolved.fileReferences.isEmpty)
    }

    func testRecoveryDoesNotTrapCandidateWhenImagesAreUnavailable() throws {
        let fixture = try makeImageFixture()
        let unavailable = AgentObservation(
            type: .error,
            candidateID: fixture.candidate.id,
            content: "Image inspection failed for both local images.",
            unavailableImageReferences: ["F1", "F2"]
        )
        let observations = [
            overview(fixture),
            semanticRejection(fixture),
            unavailable
        ]

        let resolved = AgentDecisionReferenceResolver().resolve(
            finishDecision(fixture),
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: observations
        )

        XCTAssertEqual(resolved.action, .finishCandidate)
        XCTAssertTrue(resolved.fileReferences.isEmpty)
    }

    private func makeImageFixture() throws -> Fixture {
        let root = URL(fileURLWithPath: "/tmp/orderly-semantic-recovery")
        let first = FileMetadata(
            id: UUID(),
            url: root.appendingPathComponent("screen-a.png"),
            name: "screen-a.png",
            extensionName: "png",
            size: 1_000,
            createdAt: nil,
            modifiedAt: Date(timeIntervalSince1970: 1),
            accessedAt: nil,
            isDirectory: false,
            isHidden: false,
            uti: nil
        )
        let second = FileMetadata(
            id: UUID(),
            url: root.appendingPathComponent("screen-b.png"),
            name: "screen-b.png",
            extensionName: "png",
            size: 1_100,
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
            fileIDs: [first.id, second.id],
            confidence: 1,
            reason: "Image grouping fixture"
        )
        let evidence = CandidateEvidence(
            candidateID: candidate.id,
            files: [
                CandidateFileEvidence(
                    fileID: first.id,
                    reference: "F1",
                    name: first.name,
                    tag: .image,
                    size: first.size,
                    modifiedAt: first.modifiedAt,
                    relativePath: first.name,
                    allowedDispositions: [.keep, .move, .review],
                    isInstallerCandidate: false,
                    duplicateCopyCount: 0,
                    duplicateKeeperName: nil,
                    duplicateKeeperModifiedAt: nil
                ),
                CandidateFileEvidence(
                    fileID: second.id,
                    reference: "F2",
                    name: second.name,
                    tag: .image,
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
            candidates: [candidate],
            analyzedAt: Date(timeIntervalSince1970: 3),
            files: [first, second],
            unreadableHashCount: 0
        )
        let environment = AgentEnvironment(
            analysis: analysis,
            evidence: [evidence]
        )
        let firstGlobal = try XCTUnwrap(
            environment.globalReferenceByFileID[first.id]
        )
        let secondGlobal = try XCTUnwrap(
            environment.globalReferenceByFileID[second.id]
        )

        return Fixture(
            candidate: candidate,
            environment: environment,
            first: first,
            second: second,
            firstGlobal: firstGlobal,
            secondGlobal: secondGlobal
        )
    }

    private func overview(_ fixture: Fixture) -> AgentObservation {
        AgentObservation(
            type: .candidate,
            candidateID: fixture.candidate.id,
            content: "Two local image files.",
            globalReferences: [fixture.firstGlobal, fixture.secondGlobal],
            imageFileReferences: ["F1", "F2"],
            imageGlobalReferences: [fixture.firstGlobal, fixture.secondGlobal]
        )
    }

    private func semanticRejection(_ fixture: Fixture) -> AgentObservation {
        AgentObservation(
            type: .error,
            candidateID: fixture.candidate.id,
            content: """
            Your proposed finding was rejected by validation.
            - Cross-file semantic claims such as visual similarity, shared session/project/topic/subject, or image/document variants require a cited semantic comparison. Metadata-only evidence cannot establish that relationship.
            """
        )
    }

    private func imageContent(
        candidateID: UUID,
        file: FileMetadata,
        localReference: String,
        globalReference: String
    ) -> AgentObservation {
        let semantic = ImageSemanticObservation(
            fileID: file.id,
            localReference: localReference,
            globalReference: globalReference,
            contentKind: .screenshot,
            summary: "A settings screen is visible.",
            confidence: 0.9
        )
        return AgentObservation(
            type: .imageContent,
            candidateID: candidateID,
            content: "contentKind=screenshot",
            globalReferences: [globalReference],
            imageSemantic: semantic,
            imageGlobalReferences: [globalReference]
        )
    }

    private func imageComparison(_ fixture: Fixture) -> AgentObservation {
        let deterministic = DeterministicImageComparison(
            fileIDs: [fixture.first.id, fixture.second.id],
            globalReferences: [fixture.firstGlobal, fixture.secondGlobal],
            sameDimensions: true,
            aspectRatioDifference: 0,
            featurePrintDistance: 0.05
        )
        let comparison = ImageComparisonObservation(
            fileIDs: [fixture.first.id, fixture.second.id],
            globalReferences: [fixture.firstGlobal, fixture.secondGlobal],
            deterministic: deterministic,
            semantic: ImageSemanticAssessment(
                relationship: .sameImageVariant,
                confidence: 0.9,
                summary: "The screenshots are variants of the same screen."
            )
        )
        return AgentObservation(
            type: .imageSemanticComparison,
            candidateID: fixture.candidate.id,
            content: "semanticRelationship=sameImageVariant",
            globalReferences: [fixture.firstGlobal, fixture.secondGlobal],
            imageComparison: deterministic,
            imageSemanticComparison: comparison
        )
    }

    private func finishDecision(_ fixture: Fixture) -> AgentDecision {
        AgentDecision(
            action: .finishCandidate,
            candidateID: fixture.candidate.id,
            fileReferences: [],
            reason: "Enough evidence is available."
        )
    }
}
