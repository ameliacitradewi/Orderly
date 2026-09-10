import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import OrderlyCore

@MainActor
final class ImageAgentToolTests: XCTestCase {
    private struct StubImageSemanticAnalyzer: ImageSemanticAnalyzing {
        func analyze(
            imageURL: URL,
            evidence: ImageEvidenceObservation
        ) async throws -> ImageSemanticObservation {
            ImageSemanticObservation(
                fileID: evidence.fileID,
                localReference: evidence.localReference,
                globalReference: evidence.globalReference,
                contentKind: .screenshot,
                summary: "A software settings screen with a sidebar and controls.",
                confidence: 0.9
            )
        }
    }

    private struct StubPairSemanticAnalyzer: ImagePairSemanticAnalyzing {
        func analyze(
            first: ImageSemanticObservation,
            second: ImageSemanticObservation,
            deterministic: DeterministicImageComparison
        ) async throws -> ImageSemanticAssessment {
            ImageSemanticAssessment(
                relationship: .sameImageVariant,
                confidence: 0.87,
                summary: "The images appear to be visual variants of the same underlying settings screen."
            )
        }
    }

    func testRouterInspectsLocalAndGlobalImagesThenComparesThem() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let router = ToolRouter(
            imageSemanticAnalyzer: StubImageSemanticAnalyzer(),
            imagePairSemanticAnalyzer: StubPairSemanticAnalyzer()
        )
        let candidateID = fixture.candidate.id
        let g1 = try XCTUnwrap(
            fixture.environment.globalReferenceByFileID[fixture.first.id]
        )
        let g2 = try XCTUnwrap(
            fixture.environment.globalReferenceByFileID[fixture.second.id]
        )

        let overview = try router.execute(
            decision: AgentDecision(
                action: .inspectCandidate,
                candidateID: candidateID,
                fileReferences: [],
                reason: "overview"
            ),
            environment: fixture.environment
        )
        XCTAssertEqual(overview.imageFileReferences, ["F1"])

        let local = try await router.executeAsync(
            decision: AgentDecision(
                action: .inspectImageContent,
                candidateID: candidateID,
                fileReferences: ["F1"],
                reason: "inspect local image"
            ),
            environment: fixture.environment,
            observations: [overview]
        )
        XCTAssertEqual(local.type, .imageContent)
        XCTAssertEqual(local.imageSemantic?.contentKind, .screenshot)
        XCTAssertEqual(local.imageSemantic?.globalReference, g1)

        let discovery = AgentObservation(
            type: .discovery,
            candidateID: candidateID,
            content: "external image discovered",
            globalReferences: [g2],
            imageGlobalReferences: [g2]
        )
        let external = try await router.executeAsync(
            decision: AgentDecision(
                action: .inspectGlobalImageContent,
                candidateID: candidateID,
                fileReferences: [g2],
                reason: "inspect external image"
            ),
            environment: fixture.environment,
            observations: [overview, local, discovery]
        )
        XCTAssertEqual(external.type, .imageContent)
        XCTAssertNil(external.imageSemantic?.localReference)
        XCTAssertEqual(external.imageSemantic?.globalReference, g2)

        let comparison = try await router.executeAsync(
            decision: AgentDecision(
                action: .compareImageContent,
                candidateID: candidateID,
                fileReferences: [g1, g2],
                reason: "compare visual relationship"
            ),
            environment: fixture.environment,
            observations: [overview, local, discovery, external]
        )

        XCTAssertEqual(comparison.type, .imageSemanticComparison)
        XCTAssertEqual(
            comparison.imageSemanticComparison?.semantic.relationship,
            .sameImageVariant
        )
        XCTAssertEqual(
            Set(comparison.imageSemanticComparison?.fileIDs ?? []),
            Set([fixture.first.id, fixture.second.id])
        )
        XCTAssertTrue(comparison.content.contains("not exact-duplicate verification"))
    }

    func testRelatedFindingAcceptsCitedImageSemanticComparison() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let g1 = try XCTUnwrap(
            fixture.environment.globalReferenceByFileID[fixture.first.id]
        )
        let g2 = try XCTUnwrap(
            fixture.environment.globalReferenceByFileID[fixture.second.id]
        )
        let deterministic = DeterministicImageComparison(
            fileIDs: [fixture.first.id, fixture.second.id],
            globalReferences: [g1, g2],
            sameDimensions: true,
            aspectRatioDifference: 0,
            featurePrintDistance: 0.05
        )
        let semantic = ImageSemanticAssessment(
            relationship: .sameImageVariant,
            confidence: 0.9,
            summary: "The images are visual variants of the same screen."
        )
        let comparison = ImageComparisonObservation(
            fileIDs: deterministic.fileIDs,
            globalReferences: [g1, g2],
            deterministic: deterministic,
            semantic: semantic
        )
        let observation = AgentObservation(
            type: .imageSemanticComparison,
            candidateID: fixture.candidate.id,
            content: "semanticRelationship=sameImageVariant",
            globalReferences: [g1, g2],
            imageComparison: deterministic,
            imageSemanticComparison: comparison
        )
        let finding = AgentFinding(
            candidateID: fixture.candidate.id,
            relationship: .related,
            summary: "The candidate image is visually related to another image in the folder.",
            evidence: [
                AgentEvidenceReference(
                    observationID: observation.id,
                    description: "The cited image comparison classified the pair as sameImageVariant."
                )
            ],
            proposals: [
                AgentFileProposal(
                    fileReference: "F1",
                    disposition: .review,
                    reason: "Visual similarity does not establish deletion safety."
                )
            ],
            confidence: 0.9
        )

        let issues = AgentPlanValidator().validate(
            finding: finding,
            candidate: fixture.candidate,
            evidence: fixture.evidence,
            observations: [observation]
        )
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "\n"))
    }

    func testImageVariantCannotSupportExactDuplicateWithoutSHAComparison() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let g1 = try XCTUnwrap(
            fixture.environment.globalReferenceByFileID[fixture.first.id]
        )
        let g2 = try XCTUnwrap(
            fixture.environment.globalReferenceByFileID[fixture.second.id]
        )
        let deterministic = DeterministicImageComparison(
            fileIDs: [fixture.first.id, fixture.second.id],
            globalReferences: [g1, g2],
            sameDimensions: true,
            aspectRatioDifference: 0,
            featurePrintDistance: 0
        )
        let observation = AgentObservation(
            type: .imageSemanticComparison,
            candidateID: fixture.candidate.id,
            content: "semanticRelationship=sameImageVariant",
            imageComparison: deterministic,
            imageSemanticComparison: ImageComparisonObservation(
                fileIDs: deterministic.fileIDs,
                globalReferences: [g1, g2],
                deterministic: deterministic,
                semantic: ImageSemanticAssessment(
                    relationship: .sameImageVariant,
                    confidence: 1,
                    summary: "Visually the same underlying image."
                )
            )
        )
        let finding = AgentFinding(
            candidateID: fixture.candidate.id,
            relationship: .exactDuplicate,
            summary: "The images are exact duplicates.",
            evidence: [
                AgentEvidenceReference(
                    observationID: observation.id,
                    description: "The image comparison found a same-image variant."
                )
            ],
            proposals: [
                AgentFileProposal(
                    fileReference: "F1",
                    disposition: .review,
                    reason: "Review."
                )
            ],
            confidence: 1
        )

        let issues = AgentPlanValidator().validate(
            finding: finding,
            candidate: fixture.candidate,
            evidence: fixture.evidence,
            observations: [observation]
        )
        XCTAssertTrue(
            issues.contains("Duplicate claims require an observation with verifiedDuplicate=true.")
        )
    }

    private struct Fixture {
        let root: URL
        let first: FileMetadata
        let second: FileMetadata
        let candidate: AnalysisCandidate
        let evidence: CandidateEvidence
        let environment: AgentEnvironment
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orderly-Image-Agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let firstURL = root.appendingPathComponent("settings-1.png")
        let secondURL = root.appendingPathComponent("settings-2.png")
        try writeImage(at: firstURL, inverted: false)
        try writeImage(at: secondURL, inverted: false)

        let first = metadata(firstURL)
        let second = metadata(secondURL)
        let candidate = AnalysisCandidate(
            id: UUID(),
            type: .grouping,
            fileIDs: [first.id],
            confidence: 1,
            reason: "image fixture"
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
            analyzedAt: Date(),
            files: [first, second],
            unreadableHashCount: 0
        )
        let environment = AgentEnvironment(
            analysis: analysis,
            evidence: [evidence]
        )
        return Fixture(
            root: root,
            first: first,
            second: second,
            candidate: candidate,
            evidence: evidence,
            environment: environment
        )
    }

    private func metadata(_ url: URL) -> FileMetadata {
        let values = try? url.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey]
        )
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

    private func writeImage(at url: URL, inverted: Bool) throws {
        let width = 96
        let height = 64
        var pixels = [UInt8](
            repeating: inverted ? 225 : 30,
            count: width * height
        )
        for y in (height / 4)..<(height * 3 / 4) {
            for x in (width / 4)..<(width * 3 / 4) {
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
            throw NSError(domain: "ImageAgentToolTests", code: 1)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ImageAgentToolTests", code: 2)
        }
    }
}
