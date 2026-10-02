import CoreGraphics
import CoreText
import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class ContentInspectionTests: XCTestCase {
    private enum PDFTestError: Error {
        case cannotCreateConsumer
        case cannotCreateContext
    }

    func testPDFKitExtractsRealTextWithBoundedExcerpt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orderly-PDF-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("annual-report.pdf")
        let text = String(
            repeating: "Annual Financial Report 2026 revenue and results. ",
            count: 20
        )
        try writeTextPDF(
            at: url,
            pages: [text, "Second page appendix."]
        )

        let observation = try PDFTextExtractor().inspectPDF(
            at: url,
            fileReference: "F1",
            maxExcerptCharacters: 120
        )

        XCTAssertEqual(observation.contentType, "application/pdf")
        XCTAssertEqual(observation.pageCount, 2)
        XCTAssertGreaterThan(observation.extractedCharacterCount, 120)
        XCTAssertLessThanOrEqual(observation.excerpt.count, 120)
        XCTAssertTrue(observation.excerpt.contains("Annual Financial Report"))
        XCTAssertTrue(observation.truncated)
    }

    private func writeTextPDF(
        at url: URL,
        pages: [String]
    ) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw PDFTestError.cannotCreateConsumer
        }

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(
            consumer: consumer,
            mediaBox: &mediaBox,
            nil
        ) else {
            throw PDFTestError.cannotCreateContext
        }

        for text in pages {
            context.beginPDFPage(nil)
            let font = CTFontCreateWithName(
                "Helvetica" as CFString,
                12,
                nil
            )
            let attributed = NSAttributedString(
                string: text,
                attributes: [
                    NSAttributedString.Key(
                        kCTFontAttributeName as String
                    ): font
                ]
            )
            let framesetter = CTFramesetterCreateWithAttributedString(
                attributed
            )
            let path = CGPath(
                rect: CGRect(x: 50, y: 50, width: 512, height: 692),
                transform: nil
            )
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: 0, length: 0),
                path,
                nil
            )
            CTFrameDraw(frame, context)
            context.endPDFPage()
        }

        context.closePDF()
    }
}
