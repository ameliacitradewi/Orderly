import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class ImageSemanticVisionOnlyFastPathTests: XCTestCase {
    private final class StubVisionModel: VisionLanguageService {
        let response: String

        init(response: String) {
            self.response = response
        }

        func generate(prompt: String, imageURL: URL) async throws -> String {
            response
        }
    }

    private final class NeverTextModel: LLMService {
        private(set) var calls = 0

        func generate(prompt: String) async throws -> String {
            calls += 1
            throw TestError.unexpectedTextModelCall
        }
    }

    private enum TestError: Error {
        case unexpectedTextModelCall
    }

    private func evidence() -> ImageEvidenceObservation {
        ImageEvidenceObservation(
            fileID: UUID(),
            localReference: "F1",
            globalReference: "G1",
            contentType: "public.png",
            width: 960,
            height: 600,
            frameCount: 1,
            orientation: 1
        )
    }

    func testVisionOnlyFastPathUsesExplicitScreenshotProseWithoutQwenStructuring() async throws {
        let vision = StubVisionModel(
            response: "A screenshot of the Orderly settings page with a sidebar and Choose Folder button."
        )
        let text = NeverTextModel()
        let analyzer = StructuredImageSemanticAnalyzer(
            visionModel: vision,
            textModel: text,
            preferVisionOnly: true
        )

        let result = try await analyzer.analyze(
            imageURL: URL(fileURLWithPath: "/tmp/settings.png"),
            evidence: evidence()
        )

        XCTAssertEqual(text.calls, 0)
        XCTAssertEqual(result.contentKind, .screenshot)
        XCTAssertEqual(result.confidence, 0.75, accuracy: 0.0001)
        XCTAssertTrue(result.summary.contains("Orderly settings page"))
    }

    func testVisionOnlyFastPathKeepsAmbiguousProseUncertainWithoutQwenStructuring() async throws {
        let vision = StubVisionModel(
            response: "A rectangular visual with text, controls, and several panels."
        )
        let text = NeverTextModel()
        let analyzer = StructuredImageSemanticAnalyzer(
            visionModel: vision,
            textModel: text,
            preferVisionOnly: true
        )

        let result = try await analyzer.analyze(
            imageURL: URL(fileURLWithPath: "/tmp/ambiguous.png"),
            evidence: evidence()
        )

        XCTAssertEqual(text.calls, 0)
        XCTAssertEqual(result.contentKind, .uncertain)
        XCTAssertEqual(result.confidence, 0.5, accuracy: 0.0001)
        XCTAssertFalse(result.summary.isEmpty)
    }
}
