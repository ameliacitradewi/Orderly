import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class ContentInspectionTests: XCTestCase {
    private func makePDF(at url: URL, text: String) throws {
        #if canImport(PDFKit)
        import PDFKit
        #endif
    }
}
