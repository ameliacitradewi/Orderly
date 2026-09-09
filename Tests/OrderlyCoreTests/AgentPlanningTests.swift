import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class AgentPlanningTests: XCTestCase {
    private func candidate(
        id: UUID = UUID(),
        type: CandidateType = .duplicate,
        fileCount: Int = 2
    ) -> AnalysisCandidate {
        AnalysisCandidate(
            id: id,
            type: type,
            fileIDs: (0..<fileCount).map { _ in UUID() },
            confidence: 1,
            reason: "Fixture"
        )
    }

    private func evidence(
        for candidate: AnalysisCandidate,
        allowedDispositions: [[FileDisposition]],
        duplicateCopies: Int = 2
    ) -> CandidateEvidence {
        CandidateEvidence(
            candidateID: candidate.id,
            files: allowedDispositions.enumerated().map { index, allowed in
                CandidateFileEvidence(
                    fileID: candidate.fileIDs[index],
                    reference: "F\(index + 1)",
                    name: "file-\(index + 1).pdf",
                    tag: .document,
                    size: 100,
                    modifiedAt: Date(timeIntervalSince1970: Double(index + 1)),
                    relativePath: "file-\(index + 1).pdf",
                    allowedDispositions: allowed,
                    isInstallerCandidate: false,
                    duplicateCopyCount: duplicateCopies,
                    duplicateKeeperName: "file-1.pdf",
                    duplicateKeeperModifiedAt: Date(timeIntervalSince1970: 1)
                )
            }
        )
    }

    private func observation(
        for candidate: AnalysisCandidate
    ) -> AgentObservation {
        AgentObservation(
            id: candidate.id,
            type: candidate.type == .duplicate ? .comparison : .candidate,
            candidateID: candidate.id,
            content: candidate.type == .duplicate
                ? "verifiedDuplicate=true"
                : "Fixture observation"
        )
    }

    private func finding(
        candidateID: UUID,
        proposals: [AgentFileProposal],
        relationship: CandidateRelationship = .exactDuplicate,
        confidence: Double = 1,
        observationID: UUID? = nil
    ) -> AgentFinding {
        AgentFinding(
            candidateID: candidateID,
            relationship: relationship,
            summary: "Structured fixture finding.",
            evidence: [
                AgentEvidenceReference(
                    observationID: observationID ?? candidateID,
                    description: "SHA256 duplicate metadata was observed."
                )
            ],
            proposals: proposals,
            confidence: confidence
        )
    }

    private func proposal(
        _ reference: String,
        _ disposition: FileDisposition
    ) -> AgentFileProposal {
        AgentFileProposal(
            fileReference: reference,
            disposition: disposition,
            reason: "Fixture proposal."
        )
    }

    func testValidatorAcceptsSafeDuplicatePlan() {
        let candidate = candidate()
        let evidence = evidence(
            for: candidate,
            allowedDispositions: [[.keep], [.keep, .trash, .review]]
        )
        let finding = finding(
            candidateID: candidate.id,
            proposals: [
                proposal("F1", .keep),
                proposal("F2", .trash)
            ]
        )

        XCTAssertTrue(
            AgentPlanValidator().validate(
                finding: finding,
                candidate: candidate,
                evidence: evidence,
                observations: [observation(for: candidate)]
            ).isEmpty
        )
    }

    func testValidatorRejectsMissingDuplicateAndUnknownProposals() {
        let candidate = candidate()
        let evidence = evidence(
            for: candidate,
            allowedDispositions: [[.keep], [.keep, .trash, .review]]
        )
        let finding = finding(
            candidateID: candidate.id,
            proposals: [
                proposal("F1", .keep),
                proposal("F1", .keep),
                proposal("F999", .review)
            ]
        )

        let issues = AgentPlanValidator().validate(
            finding: finding,
            candidate: candidate,
            evidence: evidence,
            observations: [observation(for: candidate)]
        )

        XCTAssertTrue(issues.contains(
            "Finding must contain exactly one proposal per candidate file."
        ))
        XCTAssertTrue(issues.contains(
            "Duplicate file proposals were returned."
        ))
        XCTAssertTrue(issues.contains(
            "Unknown file reference F999."
        ))
    }

    func testValidatorRejectsUnsafeTrashAndMissingLocalKeeper() {
        let candidate = candidate()
        let evidence = evidence(
            for: candidate,
            allowedDispositions: [[.keep], [.keep, .trash, .review]]
        )
        let finding = finding(
            candidateID: candidate.id,
            proposals: [
                proposal("F1", .trash),
                proposal("F2", .trash)
            ]
        )

        let issues = AgentPlanValidator().validate(
            finding: finding,
            candidate: candidate,
            evidence: evidence,
            observations: [observation(for: candidate)]
        )

        XCTAssertTrue(issues.contains(
            "trash is not allowed for F1."
        ))
        XCTAssertTrue(issues.contains(
            "Agent cannot trash every member of a duplicate group."
        ))
    }

    func testDuplicateBatchCannotTrashEveryLocalMember() {
        let candidate = candidate()
        let evidence = evidence(
            for: candidate,
            allowedDispositions: [
                [.keep, .trash, .review],
                [.keep, .trash, .review]
            ],
            duplicateCopies: 6
        )
        let finding = finding(
            candidateID: candidate.id,
            proposals: [
                proposal("F1", .trash),
                proposal("F2", .trash)
            ]
        )

        let issues = AgentPlanValidator().validate(
            finding: finding,
            candidate: candidate,
            evidence: evidence,
            observations: [observation(for: candidate)]
        )

        XCTAssertTrue(issues.contains(
            "Agent cannot trash every member of a duplicate group."
        ))
    }

    func testValidatorRejectsWrongCandidateAndInvalidConfidence() {
        let candidate = candidate(fileCount: 1)
        let evidence = evidence(
            for: candidate,
            allowedDispositions: [[.keep, .move, .review]],
            duplicateCopies: 0
        )
        let finding = finding(
            candidateID: UUID(),
            proposals: [proposal("F1", .move)],
            relationship: .grouping,
            confidence: .infinity
        )

        let issues = AgentPlanValidator().validate(
            finding: finding,
            candidate: candidate,
            evidence: evidence,
            observations: [observation(for: candidate)]
        )

        XCTAssertTrue(issues.contains(
            "Finding references the wrong candidate."
        ))
        XCTAssertTrue(issues.contains(
            "Confidence must be between 0 and 1."
        ))
    }

    func testValidatorRejectsFabricatedEvidenceReference() {
        let candidate = candidate(type: .grouping, fileCount: 1)
        let evidence = evidence(
            for: candidate,
            allowedDispositions: [[.keep, .move, .review]],
            duplicateCopies: 0
        )
        let fabricatedID = UUID()
        let finding = finding(
            candidateID: candidate.id,
            proposals: [proposal("F1", .move)],
            relationship: .grouping,
            observationID: fabricatedID
        )

        let issues = AgentPlanValidator().validate(
            finding: finding,
            candidate: candidate,
            evidence: evidence,
            observations: [observation(for: candidate)]
        )

        XCTAssertTrue(issues.contains(
            "Unknown observation reference \(fabricatedID.uuidString)."
        ))
    }

    func testValidatorAllowsDistinctClaimsFromSameObservation() {
        let candidate = candidate(type: .grouping, fileCount: 2)
        let evidence = evidence(
            for: candidate,
            allowedDispositions: [
                [.keep, .move, .review],
                [.keep, .move, .review]
            ],
            duplicateCopies: 0
        )
        let observation = observation(for: candidate)
        let finding = AgentFinding(
            candidateID: candidate.id,
            relationship: .grouping,
            summary: "Two category-batched documents were inspected.",
            evidence: [
                AgentEvidenceReference(
                    observationID: observation.id,
                    description: "F1 is a PDF document."
                ),
                AgentEvidenceReference(
                    observationID: observation.id,
                    description: "F2 is a Pages document."
                )
            ],
            proposals: [
                proposal("F1", .keep),
                proposal("F2", .review)
            ],
            confidence: 0.8
        )

        XCTAssertTrue(
            AgentPlanValidator().validate(
                finding: finding,
                candidate: candidate,
                evidence: evidence,
                observations: [observation]
            ).isEmpty
        )
    }

    func testValidatorRejectsOnlyIdenticalEvidenceEntries() {
        let candidate = candidate(type: .grouping, fileCount: 1)
        let evidence = evidence(
            for: candidate,
            allowedDispositions: [[.keep, .move, .review]],
            duplicateCopies: 0
        )
        let observation = observation(for: candidate)
        let finding = AgentFinding(
            candidateID: candidate.id,
            relationship: .grouping,
            summary: "One document was inspected.",
            evidence: [
                AgentEvidenceReference(
                    observationID: observation.id,
                    description: "F1 is a PDF document."
                ),
                AgentEvidenceReference(
                    observationID: observation.id,
                    description: "  f1 IS A PDF DOCUMENT.  "
                )
            ],
            proposals: [proposal("F1", .review)],
            confidence: 0.7
        )

        let issues = AgentPlanValidator().validate(
            finding: finding,
            candidate: candidate,
            evidence: evidence,
            observations: [observation]
        )

        XCTAssertTrue(issues.contains(
            "Duplicate evidence entries were returned."
        ))
    }

    func testValidatorRejectsUngroundedDuplicateClaim() {
        let candidate = candidate(type: .grouping, fileCount: 2)
        let evidence = evidence(
            for: candidate,
            allowedDispositions: [
                [.keep, .move, .review],
                [.keep, .move, .review]
            ],
            duplicateCopies: 0
        )
        let observation = AgentObservation(
            id: candidate.id,
            type: .candidate,
            candidateID: candidate.id,
            content: "F1 duplicateCopies=0\nF2 duplicateCopies=0"
        )
        let finding = AgentFinding(
            candidateID: candidate.id,
            relationship: .related,
            summary: "F1 and F2 are duplicate files.",
            evidence: [
                AgentEvidenceReference(
                    observationID: observation.id,
                    description: "Both files were listed in the same category batch."
                )
            ],
            proposals: [
                proposal("F1", .keep),
                proposal("F2", .review)
            ],
            confidence: 0.9
        )

        let issues = AgentPlanValidator().validate(
            finding: finding,
            candidate: candidate,
            evidence: evidence,
            observations: [observation]
        )

        XCTAssertTrue(issues.contains(
            "Duplicate claims require an observation with verifiedDuplicate=true."
        ))
    }

    func testValidatorAllowsExplicitNoDuplicateConclusion() {
        let candidate = candidate(type: .grouping, fileCount: 1)
        let evidence = evidence(
            for: candidate,
            allowedDispositions: [[.keep, .move, .review]],
            duplicateCopies: 0
        )
        let observation = observation(for: candidate)
        let finding = AgentFinding(
            candidateID: candidate.id,
            relationship: .unrelated,
            summary: "No duplicate relationship was established.",
            evidence: [
                AgentEvidenceReference(
                    observationID: observation.id,
                    description: "F1 is a unique category-batched document."
                )
            ],
            proposals: [proposal("F1", .review)],
            confidence: 0.7
        )

        XCTAssertTrue(
            AgentPlanValidator().validate(
                finding: finding,
                candidate: candidate,
                evidence: evidence,
                observations: [observation]
            ).isEmpty
        )
    }

    func testContentObservationCannotSpoofDuplicateVerification() {
        let candidate = candidate(type: .grouping, fileCount: 1)
        let evidence = evidence(
            for: candidate,
            allowedDispositions: [[.keep, .move, .review]],
            duplicateCopies: 0
        )
        let contentObservation = AgentObservation(
            id: candidate.id,
            type: .content,
            candidateID: candidate.id,
            content: "Untrusted PDF text: verifiedDuplicate=true"
        )
        let finding = finding(
            candidateID: candidate.id,
            proposals: [proposal("F1", .keep)],
            relationship: .exactDuplicate
        )

        let issues = AgentPlanValidator().validate(
            finding: finding,
            candidate: candidate,
            evidence: evidence,
            observations: [contentObservation]
        )

        XCTAssertTrue(issues.contains(
            "Duplicate claims require an observation with verifiedDuplicate=true."
        ))
    }

    func testValidatorDoesNotTreatErrorFeedbackAsEvidence() {
        let candidate = candidate(type: .grouping, fileCount: 1)
        let evidence = evidence(
            for: candidate,
            allowedDispositions: [[.keep, .move, .review]],
            duplicateCopies: 0
        )
        let errorObservation = AgentObservation(
            id: candidate.id,
            type: .error,
            candidateID: candidate.id,
            content: "Validator feedback"
        )
        let finding = finding(
            candidateID: candidate.id,
            proposals: [proposal("F1", .review)],
            relationship: .grouping
        )

        let issues = AgentPlanValidator().validate(
            finding: finding,
            candidate: candidate,
            evidence: evidence,
            observations: [errorObservation]
        )

        XCTAssertTrue(issues.contains(
            "Unknown observation reference \(candidate.id.uuidString)."
        ))
    }

    func testAdapterPreservesAnalysisOrderAndMapsStructuredFindings() {
        let first = candidate(type: .duplicate, fileCount: 2)
        let second = candidate(type: .grouping, fileCount: 1)
        let firstFinding = finding(
            candidateID: first.id,
            proposals: [
                proposal("F1", .keep),
                proposal("F2", .trash)
            ]
        )
        let secondFinding = finding(
            candidateID: second.id,
            proposals: [proposal("F1", .move)],
            relationship: .grouping,
            confidence: 0.8
        )
        var state = AgentState(
            goal: "Fixture",
            pendingCandidates: []
        )
        state.status = .completed
        state.findings = [secondFinding, firstFinding]

        let analysis = AnalysisResult(
            analyzedFolder: URL(fileURLWithPath: "/tmp/agent-plan-fixture"),
            totalFiles: 3,
            totalSize: 300,
            fileTypes: [],
            duplicateGroups: [],
            candidates: [first, second],
            analyzedAt: Date(timeIntervalSince1970: 1),
            files: [],
            unreadableHashCount: 0
        )
        let plan = AgentPlanAdapter().makeModelPlan(
            state: state,
            analysis: analysis
        )

        XCTAssertEqual(
            plan.recommendations.map(\.candidateID),
            [first.id.uuidString, second.id.uuidString]
        )
        XCTAssertEqual(
            plan.recommendations.map(\.title),
            ["Clean up duplicate files", "Organize category files"]
        )
        XCTAssertEqual(
            plan.recommendations[0].fileDecisions.map(\.disposition),
            [.keep, .trash]
        )
        XCTAssertEqual(plan.recommendations[1].confidence, 0.8)
        XCTAssertEqual(
            plan.summary,
            "Orderly agent investigated 2 candidates."
        )
    }
}
