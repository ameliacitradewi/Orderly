import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class ImageSemanticSummaryBoundaryTests: XCTestCase {
    private final class StubVisionModel: VisionLanguageService {
        let response: String

        init(response: String) {
            self.response = response
        }

        func generate(prompt: String, imageURL: URL) async throws -> String {
            response
        }
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

    func testVisionOnlySummaryPrefersCompleteSentenceBeforeWordLimit() async throws {
        let longTail = Array(repeating: "additional", count: 60)
            .joined(separator: " ")
        let vision = StubVisionModel(
            response: "A screenshot shows the Orderly settings page. \(longTail)"
        )
        let analyzer = StructuredImageSemanticAnalyzer(
            visionModel: vision,
            preferVisionOnly: true
        )

        let result = try await analyzer.analyze(
            imageURL: URL(fileURLWithPath: "/tmp/settings.png"),
            evidence: evidence()
        )

        XCTAssertEqual(
            result.summary,
            "A screenshot shows the Orderly settings page."
        )
        XCTAssertEqual(result.contentKind, .screenshot)
    }

    func testVisionOnlySummaryWithoutSentenceBoundaryEndsAtWordBoundary() async throws {
        let words = (1...70).map { "word\($0)" }.joined(separator: " ")
        let vision = StubVisionModel(response: "A screenshot \(words)")
        let analyzer = StructuredImageSemanticAnalyzer(
            visionModel: vision,
            preferVisionOnly: true
        )

        let result = try await analyzer.analyze(
            imageURL: URL(fileURLWithPath: "/tmp/settings.png"),
            evidence: evidence()
        )

        XCTAssertTrue(result.summary.hasSuffix("…"))
        XCTAssertFalse(result.summary.hasSuffix("word"))
        XCTAssertLessThanOrEqual(
            result.summary.split(whereSeparator: \.isWhitespace).count,
            45
        )
    }
}
