import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class ToolRouterTests: XCTestCase {
    private func fixtureEnvironment() async throws -> (
        environment: AgentEnvironment,
        candidate: AnalysisCandidate,
        evidence: CandidateEvidence
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let older = try file(
            "report-old.pdf",
            in: root,
            bytes: "verified duplicate",
            time: 1
        )
        let newer = try file(
            "report-new.pdf",
            in: root,
            bytes: "verified duplicate",
            time: 2
        )
        let scan = try await DuplicateDetector().findDuplicates(
            in: [older, newer]
        )
        let candidates = ClutterAnalyzer().analyze(
            files: scan.files,
            duplicateGroups: scan.groups
        )
        let candidate = try XCTUnwrap(candidates.first)
        let evidence = EvidenceEngine().buildEvidence(
            candidates: candidates,
            files: scan.files,
            duplicateGroups: scan.groups,
            rootFolder: root
        )
        let candidateEvidence = try XCTUnwrap(
            evidence.first(where: { $0.candidateID == candidate.id })
        )
        let analysis = AnalysisResult(
            analyzedFolder: root,
            totalFiles: scan.files.count,
            totalSize: scan.files.reduce(0) { $0 + $1.size },
            fileTypes: [],
            duplicateGroups: scan.groups,
            candidates: candidates,
            analyzedAt: Date(timeIntervalSince1970: 3),
            files: scan.files,
            unreadableHashCount: scan.unreadableCount
        )

        return (
            AgentEnvironment(analysis: analysis, evidence: evidence),
            candidate,
            candidateEvidence
        )
    }

    private func file(
        _ name: String,
        in root: URL,
        bytes: String,
        time: TimeInterval
    ) throws -> FileMetadata {
        let url = root.appendingPathComponent(name)
        try Data(bytes.utf8).write(to: url)
        let date = Date(timeIntervalSince1970: time)
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: url.path
        )
        return FileMetadata(
            id: UUID(),
            url: url,
            name: name,
            extensionName: url.pathExtension,
            size: Int64(bytes.utf8.count),
            createdAt: nil,
            modifiedAt: date,
            accessedAt: nil,
            isDirectory: false,
            isHidden: false,
            uti: nil
        )
    }

    func testInspectCandidateReturnsOnlyCandidateEvidence() async throws {
        let fixture = try await fixtureEnvironment()
        let observation = try ToolRouter().execute(
            decision: AgentDecision(
                action: .inspectCandidate,
                candidateID: fixture.candidate.id,
                fileReferences: [],
                reason: "Inspect deterministic evidence"
            ),
            environment: fixture.environment
        )

        XCTAssertEqual(observation.type, .candidate)
        XCTAssertEqual(observation.candidateID, fixture.candidate.id)
        for file in fixture.evidence.files {
            XCTAssertTrue(observation.content.contains("\(file.reference):"))
            XCTAssertTrue(observation.content.contains("name=\(file.name)"))
            XCTAssertTrue(observation.content.contains("size=\(file.size)"))
            let allowed = file.allowedDispositions
                .map(\.rawValue)
                .joined(separator: ",")
            XCTAssertTrue(observation.content.contains(
                "allowedDispositions=\(allowed)"
            ))
        }
    }

    func testInspectFileReturnsMetadataForOneValidatedReference() async throws {
        let fixture = try await fixtureEnvironment()
        let target = try XCTUnwrap(fixture.evidence.files.first)
        let observation = try ToolRouter().execute(
            decision: AgentDecision(
                action: .inspectFile,
                candidateID: fixture.candidate.id,
                fileReferences: [target.reference],
                reason: "Inspect one file"
            ),
            environment: fixture.environment
        )

        XCTAssertEqual(observation.type, .metadata)
        XCTAssertEqual(observation.candidateID, fixture.candidate.id)
        XCTAssertTrue(observation.content.contains("reference=\(target.reference)"))
        XCTAssertTrue(observation.content.contains("path=\(target.relativePath)"))
        XCTAssertTrue(observation.content.contains("duplicateCopies=2"))
    }

    func testCompareFilesReturnsExistingComparisonFacts() async throws {
        let fixture = try await fixtureEnvironment()
        XCTAssertEqual(fixture.evidence.files.count, 2)
        let references = fixture.evidence.files.map(\.reference)
        let observation = try ToolRouter().execute(
            decision: AgentDecision(
                action: .compareFiles,
                candidateID: fixture.candidate.id,
                fileReferences: references,
                reason: "Compare verified duplicate metadata"
            ),
            environment: fixture.environment
        )

        XCTAssertEqual(observation.type, .comparison)
        XCTAssertEqual(observation.candidateID, fixture.candidate.id)
        XCTAssertTrue(observation.content.contains("\(references[0]) vs \(references[1])"))
        XCTAssertTrue(observation.content.contains("sameSize=true"))
        for file in fixture.evidence.files {
            XCTAssertTrue(observation.content.contains("name=\(file.name)"))
        }
    }

    func testInspectFileRejectsUnknownReference() async throws {
        let fixture = try await fixtureEnvironment()
        let decision = AgentDecision(
            action: .inspectFile,
            candidateID: fixture.candidate.id,
            fileReferences: ["F999"],
            reason: "Attempt an invalid lookup"
        )

        XCTAssertThrowsError(
            try ToolRouter().execute(
                decision: decision,
                environment: fixture.environment
            )
        ) { error in
            guard case AgentToolError.invalidFileReference(let reference) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(reference, "F999")
            XCTAssertEqual(error.localizedDescription, "Unknown file reference: F999.")
        }
    }

    func testRouterRejectsInvalidShapeAndNonToolActions() async throws {
        let fixture = try await fixtureEnvironment()
        let router = ToolRouter()

        XCTAssertThrowsError(
            try router.execute(
                decision: AgentDecision(
                    action: .inspectCandidate,
                    candidateID: nil,
                    fileReferences: [],
                    reason: "Missing candidate"
                ),
                environment: fixture.environment
            )
        ) { error in
            guard case AgentToolError.missingCandidate = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertThrowsError(
            try router.execute(
                decision: AgentDecision(
                    action: .inspectFile,
                    candidateID: fixture.candidate.id,
                    fileReferences: [],
                    reason: "Missing reference"
                ),
                environment: fixture.environment
            )
        ) { error in
            guard case AgentToolError.wrongFileCount = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertThrowsError(
            try router.execute(
                decision: AgentDecision(
                    action: .finishCandidate,
                    candidateID: fixture.candidate.id,
                    fileReferences: [],
                    reason: "Finish"
                ),
                environment: fixture.environment
            )
        ) { error in
            guard case AgentToolError.notAToolAction = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
