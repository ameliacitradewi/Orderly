import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class ExecutionEngineHardeningTests: XCTestCase {
    func testMissingMoveSourceIsSafelySkippedAndOtherFileStillMoves() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let missingURL = root.appendingPathComponent("missing.txt")
        let survivingURL = root.appendingPathComponent("surviving.txt")
        try Data("missing".utf8).write(to: missingURL)
        try Data("surviving".utf8).write(to: survivingURL)

        let missing = try metadata(at: missingURL)
        let surviving = try metadata(at: survivingURL)
        try FileManager.default.removeItem(at: missingURL)

        let destination = root.appendingPathComponent(FileType.document.tagName, isDirectory: true)
        let action = ExecutionAction(
            sourceActionID: UUID(),
            type: .move,
            fileIDs: [missing.id, surviving.id],
            destination: destination
        )
        let plan = ExecutionPlan(
            cleanupPlanID: UUID(),
            selectedActions: [action]
        )

        let result = try await ExecutionEngine(
            requiresSecurityScopedAccess: false
        ).execute(
            plan: plan,
            files: [missing, surviving],
            rootFolder: root,
            onProgress: { _ in }
        )

        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.succeededCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertFalse(result.isFullySuccessful)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent(surviving.name).path
            )
        )
    }

    func testChangedMoveSourceIsSkippedBeforeMutation() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("proposal.txt")
        try Data("original".utf8).write(to: sourceURL)
        let original = try metadata(at: sourceURL)

        try Data("changed after approval".utf8).write(to: sourceURL)

        let destination = root.appendingPathComponent(FileType.document.tagName, isDirectory: true)
        let plan = ExecutionPlan(
            cleanupPlanID: UUID(),
            selectedActions: [
                ExecutionAction(
                    sourceActionID: UUID(),
                    type: .move,
                    fileIDs: [original.id],
                    destination: destination
                )
            ]
        )

        let result = try await ExecutionEngine(
            requiresSecurityScopedAccess: false
        ).execute(
            plan: plan,
            files: [original],
            rootFolder: root,
            onProgress: { _ in }
        )

        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.succeededCount, 0)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent(original.name).path
            )
        )
        XCTAssertTrue(result.records[0].message.contains("changed after scanning"))
    }

    func testMoveCollisionUsesDeterministicAvailableName() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("report.txt")
        try Data("new report".utf8).write(to: sourceURL)
        let source = try metadata(at: sourceURL)

        let destination = root.appendingPathComponent(FileType.document.tagName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: false
        )
        let occupied = destination.appendingPathComponent("report.txt")
        try Data("existing report".utf8).write(to: occupied)

        let plan = ExecutionPlan(
            cleanupPlanID: UUID(),
            selectedActions: [
                ExecutionAction(
                    sourceActionID: UUID(),
                    type: .move,
                    fileIDs: [source.id],
                    destination: destination
                )
            ]
        )

        let result = try await ExecutionEngine(
            requiresSecurityScopedAccess: false
        ).execute(
            plan: plan,
            files: [source],
            rootFolder: root,
            onProgress: { _ in }
        )

        XCTAssertEqual(result.succeededCount, 1)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: occupied.path))
        XCTAssertEqual(
            result.records.first?.resultingURL?.lastPathComponent,
            "report (2).txt"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("report (2).txt").path
            )
        )
    }

    func testCreateFolderNameConflictIsSafelySkipped() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let destination = root.appendingPathComponent("Documents")
        try Data("not a folder".utf8).write(to: destination)

        let plan = ExecutionPlan(
            cleanupPlanID: UUID(),
            selectedActions: [
                ExecutionAction(
                    sourceActionID: UUID(),
                    type: .createFolder,
                    fileIDs: [],
                    destination: destination
                )
            ]
        )

        let result = try await ExecutionEngine(
            requiresSecurityScopedAccess: false
        ).execute(
            plan: plan,
            files: [],
            rootFolder: root,
            onProgress: { _ in }
        )

        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertFalse(result.isFullySuccessful)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testCancelledTaskReturnsPartialSafeResultWithoutStartingMutation() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("cancel-me.txt")
        try Data("leave me here".utf8).write(to: sourceURL)
        let source = try metadata(at: sourceURL)
        let destination = root.appendingPathComponent(FileType.document.tagName, isDirectory: true)
        let plan = ExecutionPlan(
            cleanupPlanID: UUID(),
            selectedActions: [
                ExecutionAction(
                    sourceActionID: UUID(),
                    type: .move,
                    fileIDs: [source.id],
                    destination: destination
                )
            ]
        )
        let engine = ExecutionEngine(requiresSecurityScopedAccess: false)

        let task = Task {
            try await engine.execute(
                plan: plan,
                files: [source],
                rootFolder: root,
                onProgress: { _ in }
            )
        }
        task.cancel()
        let result = try await task.value

        XCTAssertTrue(result.wasCancelled)
        XCTAssertFalse(result.isFullySuccessful)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orderly-Execution-Hardening-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    private func metadata(at url: URL) throws -> FileMetadata {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        var file = FileMetadata(
            id: UUID(),
            url: url,
            name: url.lastPathComponent,
            extensionName: url.pathExtension,
            size: size,
            createdAt: attributes[.creationDate] as? Date,
            modifiedAt: attributes[.modificationDate] as? Date,
            accessedAt: nil,
            isDirectory: false,
            isHidden: false,
            uti: nil
        )
        file.classification = .document
        return file
    }
}
