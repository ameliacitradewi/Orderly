import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class AgentDeterministicSemanticFindingTests: XCTestCase {
    func testDocumentRelationshipBuildsValidatedReviewFinding() throws {
        let fixture = makeFixture(
            fileCount: 2,
            allowedDispositions: [.keep, .move, .review]
        )
        let observation = AgentObservation(
            type: .documentComparison,
            candidateID: fixture.candidate.id,
            content: "semanticRelationship=sameDocumentRevision",
            globalReferences: ["G1", "G2"],
            documentComparison: DocumentComparisonObservation(
                fileIDs: fixture.candidate.fileIDs,
                globalReferences: ["G1", "G2"],
                deterministic: DeterministicDocumentComparison(
                    tokenOverlap: 0.86,
                    shingleSimilarity: 0.44,
                    lengthDifference: 0.06,
                    comparedCharacterCount: 680
                ),
                semantic: DocumentSemanticAssessment(
                    relationship: .sameDocumentRevision,
                    summary: "The documents are revisions of the same underlying document.",
                    confidence: 0.9
                )
            )
        )

        let finding = try XCTUnwrap(
            AgentDeterministicFindingPlanner().finding(
                candidate: fixture.candidate,
                evidence: fixture.evidence,
                observations: [observation]
            )
        )

        XCTAssertEqual(finding.relationship, .related)
        XCTAssertEqual(finding.confidence, 0.9, accuracy: 0.0001)
        XCTAssertEqual(finding.evidence.map(\.observationID), [observation.id])
        XCTAssertTrue(finding.proposals.allSatisfy { $0.disposition == .review })
        XCTAssertFalse(finding.proposals.contains { $0.disposition == .trash })
        XCTAssertFalse(finding.summary.lowercased().contains("newer"))
        XCTAssertFalse(finding.summary.lowercased().contains("older"))

        let issues = AgentPlanValidator().validate(
            finding: finding,
            candidate: fixture.candidate,
            evidence: fixture.evidence,
            observations: [observation]
        )
        XCTAssertTrue(issues.isEmpty, "Unexpected validation issues: \(issues)")
    }

    func testImageRelationshipBuildsValidatedReviewFinding() throws {
        let fixture = makeFixture(
            fileCount: 2,
            allowedDispositions: [.keep, .move, .review]
        )
        let deterministic = DeterministicImageComparison(
            fileIDs: fixture.candidate.fileIDs,
            globalReferences: ["G1", "G2"],
            sameDimensions: true,
            aspectRatioDifference: 0,
            featurePrintDistance: 0.18
        )
        let observation = AgentObservation(
            type: .imageSemanticComparison,
            candidateID: fixture.candidate.id,
            content: "semanticRelationship=sameScene",
            globalReferences: ["G1", "G2"],
            imageComparison: deterministic,
            imageSemanticComparison: ImageComparisonObservation(
                fileIDs: fixture.candidate.fileIDs,
                globalReferences: ["G1", "G2"],
                deterministic: deterministic,
                semantic: ImageSemanticAssessment(
                    relationship: .sameScene,
                    confidence: 0.75,
                    summary: "The images show the same settings screen family."
                )
            )
        )

        let finding = try XCTUnwrap(
            AgentDeterministicFindingPlanner().finding(
                candidate: fixture.candidate,
                evidence: fixture.evidence,
                observations: [observation]
            )
        )

        XCTAssertEqual(finding.relationship, .related)
        XCTAssertEqual(finding.confidence, 0.75, accuracy: 0.0001)
        XCTAssertTrue(finding.proposals.allSatisfy { $0.disposition == .review })
        XCTAssertFalse(finding.proposals.contains { $0.disposition == .trash })

        let issues = AgentPlanValidator().validate(
            finding: finding,
            candidate: fixture.candidate,
            evidence: fixture.evidence,
            observations: [observation]
        )
        XCTAssertTrue(issues.isEmpty, "Unexpected validation issues: \(issues)")
    }

    func testSemanticFastPathRefusesCandidateWhenTrashIsAllowed() {
        let fixture = makeFixture(
            fileCount: 2,
            allowedDispositions: [.keep, .review, .trash]
        )
        let observation = AgentObservation(
            type: .documentComparison,
            candidateID: fixture.candidate.id,
            content: "semanticRelationship=sameTopic",
            documentComparison: DocumentComparisonObservation(
                fileIDs: fixture.candidate.fileIDs,
                globalReferences: ["G1", "G2"],
                deterministic: DeterministicDocumentComparison(
                    tokenOverlap: 0.5,
                    shingleSimilarity: 0.2,
                    lengthDifference: 0.1,
                    comparedCharacterCount: 400
                ),
                semantic: DocumentSemanticAssessment(
                    relationship: .sameTopic,
                    summary: "The documents discuss the same topic.",
                    confidence: 0.8
                )
            )
        )

        XCTAssertNil(
            AgentDeterministicFindingPlanner().finding(
                candidate: fixture.candidate,
                evidence: fixture.evidence,
                observations: [observation]
            )
        )
    }

    func testSemanticFastPathRequiresConnectedEvidenceForEveryCandidateFile() {
        let fixture = makeFixture(
            fileCount: 3,
            allowedDispositions: [.keep, .move, .review]
        )
        let partialObservation = AgentObservation(
            type: .documentComparison,
            candidateID: fixture.candidate.id,
            content: "semanticRelationship=sameTopic",
            documentComparison: DocumentComparisonObservation(
                fileIDs: Array(fixture.candidate.fileIDs.prefix(2)),
                globalReferences: ["G1", "G2"],
                deterministic: DeterministicDocumentComparison(
                    tokenOverlap: 0.5,
                    shingleSimilarity: 0.2,
                    lengthDifference: 0.1,
                    comparedCharacterCount: 400
                ),
                semantic: DocumentSemanticAssessment(
                    relationship: .sameTopic,
                    summary: "Two files discuss the same topic.",
                    confidence: 0.8
                )
            )
        )

        XCTAssertNil(
            AgentDeterministicFindingPlanner().finding(
                candidate: fixture.candidate,
                evidence: fixture.evidence,
                observations: [partialObservation]
            )
        )
    }

    private func makeFixture(
        fileCount: Int,
        allowedDispositions: [FileDisposition]
    ) -> (candidate: AnalysisCandidate, evidence: CandidateEvidence) {
        let ids = (0..<fileCount).map { _ in UUID() }
        let candidate = AnalysisCandidate(
            id: UUID(),
            type: .grouping,
            fileIDs: ids,
            confidence: 1,
            reason: "Semantic finding fixture"
        )
        let evidence = CandidateEvidence(
            candidateID: candidate.id,
            files: ids.enumerated().map { index, id in
                CandidateFileEvidence(
                    fileID: id,
                    reference: "F\(index + 1)",
                    name: "file-\(index + 1).pdf",
                    tag: .document,
                    size: 100 + Int64(index),
                    modifiedAt: nil,
                    relativePath: "file-\(index + 1).pdf",
                    allowedDispositions: allowedDispositions,
                    isInstallerCandidate: false,
                    duplicateCopyCount: 0,
                    duplicateKeeperName: nil,
                    duplicateKeeperModifiedAt: nil
                )
            }
        )
        return (candidate, evidence)
    }
}
