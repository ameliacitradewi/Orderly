import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class PipelineTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func file(_ name: String, in root: URL, bytes: String = "same", time: TimeInterval = 1) throws -> FileMetadata {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes.utf8).write(to: url)
        let date = Date(timeIntervalSince1970: time)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return FileMetadata(id: UUID(), url: url, name: url.lastPathComponent, extensionName: url.pathExtension,
                            size: Int64(bytes.utf8.count), createdAt: nil, modifiedAt: date, accessedAt: nil,
                            isDirectory: false, isHidden: name.hasPrefix("."), uti: nil)
    }

    private func plan(_ scan: DuplicateScan, root: URL, recommendations: [CleanupRecommendation] = []) -> CleanupPlan {
        let candidates = ClutterAnalyzer().analyze(files: scan.files, duplicateGroups: scan.groups)
        return CleanupPlanBuilder().buildPlan(folder: root, candidates: candidates,
            modelPlan: ModelCleanupPlan(summary: "Fixture", recommendations: recommendations), files: scan.files)
    }

    func testExtensionRulesAndCompoundSuffixes() {
        let expected: [String: FileType] = [
            "REPORT.PDF": .document, "notes.page": .document, "sheet.csv": .document,
            "photo.HEIC": .image, "setup.dmg": .application, "script.python": .code,
            "view.html": .code, ".DS_Store": .artifact, "._photo.jpg": .artifact,
            "bundle.tar.gz": .archive, "scan.nii.gz": .archive, "clip.h264": .video,
            "track.WAV": .audio, "key.ppk": .other, "machine.vmsd": .other,
            "backup.bak": .other, "download.crdownload": .artifact,
            "sample.php8": .code, "state.008": .other, "LICENSE": .other,
            "unknown.veryunusual": .other
        ]
        for (name, type) in expected {
            XCTAssertEqual(ExtensionCatalog.category(for: ExtensionCatalog.key(for: name)) ?? .other, type, name)
        }
        XCTAssertEqual(Set(FileType.allCases.map(\.tagName)), Set([
            "Documents", "Image", "App Installer", "Code", "Artifacts", "ZIP Files", "Video", "Audio", "Others"
        ]))
    }

    func testThreeCopiesAcrossExtensionsKeepNewestAndOrganizeUnique() async throws {
        let root = try fixture()
        let old = try file("old.txt", in: root, time: 1)
        let middle = try file("middle.pdf", in: root, time: 2)
        let newest = try file("new.dmg", in: root, time: 3)
        let different = try file("different.txt", in: root, bytes: "diff", time: 4)
        let scan = try await DuplicateDetector().findDuplicates(in: [old, newest, different, middle])
        XCTAssertEqual(scan.groups.count, 1)
        XCTAssertEqual(scan.groups[0].files.count, 3)
        XCTAssertEqual(scan.groups[0].keeperID, newest.id)
        XCTAssertEqual(scan.files.filter { $0.tags.contains("SHA256 Duplicate") }.count, 3)
        let result = plan(scan, root: root)
        XCTAssertEqual(Set(result.actions.filter { $0.type == .trash }.flatMap(\.fileIDs)), Set([old.id, middle.id]))
        let moves = result.actions.filter { $0.type == .move }
        XCTAssertEqual(moves.flatMap(\.fileIDs), [different.id])
        XCTAssertEqual(moves.first?.destination?.lastPathComponent, "Documents")
        XCTAssertFalse(result.actions.flatMap(\.fileIDs).contains(newest.id))
        XCTAssertTrue(result.actions.allSatisfy { !$0.isSelected })
    }

    func testEqualDatesAreStableAndNewestArtifactIsProtected() async throws {
        let root = try fixture()
        let artifact = try file(".DS_Store", in: root, time: 10)
        let other = try file("z.txt", in: root, time: 10)
        let first = try await DuplicateDetector().findDuplicates(in: [other, artifact])
        let reversed = try await DuplicateDetector().findDuplicates(in: [artifact, other])
        XCTAssertEqual(first.groups[0].keeperID, artifact.id)
        XCTAssertEqual(first.groups[0].keeperID, reversed.groups[0].keeperID)
        XCTAssertFalse(plan(first, root: root).actions.flatMap(\.fileIDs).contains(artifact.id))
    }

    func testLargeDuplicateGroupRetainsOneAcrossBatches() async throws {
        let root = try fixture()
        let files = try (0..<37).map { try file("copy\($0).txt", in: root, time: Double($0)) }
        let scan = try await DuplicateDetector().findDuplicates(in: files)
        let candidates = ClutterAnalyzer().analyze(files: scan.files, duplicateGroups: scan.groups)
        XCTAssertTrue(candidates.allSatisfy { $0.fileIDs.count <= ClutterAnalyzer.batchSize })
        XCTAssertEqual(Set(candidates.flatMap(\.fileIDs)), Set(files.map(\.id)))
        let evidence = EvidenceEngine().buildEvidence(candidates: candidates, files: scan.files,
                                                     duplicateGroups: scan.groups, rootFolder: root)
        for batch in evidence {
            let decisions = batch.files.map { ModelFileDecision(fileReference: $0.reference,
                disposition: $0.requiredDisposition ?? .move, reason: "Fixture") }
            XCTAssertTrue(ModelPlanValidator().issues(decisions: decisions, files: batch.files).isEmpty)
        }
        XCTAssertEqual(plan(scan, root: root).actions.filter { $0.type == .trash }.flatMap(\.fileIDs).count, 36)
    }

    func testEmptyFilesAndMissingDates() async throws {
        let root = try fixture()
        let first = try file("a.txt", in: root, bytes: "")
        let second = try file("b.txt", in: root, bytes: "", time: 2)
        let undated = FileMetadata(id: first.id, url: first.url, name: first.name, extensionName: first.extensionName,
            size: first.size, createdAt: nil, modifiedAt: nil, accessedAt: nil, isDirectory: false, isHidden: false, uti: nil)
        let scan = try await DuplicateDetector().findDuplicates(in: [undated, second])
        XCTAssertEqual(scan.groups.count, 1)
        XCTAssertNil(scan.groups[0].keeperID)
        XCTAssertTrue(plan(scan, root: root).actions.isEmpty)
    }

    func testOnlyRegenerableArtifactsAreDeletedWithoutModelInstallerAdvice() async throws {
        let root = try fixture()
        let names = [".DS_Store", "thumbs.db", "work.tmp", "work.log", "work.bak", "._photo.jpg", "installer.dmg", "key.ppk"]
        let files = try names.enumerated().map { try file($0.element, in: root, bytes: String(repeating: "x", count: $0.offset + 1)) }
        let scan = try await DuplicateDetector().findDuplicates(in: files)
        let deleted = plan(scan, root: root).actions.filter { $0.type == .trash }.flatMap(\.fileIDs)
        XCTAssertEqual(Set(deleted), Set(files.prefix(2).map(\.id)))
    }

    func testMaliciousRecommendationsCannotDeleteDocumentsOrChooseOutsideDestination() throws {
        let root = try fixture()
        let doc = try file("report.pdf", in: root)
        let candidate = AnalysisCandidate(id: UUID(), type: .grouping, fileIDs: [doc.id], confidence: 1, reason: "Fixture")
        let model = ModelCleanupPlan(summary: "Fixture", recommendations: [CleanupRecommendation(
            candidateID: candidate.id.uuidString, title: "Delete", explanation: "Fixture",
            fileDecisions: [ModelFileDecision(fileReference: "F1", disposition: .trash, reason: "Fixture")],
            destinationFolderName: "../../outside", confidence: 1)])
        let result = CleanupPlanBuilder().buildPlan(folder: root, candidates: [candidate], modelPlan: model, files: [doc])
        XCTAssertEqual(result.actions.first?.type, .move)
        XCTAssertEqual(result.actions.first?.destination, root.appendingPathComponent("Documents", isDirectory: true))
    }

    func testInstallerAdviceIsHonoredAndAlreadyOrganizedFilesStayPut() throws {
        let root = try fixture()
        let installer = try file("setup.dmg", in: root)
        let organized = try file("Documents/report.pdf", in: root)
        let candidate = AnalysisCandidate(id: UUID(), type: .grouping, fileIDs: [installer.id], confidence: 1, reason: "Fixture")
        let model = ModelCleanupPlan(summary: "Fixture", recommendations: [CleanupRecommendation(
            candidateID: candidate.id.uuidString, title: "Delete installer", explanation: "After installation",
            fileDecisions: [ModelFileDecision(fileReference: "F1", disposition: .trash, reason: "After installation")],
            destinationFolderName: "", confidence: 1)])
        let result = CleanupPlanBuilder().buildPlan(folder: root, candidates: [candidate], modelPlan: model, files: [installer, organized])
        XCTAssertEqual(result.actions.count, 1)
        XCTAssertEqual(result.actions[0].type, .trash)
        XCTAssertEqual(result.actions[0].fileIDs, [installer.id])
    }

    func testMissingOrChangedKeeperBlocksDeletion() async throws {
        let root = try fixture()
        let older = try file("old.txt", in: root)
        let newer = try file("new.txt", in: root, time: 2)
        let scan = try await DuplicateDetector().findDuplicates(in: [older, newer])
        let lookup = FileLookup(files: scan.files)
        let source = try XCTUnwrap(lookup.file(withID: older.id))
        XCTAssertNoThrow(try DeletionVerifier.verify(file: source, lookup: lookup, root: root))
        // Even a same-length edit with restored modification time must fail the digest check.
        try Data("diff".utf8).write(to: newer.url)
        try FileManager.default.setAttributes([.modificationDate: newer.modifiedAt!], ofItemAtPath: newer.url.path)
        XCTAssertThrowsError(try DeletionVerifier.verify(file: source, lookup: lookup, root: root))
        try FileManager.default.removeItem(at: newer.url)
        XCTAssertThrowsError(try DeletionVerifier.verify(file: source, lookup: lookup, root: root))
    }

    func testDocumentPackagesUseContentAndRelativePathsAndScannerSkipsSymlinks() async throws {
        let root = try fixture()
        _ = try file("a.pages/Index/document", in: root)
        _ = try file("b.pages/Index/document", in: root)
        _ = try file("c.pages/Index/different", in: root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.pages"),
                                                   withDestinationURL: root.appendingPathComponent("a.pages"))
        let files = try await FileSystemService().scanDirectory(at: root)
        XCTAssertEqual(files.count, 3)
        XCTAssertTrue(files.allSatisfy(\.isDirectory))
        let scan = try await DuplicateDetector().findDuplicates(in: files)
        XCTAssertEqual(scan.groups.count, 1)
        XCTAssertEqual(scan.groups[0].files.count, 2)
        let duplicates = FileLookup(files: scan.files).files(withIDs: scan.groups[0].files)
        XCTAssertEqual(Set(duplicates.map(\.name)), Set(["a.pages", "b.pages"]))
    }
}
