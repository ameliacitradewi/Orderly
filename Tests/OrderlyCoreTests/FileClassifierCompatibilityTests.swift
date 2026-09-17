import Foundation
import XCTest
@testable import OrderlyCore

@MainActor
final class FileClassifierCompatibilityTests: XCTestCase {
    private func metadata(named name: String) -> FileMetadata {
        FileMetadata(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp").appendingPathComponent(name),
            name: name,
            extensionName: URL(fileURLWithPath: name).pathExtension,
            size: 1,
            createdAt: nil,
            modifiedAt: nil,
            accessedAt: nil,
            isDirectory: false,
            isHidden: name.hasPrefix("."),
            uti: nil
        )
    }

    func testCataloguedExtensionsClassifyDeterministically() async throws {
        let input = [
            metadata(named: "notes.txt"),
            metadata(named: "proposal.pdf"),
            metadata(named: "screenshot.png"),
            metadata(named: "archive.zip"),
            metadata(named: "main.swift"),
            metadata(named: "installer.dmg")
        ]

        let classified = try await FileClassifier().classify(files: input)
        let byName = Dictionary(uniqueKeysWithValues: classified.map { ($0.name, $0.fileType) })

        XCTAssertEqual(byName["notes.txt"], .document)
        XCTAssertEqual(byName["proposal.pdf"], .document)
        XCTAssertEqual(byName["screenshot.png"], .image)
        XCTAssertEqual(byName["archive.zip"], .archive)
        XCTAssertEqual(byName["main.swift"], .code)
        XCTAssertEqual(byName["installer.dmg"], .application)
    }

    func testCataloguedClassificationDoesNotRequireModelAvailability() async throws {
        // This is intentionally all-catalogued input. The production classifier must
        // complete without touching Foundation Models, so OS/model availability cannot
        // block the deterministic classification stage.
        let input = [
            metadata(named: "report.pdf"),
            metadata(named: "photo.jpg"),
            metadata(named: "data.csv")
        ]

        let classified = try await FileClassifier().classify(files: input)

        XCTAssertEqual(classified.map(\.fileType), [.document, .image, .document])
    }
}
