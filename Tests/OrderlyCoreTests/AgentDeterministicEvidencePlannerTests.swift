import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class AgentDeterministicEvidencePlannerTests: XCTestCase {
    private struct Fixture {
        let candidate: AnalysisCandidate
        let environment: AgentEnvironment
        let first: FileMetadata
        let second: FileMetadata
        let firstGlobal: String
        let secondGlobal: String
    }

    func testAutomaticCandidateDoesNotBypassModelWithoutRecoveryFeedback() throws {
        let fixture = try makeFixture(requirement: .automatic)
        let decision = AgentDeterministicEvidencePlanner().nextDecision(
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: [overview(fixture)]
        )

        XCTAssertNil(decision)
    }

    func testRequiredImageWorkflowBypassesModelForInspectionAndComparison() throws {
        let fixture = try makeFixture(requirement: .imageSemantic)
        let planner = AgentDeterministicEvidencePlanner()
        var observations = [overview(fixture)]

        var decision = try XCTUnwrap(planner.nextDecision(
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: observations
        ))
        XCTAssertEqual(decision.action, .inspectImageContent)
        XCTAssertEqual(decision.fileReferences, ["F1"])

        observations.append(imageContent(
            candidateID: fixture.candidate.id,
            file: fixture.first,
            localReference: "F1",
            globalReference: fixture.firstGlobal
        ))
        decision = try XCTUnwrap(planner.nextDecision(
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: observations
        ))
        XCTAssertEqual(decision.action, .inspectImageContent)
        XCTAssertEqual(decision.fileReferences, ["F2"])

        observations.append(imageContent(
            candidateID: fixture.candidate.id,
            file: fixture.second,
            localReference: "F2",
            globalReference: fixture.secondGlobal
        ))
        decision = try XCTUnwrap(planner.nextDecision(
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: observations
        ))
        XCTAssertEqual(decision.action, .compareImageContent)
        XCTAssertEqual(
            Set(decision.fileReferences),
            Set([fixture.firstGlobal, fixture.secondGlobal])
        )

        observations.append(imageComparison(fixture))
        XCTAssertNil(planner.nextDecision(
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: observations
        ))
    }

    func testValidatorFeedbackCanBypassModelForBoundedRecovery() throws {
        let fixture = try makeFixture(requirement: .automatic)
        let observations = [
            overview(fixture),
            AgentObservation(
                type: .error,
                candidateID: fixture.candidate.id,
                content: "Cross-file semantic claims such as visual similarity require a cited semantic comparison."
            )
        ]

        let decision = try XCTUnwrap(
            AgentDeterministicEvidencePlanner().nextDecision(
                candidate: fixture.candidate,
                environment: fixture.environment,
                observations: observations
            )
        )
        XCTAssertEqual(decision.action, .inspectImageContent)
        XCTAssertEqual(decision.fileReferences, ["F1"])
    }

    func testUnavailableImagesDoNotTrapDeterministicPlanner() throws {
        let fixture = try makeFixture(requirement: .imageSemantic)
        let observations = [
            overview(fixture),
            AgentObservation(
                type: .error,
                candidateID: fixture.candidate.id,
                content: "Image inspection unavailable.",
                unavailableImageReferences: ["F1", "F2"]
            )
        ]

        XCTAssertNil(
            AgentDeterministicEvidencePlanner().nextDecision(
                candidate: fixture.candidate,
                environment: fixture.environment,
                observations: observations
            )
        )
    }

    private func makeFixture(
        requirement: CandidateInvestigationRequirement
    ) throws -> Fixture {
        let root = URL(fileURLWithPath: "/tmp/orderly-deterministic-evidence")
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
            reason: "Fixture",
            investigationRequirement: requirement
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

        return Fixture(
            candidate: candidate,
            environment: environment,
            first: first,
            second: second,
            firstGlobal: try XCTUnwrap(environment.globalReferenceByFileID[first.id]),
            secondGlobal: try XCTUnwrap(environment.globalReferenceByFileID[second.id])
        )
    }

    private func overview(_ fixture: Fixture) -> AgentObservation {
        AgentObservation(
            type: .candidate,
            candidateID: fixture.candidate.id,
            content: "Two candidate images.",
            globalReferences: [fixture.firstGlobal, fixture.secondGlobal],
            imageFileReferences: ["F1", "F2"],
            imageGlobalReferences: [fixture.firstGlobal, fixture.secondGlobal]
        )
    }

    private func imageContent(
        candidateID: UUID,
        file: FileMetadata,
        localReference: String,
        globalReference: String
    ) -> AgentObservation {
        AgentObservation(
            type: .imageContent,
            candidateID: candidateID,
            content: "contentKind=screenshot",
            globalReferences: [globalReference],
            imageSemantic: ImageSemanticObservation(
                fileID: file.id,
                localReference: localReference,
                globalReference: globalReference,
                contentKind: .screenshot,
                summary: "A settings screen is visible.",
                confidence: 0.9
            ),
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
        let semantic = ImageComparisonObservation(
            fileIDs: [fixture.first.id, fixture.second.id],
            globalReferences: [fixture.firstGlobal, fixture.secondGlobal],
            deterministic: deterministic,
            semantic: ImageSemanticAssessment(
                relationship: .sameImageVariant,
                confidence: 0.9,
                summary: "The images are variants of the same screen."
            )
        )

        return AgentObservation(
            type: .imageSemanticComparison,
            candidateID: fixture.candidate.id,
            content: "semanticRelationship=sameImageVariant",
            globalReferences: [fixture.firstGlobal, fixture.secondGlobal],
            imageComparison: deterministic,
            imageSemanticComparison: semantic
        )
    }
}
