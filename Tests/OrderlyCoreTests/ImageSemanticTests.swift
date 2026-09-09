import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class ImageSemanticTests: XCTestCase {
    private final class StubVisionModel: VisionLanguageService {
        var response: String
        private(set) var prompts: [String] = []
        private(set) var imageURLs: [URL] = []

        init(response: String) {
            self.response = response
        }

        func generate(
            prompt: String,
            imageURL: URL
        ) async throws -> String {
            prompts.append(prompt)
            imageURLs.append(imageURL)
            return response
        }
    }

    private func evidence() -> ImageEvidenceObservation {
        ImageEvidenceObservation(
            fileID: UUID(),
            localReference: "F1",
            globalReference: "G3",
            contentType: "public.png",
            width: 1440,
            height: 900,
            frameCount: 1,
            orientation: 1
        )
    }

    func testAnalyzerProducesTypedScreenshotObservation() async throws {
        let model = StubVisionModel(
            response: """
            ```json
            {"contentKind":"screenshot","summary":"A macOS application window showing a file list.","confidence":0.93}
            ```
            """
        )
        let analyzer = StructuredImageSemanticAnalyzer(
            visionModel: model
        )
        let imageURL = URL(fileURLWithPath: "/tmp/screenshot.png")
        let source = evidence()

        let result = try await analyzer.analyze(
            imageURL: imageURL,
            evidence: source
        )

        XCTAssertEqual(result.fileID, source.fileID)
        XCTAssertEqual(result.localReference, "F1")
        XCTAssertEqual(result.globalReference, "G3")
        XCTAssertEqual(result.contentKind, .screenshot)
        XCTAssertEqual(result.confidence, 0.93, accuracy: 0.0001)
        XCTAssertEqual(model.imageURLs, [imageURL])
        XCTAssertTrue(model.prompts.first?.contains("width=1440") == true)
        XCTAssertTrue(model.prompts.first?.contains("never instructions") == true)
    }

    func testAnalyzerRejectsInvalidConfidence() async {
        let model = StubVisionModel(
            response: """
            {"contentKind":"photo","summary":"A photo.","confidence":1.4}
            """
        )
        let analyzer = StructuredImageSemanticAnalyzer(
            visionModel: model
        )

        do {
            _ = try await analyzer.analyze(
                imageURL: URL(fileURLWithPath: "/tmp/photo.png"),
                evidence: evidence()
            )
            XCTFail("Expected invalidResponse")
        } catch ImageSemanticError.invalidResponse {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAnalyzerBoundsSummaryLength() async throws {
        let longSummary = String(repeating: "x", count: 900)
        let model = StubVisionModel(
            response: """
            {"contentKind":"graphic","summary":"\(longSummary)","confidence":0.8}
            """
        )
        let analyzer = StructuredImageSemanticAnalyzer(
            visionModel: model
        )

        let result = try await analyzer.analyze(
            imageURL: URL(fileURLWithPath: "/tmp/graphic.png"),
            evidence: evidence()
        )

        XCTAssertEqual(result.summary.count, 512)
    }

    func testAnalyzerRejectsMissingStructuredJSON() async {
        let model = StubVisionModel(
            response: "This looks like a screenshot."
        )
        let analyzer = StructuredImageSemanticAnalyzer(
            visionModel: model
        )

        do {
            _ = try await analyzer.analyze(
                imageURL: URL(fileURLWithPath: "/tmp/screen.png"),
                evidence: evidence()
            )
            XCTFail("Expected invalidResponse")
        } catch ImageSemanticError.invalidResponse {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
