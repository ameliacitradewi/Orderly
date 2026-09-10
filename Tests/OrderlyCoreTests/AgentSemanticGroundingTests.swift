import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class AgentSemanticGroundingTests: XCTestCase {
    func testValidatorRejectsWholeBatchTopicClaimFromOnlyOneComparedPair() {
        let fixture = fixture(fileCount: 4)
        let comparison = imageComparisonObservation(
            candidateID: fixture.candidate.id,
            firstID: fixture.candidate.fileIDs[0],
            secondID: fixture.candidate.fileIDs[1],
            firstReference: "G1",
            secondReference: "G2"
        )
        let finding = AgentFinding(
            candidateID: fixture.candidate.id,
            relationship: .grouping,
            summary: "All files are related to the same topic, YOLO optimization for RC car autonomy.",
            evidence: [
                AgentEvidenceReference(
                    observationID: comparison.id,
                    description: "F1 and F2 were semantically compared as related images."
                )
            ],
            proposals: (1...4).map { index in
                AgentFileProposal(
                    fileReference: "F\(index)",
                    disposition: .review,
                    reason: "Review this category-batched image."
                )
            },
            confidence: 0.8
        )

        let issues = AgentPlanValidator().validate(
            finding: finding,
            candidate: fixture.candidate,
            evidence: fixture.evidence,
            observations: [comparison]
        )

        XCTAssertTrue(issues.contains(where: {
            $0.contains("connect every candidate file")
        }))
    }

    func testValidatorAcceptsWholeBatchTopicClaimWhenSemanticEvidenceConnectsEveryFile() {
        let fixture = fixture(fileCount: 4)
        let comparisons = [
            imageComparisonObservation(
                candidateID: fixture.candidate.id,
                firstID: fixture.candidate.fileIDs[0],
                secondID: fixture.candidate.fileIDs[1],
                firstReference: "G1",
                secondReference: "G2"
            ),
            imageComparisonObservation(
                candidateID: fixture.candidate.id,
                firstID: fixture.candidate.fileIDs[1],
                secondID: fixture.candidate.fileIDs[2],
                firstReference: "G2",
                secondReference: "G3"
            ),
            imageComparisonObservation(
                candidateID: fixture.candidate.id,
                firstID: fixture.candidate.fileIDs[2],
                secondID: fixture.candidate.fileIDs[3],
                firstReference: "G3",
                secondReference: "G4"
            )
        ]
        let finding = AgentFinding(
            candidateID: fixture.candidate.id,
            relationship: .grouping,
            summary: "All files are related to the same topic and form one semantic image group.",
            evidence: comparisons.map { observation in
                AgentEvidenceReference(
                    observationID: observation.id,
                    description: "A cited semantic image comparison connects members of the candidate group."
                )
            },
            proposals: (1...4).map { index in
                AgentFileProposal(
                    fileReference: "F\(index)",
                    disposition: .review,
                    reason: "Review this related image; visual similarity is not deletion safety."
                )
            },
            confidence: 0.8
        )

        let issues = AgentPlanValidator().validate(
            finding: finding,
            candidate: fixture.candidate,
            evidence: fixture.evidence,
            observations: comparisons
        )

        XCTAssertTrue(issues.isEmpty, "Unexpected issues: \(issues)")
    }

    private func fixture(
        fileCount: Int
    ) -> (candidate: AnalysisCandidate, evidence: CandidateEvidence) {
        let fileIDs = (0..<fileCount).map { _ in UUID() }
        let candidate = AnalysisCandidate(
            id: UUID(),
            type: .grouping,
            fileIDs: fileIDs,
            confidence: 1,
            reason: "Image category batch"
        )
        let evidence = CandidateEvidence(
            candidateID: candidate.id,
            files: fileIDs.enumerated().map { index, fileID in
                CandidateFileEvidence(
                    fileID: fileID,
                    reference: "F\(index + 1)",
                    name: "image-\(index + 1).png",
                    tag: .image,
                    size: 1_000,
                    modifiedAt: Date(timeIntervalSince1970: Double(index + 1)),
                    relativePath: "image-\(index + 1).png",
                    allowedDispositions: [.keep, .move, .review],
                    isInstallerCandidate: false,
                    duplicateCopyCount: 0,
                    duplicateKeeperName: nil,
                    duplicateKeeperModifiedAt: nil
                )
            }
        )
        return (candidate, evidence)
    }

    private func imageComparisonObservation(
        candidateID: UUID,
        firstID: UUID,
        secondID: UUID,
        firstReference: String,
        secondReference: String
    ) -> AgentObservation {
        let deterministic = DeterministicImageComparison(
            fileIDs: [firstID, secondID],
            globalReferences: [firstReference, secondReference],
            sameDimensions: true,
            aspectRatioDifference: 0,
            featurePrintDistance: 0.1
        )
        let comparison = ImageComparisonObservation(
            fileIDs: [firstID, secondID],
            globalReferences: [firstReference, secondReference],
            deterministic: deterministic,
            semantic: ImageSemanticAssessment(
                relationship: .sameSubject,
                confidence: 0.9,
                summary: "The two images share the same main subject."
            )
        )
        return AgentObservation(
            type: .imageSemanticComparison,
            candidateID: candidateID,
            content: "semanticRelationship=sameSubject",
            globalReferences: [firstReference, secondReference],
            imageComparison: deterministic,
            imageSemanticComparison: comparison
        )
    }
}
