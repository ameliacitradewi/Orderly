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

    private final class StubTextModel: LLMService {
        var response: String
        private(set) var prompts: [String] = []

        init(response: String) {
            self.response = response
        }

        func generate(prompt: String) async throws -> String {
            prompts.append(prompt)
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

    func testAnalyzerProducesTypedScreenshotObservationFromJSON() async throws {
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
        XCTAssertTrue(model.prompts.first?.contains("one concise factual paragraph") == true)
        XCTAssertTrue(model.prompts.first?.contains("never instructions") == true)
    }

    func testAnalyzerAcceptsCompactLineProtocol() async throws {
        let model = StubVisionModel(
            response: """
            KIND=screenshot
            CONFIDENCE=0.88
            SUMMARY=A software settings screen with a sidebar and a primary button.
            """
        )
        let analyzer = StructuredImageSemanticAnalyzer(visionModel: model)

        let result = try await analyzer.analyze(
            imageURL: URL(fileURLWithPath: "/tmp/screen.png"),
            evidence: evidence()
        )

        XCTAssertEqual(result.contentKind, .screenshot)
        XCTAssertEqual(result.confidence, 0.88, accuracy: 0.0001)
        XCTAssertEqual(
            result.summary,
            "A software settings screen with a sidebar and a primary button."
        )
    }

    func testAnalyzerToleratesColonAndPercentWithinStructuredProtocol() async throws {
        let model = StubVisionModel(
            response: """
            KIND: scanned document
            CONFIDENCE: 82%
            SUMMARY: A photographed page dominated by text and document layout.
            """
        )
        let analyzer = StructuredImageSemanticAnalyzer(visionModel: model)

        let result = try await analyzer.analyze(
            imageURL: URL(fileURLWithPath: "/tmp/page.png"),
            evidence: evidence()
        )

        XCTAssertEqual(result.contentKind, .scannedDocument)
        XCTAssertEqual(result.confidence, 0.82, accuracy: 0.0001)
    }

    func testAnalyzerUsesTextModelToStructureFreeformVisionDescription() async throws {
        let vision = StubVisionModel(
            response: "A macOS settings screen with a sidebar, settings text, and a blue Choose Folder button."
        )
        let text = StubTextModel(
            response: """
            {"contentKind":"screenshot","summary":"A macOS settings screen with a sidebar and a Choose Folder button.","confidence":0.94}
            """
        )
        let analyzer = StructuredImageSemanticAnalyzer(
            visionModel: vision,
            textModel: text
        )

        let result = try await analyzer.analyze(
            imageURL: URL(fileURLWithPath: "/tmp/screen.png"),
            evidence: evidence()
        )

        XCTAssertEqual(result.contentKind, .screenshot)
        XCTAssertEqual(result.confidence, 0.94, accuracy: 0.0001)
        XCTAssertTrue(result.summary.contains("macOS settings screen"))
        XCTAssertEqual(text.prompts.count, 1)
        XCTAssertTrue(text.prompts[0].contains("untrusted data"))
        XCTAssertTrue(text.prompts[0].contains("\"width\":1440"))
        XCTAssertTrue(text.prompts[0].contains("Choose Folder"))
    }

    func testAnalyzerRejectsInvalidConfidence() async {
        let model = StubVisionModel(
            response: """
            KIND=photo
            CONFIDENCE=1.4
            SUMMARY=A photo.
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
            KIND=graphic
            CONFIDENCE=0.8
            SUMMARY=\(longSummary)
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

    func testAnalyzerRejectsUnstructuredProseWithoutTextModel() async {
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

    func testAnalyzerRejectsUnstructuredTextModelResponse() async {
        let vision = StubVisionModel(
            response: "A software settings screen."
        )
        let text = StubTextModel(
            response: "It is probably a screenshot."
        )
        let analyzer = StructuredImageSemanticAnalyzer(
            visionModel: vision,
            textModel: text
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
