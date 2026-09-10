import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class AgentRequiredInvestigationRoutingTests: XCTestCase {
    private struct Fixture {
        let candidate: AnalysisCandidate
        let environment: AgentEnvironment
        let first: FileMetadata
        let second: FileMetadata
        let firstGlobal: String
        let secondGlobal: String
    }

    func testLegacyBenchmarkReasonResolvesTypedImageRequirement() throws {
        let fixture = try makeImageFixture()
        XCTAssertEqual(fixture.candidate.investigationRequirement, .imageSemantic)
    }

    func testRequiredImagePathRedirectsMetadataComparisonToInspection() throws {
        let fixture = try makeImageFixture()
        let original = AgentDecision(
            action: .compareGlobalFiles,
            candidateID: fixture.candidate.id,
            fileReferences: [fixture.firstGlobal, fixture.secondGlobal],
            reason: "Compare metadata first."
        )

        let resolved = AgentDecisionReferenceResolver().resolve(
            original,
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: [overview(fixture)]
        )

        XCTAssertEqual(resolved.action, .inspectImageContent)
        XCTAssertEqual(resolved.fileReferences, ["F1"])
        XCTAssertNil(resolved.finding)
    }

    func testRequiredImagePathInspectsSecondThenCompares() throws {
        let fixture = try makeImageFixture()
        var observations = [
            overview(fixture),
            imageContent(
                candidateID: fixture.candidate.id,
                file: fixture.first,
                localReference: "F1",
                globalReference: fixture.firstGlobal
            )
        ]
        let finish = AgentDecision(
            action: .finishCandidate,
            candidateID: fixture.candidate.id,
            fileReferences: [],
            reason: "Enough evidence is available."
        )

        var resolved = AgentDecisionReferenceResolver().resolve(
            finish,
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: observations
        )
        XCTAssertEqual(resolved.action, .inspectImageContent)
        XCTAssertEqual(resolved.fileReferences, ["F2"])

        observations.append(
            imageContent(
                candidateID: fixture.candidate.id,
                file: fixture.second,
                localReference: "F2",
                globalReference: fixture.secondGlobal
            )
        )
        resolved = AgentDecisionReferenceResolver().resolve(
            finish,
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

    func testRequiredImagePathStopsRedirectingAfterComparison() throws {
        let fixture = try makeImageFixture()
        let observations = [
            overview(fixture),
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
            imageComparison(fixture)
        ]
        let finish = AgentDecision(
            action: .finishCandidate,
            candidateID: fixture.candidate.id,
            fileReferences: [],
            reason: "Enough evidence is available."
        )

        let resolved = AgentDecisionReferenceResolver().resolve(
            finish,
            candidate: fixture.candidate,
            environment: fixture.environment,
            observations: observations
        )

        XCTAssertEqual(resolved.action, .finishCandidate)
        XCTAssertTrue(resolved.fileReferences.isEmpty)
    }

    func testCandidateDecodesWithoutNewRequirementField() throws {
        let id = UUID()
        let fileID = UUID()
        let data = Data(
            """
            {"id":"\(id.uuidString)","type":"grouping","fileIDs":["\(fileID.uuidString)"],"confidence":1.0,"reason":"Legacy candidate"}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(AnalysisCandidate.self, from: data)
        XCTAssertEqual(decoded.investigationRequirement, .automatic)
    }

    private func makeImageFixture() throws -> Fixture {
        let root = URL(fileURLWithPath: "/tmp/orderly-required-routing")
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
            reason: "Benchmark coverage requirement: inspect both images with inspectImageContent, then use compareImageContent before finishCandidate."
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
        let environment = AgentEnvironment(analysis: analysis, evidence: [evidence])
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
            content: "Two local image files.",
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
}
