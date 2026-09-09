import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import OrderlyCore

@MainActor
final class ImageEvidenceTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let first: FileMetadata
        let second: FileMetadata
        let different: FileMetadata
        let candidate: AnalysisCandidate
        let environment: AgentEnvironment
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orderly-Image-Evidence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let firstURL = root.appendingPathComponent("screen-1.png")
        let secondURL = root.appendingPathComponent("screen-2.png")
        let differentURL = root.appendingPathComponent("different.png")
        try writeImage(at: firstURL, width: 96, height: 64, inverted: false)
        try FileManager.default.copyItem(at: firstURL, to: secondURL)
        try writeImage(at: differentURL, width: 96, height: 64, inverted: true)

        let first = metadata(firstURL)
        let second = metadata(secondURL)
        let different = metadata(differentURL)
        let candidate = AnalysisCandidate(
            id: UUID(),
            type: .grouping,
            fileIDs: [first.id],
            confidence: 1,
            reason: "Image evidence fixture"
        )
        let candidateEvidence = CandidateEvidence(
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
                )
            ]
        )
        let analysis = AnalysisResult(
            analyzedFolder: root,
            totalFiles: 3,
            totalSize: first.size + second.size + different.size,
            fileTypes: [],
            duplicateGroups: [],
            candidates: [candidate],
            analyzedAt: Date(),
            files: [first, second, different],
            unreadableHashCount: 0
        )
        return Fixture(
            root: root,
            first: first,
            second: second,
            different: different,
            candidate: candidate,
            environment: AgentEnvironment(
                analysis: analysis,
                evidence: [candidateEvidence]
            )
        )
    }

    override func tearDown() {
        super.tearDown()
        let directory = FileManager.default.temporaryDirectory
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for child in children where child.lastPathComponent.hasPrefix("Orderly-Image-Evidence-") {
            try? FileManager.default.removeItem(at: child)
        }
    }

    func testInspectionReadsTrustedRasterMetadata() throws {
        let fixture = try fixture()
        let global = try XCTUnwrap(
            fixture.environment.globalReferenceByFileID[fixture.first.id]
        )

        let observation = try InspectImageEvidenceTool().execute(
            file: fixture.first,
            localReference: "F1",
            globalReference: global,
            candidateID: fixture.candidate.id,
            analyzedFolder: fixture.root
        )

        XCTAssertEqual(observation.type, .imageEvidence)
        XCTAssertEqual(observation.imageEvidence?.fileID, fixture.first.id)
        XCTAssertEqual(observation.imageEvidence?.localReference, "F1")
        XCTAssertEqual(observation.imageEvidence?.globalReference, global)
        XCTAssertEqual(observation.imageEvidence?.width, 96)
        XCTAssertEqual(observation.imageEvidence?.height, 64)
        XCTAssertEqual(observation.imageEvidence?.frameCount, 1)
        XCTAssertEqual(observation.imageGlobalReferences, [global])
        XCTAssertFalse(observation.imageEvidence?.contentType.isEmpty ?? true)
    }

    func testVisionFeatureDistanceRanksIdenticalPixelsCloserThanDifferentPixels() throws {
        let fixture = try fixture()
        let service = AppleImageEvidenceService()
        let g1 = try XCTUnwrap(fixture.environment.globalReferenceByFileID[fixture.first.id])
        let g2 = try XCTUnwrap(fixture.environment.globalReferenceByFileID[fixture.second.id])
        let g3 = try XCTUnwrap(fixture.environment.globalReferenceByFileID[fixture.different.id])
        let first = try service.inspectImage(
            at: fixture.first.url,
            fileID: fixture.first.id,
            localReference: "F1",
            globalReference: g1
        )
        let second = try service.inspectImage(
            at: fixture.second.url,
            fileID: fixture.second.id,
            localReference: nil,
            globalReference: g2
        )
        let different = try service.inspectImage(
            at: fixture.different.url,
            fileID: fixture.different.id,
            localReference: nil,
            globalReference: g3
        )

        let identicalComparison = try service.compareImages(
            firstURL: fixture.first.url,
            secondURL: fixture.second.url,
            first: first,
            second: second
        )
        let differentComparison = try service.compareImages(
            firstURL: fixture.first.url,
            secondURL: fixture.different.url,
            first: first,
            second: different
        )

        XCTAssertTrue(identicalComparison.featurePrintDistance.isFinite)
        XCTAssertTrue(differentComparison.featurePrintDistance.isFinite)
        XCTAssertLessThanOrEqual(
            identicalComparison.featurePrintDistance,
            differentComparison.featurePrintDistance
        )
        XCTAssertTrue(identicalComparison.sameDimensions)
        XCTAssertEqual(identicalComparison.aspectRatioDifference, 0, accuracy: 0.0001)
    }

    func testComparisonRequiresObservedInspectedImagesAndStaysNonDestructive() throws {
        let fixture = try fixture()
        let g1 = try XCTUnwrap(fixture.environment.globalReferenceByFileID[fixture.first.id])
        let g2 = try XCTUnwrap(fixture.environment.globalReferenceByFileID[fixture.second.id])
        let inspector = InspectImageEvidenceTool()
        let firstEvidence = try inspector.execute(
            file: fixture.first,
            localReference: "F1",
            globalReference: g1,
            candidateID: fixture.candidate.id,
            analyzedFolder: fixture.root
        )
        let secondEvidence = try inspector.execute(
            file: fixture.second,
            localReference: nil,
            globalReference: g2,
            candidateID: fixture.candidate.id,
            analyzedFolder: fixture.root
        )
        let discovery = AgentObservation(
            type: .discovery,
            candidateID: fixture.candidate.id,
            content: "external image discovered",
            globalReferences: [g1, g2],
            imageGlobalReferences: [g2]
        )

        let comparison = try CompareImageEvidenceTool().execute(
            references: [g1, g2],
            candidateID: fixture.candidate.id,
            environment: fixture.environment,
            observations: [firstEvidence, discovery, secondEvidence]
        )

        XCTAssertEqual(comparison.type, .imageComparison)
        XCTAssertEqual(Set(comparison.imageComparison?.fileIDs ?? []), Set([fixture.first.id, fixture.second.id]))
        XCTAssertTrue(comparison.content.contains("not exact-duplicate verification"))
        XCTAssertTrue(comparison.content.contains("never authorizes deletion"))
    }

    func testComparisonRejectsUnobservedGlobalReference() throws {
        let fixture = try fixture()
        let g1 = try XCTUnwrap(fixture.environment.globalReferenceByFileID[fixture.first.id])
        let g2 = try XCTUnwrap(fixture.environment.globalReferenceByFileID[fixture.second.id])
        let firstEvidence = try InspectImageEvidenceTool().execute(
            file: fixture.first,
            localReference: "F1",
            globalReference: g1,
            candidateID: fixture.candidate.id,
            analyzedFolder: fixture.root
        )

        XCTAssertThrowsError(
            try CompareImageEvidenceTool().execute(
                references: [g1, g2],
                candidateID: fixture.candidate.id,
                environment: fixture.environment,
                observations: [firstEvidence]
            )
        ) { error in
            guard case AgentToolError.unobservedGlobalReference(let reference) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(reference, g2)
        }
    }

    func testImageInspectionRejectsFilesOutsideAnalyzedFolder() throws {
        let fixture = try fixture()
        let outsideRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orderly-Outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideRoot) }
        let outsideURL = outsideRoot.appendingPathComponent("outside.png")
        try writeImage(at: outsideURL, width: 32, height: 32, inverted: false)
        let outside = metadata(outsideURL)

        XCTAssertThrowsError(
            try InspectImageEvidenceTool().execute(
                file: outside,
                localReference: nil,
                globalReference: "G999",
                candidateID: fixture.candidate.id,
                analyzedFolder: fixture.root
            )
        ) { error in
            guard case ImageEvidenceError.fileOutsideAnalyzedFolder = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func metadata(_ url: URL) -> FileMetadata {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return FileMetadata(
            id: UUID(),
            url: url,
            name: url.lastPathComponent,
            extensionName: url.pathExtension,
            size: Int64(values?.fileSize ?? 0),
            createdAt: nil,
            modifiedAt: values?.contentModificationDate,
            accessedAt: nil,
            isDirectory: false,
            isHidden: false,
            uti: "public.png",
            classification: .image
        )
    }

    private func writeImage(
        at url: URL,
        width: Int,
        height: Int,
        inverted: Bool
    ) throws {
        var pixels = [UInt8](repeating: inverted ? 225 : 30, count: width * height)
        let xStart = width / 4
        let xEnd = width * 3 / 4
        let yStart = height / 4
        let yEnd = height * 3 / 4
        for y in yStart..<yEnd {
            for x in xStart..<xEnd {
                pixels[y * width + x] = inverted ? 30 : 225
            }
        }

        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: 0),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                "public.png" as CFString,
                1,
                nil
              ) else {
            throw NSError(domain: "ImageEvidenceTests", code: 1)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ImageEvidenceTests", code: 2)
        }
    }
}
