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

    private func fixtureDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
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

    private func environment(
        root: URL,
        fileURL: URL
    ) throws -> (
        AgentEnvironment,
        AnalysisCandidate
    ) {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )
        let fileID = UUID()
        let candidate = AnalysisCandidate(
            id: UUID(),
            type: .grouping,
            fileIDs: [fileID],
            confidence: 1,
            reason: "Ambiguous PDF"
        )
        let metadata = FileMetadata(
            id: fileID,
            url: fileURL,
            name: fileURL.lastPathComponent,
            extensionName: fileURL.pathExtension,
            size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            createdAt: nil,
            modifiedAt: attributes[.modificationDate] as? Date,
            accessedAt: nil,
            isDirectory: false,
            isHidden: false,
            uti: nil
        )
        let evidence = CandidateEvidence(
            candidateID: candidate.id,
            files: [
                CandidateFileEvidence(
                    fileID: fileID,
                    reference: "F1",
                    name: metadata.name,
                    tag: .document,
                    size: metadata.size,
                    modifiedAt: metadata.modifiedAt,
                    relativePath: metadata.name,
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
            totalFiles: 1,
            totalSize: metadata.size,
            fileTypes: [],
            duplicateGroups: [],
            candidates: [candidate],
            analyzedAt: Date(),
            files: [metadata],
            unreadableHashCount: 0
        )
        return (
            AgentEnvironment(
                analysis: analysis,
                evidence: [evidence]
            ),
            candidate
        )
    }

    func testPDFKitExtractsRealTextWithBoundedExcerpt() throws {
        let root = try fixtureDirectory()
        let url = root.appendingPathComponent("annual-report.pdf")
        let text = String(
            repeating: "Annual Financial Report 2026 revenue and results. ",
            count: 20
        )
        try writeTextPDF(at: url, pages: [text, "Second page appendix."])

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

    func testToolRouterReadsOnlyValidatedPDFReference() throws {
        let root = try fixtureDirectory()
        let url = root.appendingPathComponent("2026-report.pdf")
        try writeTextPDF(
            at: url,
            pages: ["Annual Financial Report 2026 operating revenue."]
        )
        let fixture = try environment(root: root, fileURL: url)

        let observation = try ToolRouter().execute(
            decision: AgentDecision(
                action: .inspectPDFContent,
                candidateID: fixture.1.id,
                fileReferences: ["F1"],
                reason: "Metadata is insufficient."
            ),
            environment: fixture.0
        )

        XCTAssertEqual(observation.type, .content)
        XCTAssertEqual(
            observation.contentObservation?.fileReference,
            "F1"
        )
        XCTAssertTrue(
            observation.contentObservation?.excerpt.contains(
                "Annual Financial Report 2026"
            ) == true
        )
        XCTAssertLessThanOrEqual(
            observation.contentObservation?.excerpt.count ?? .max,
            AgentContextBudget.maxContentExcerptCharacters
        )
    }

    func testPDFToolRejectsFileOutsideAnalyzedFolder() throws {
        let root = try fixtureDirectory()
        let outsideRoot = try fixtureDirectory()
        let outsideURL = outsideRoot.appendingPathComponent("outside.pdf")
        try writeTextPDF(at: outsideURL, pages: ["Outside content"])
        let fixture = try environment(
            root: root,
            fileURL: outsideURL
        )

        XCTAssertThrowsError(
            try ToolRouter().execute(
                decision: AgentDecision(
                    action: .inspectPDFContent,
                    candidateID: fixture.1.id,
                    fileReferences: ["F1"],
                    reason: "Attempt outside access"
                ),
                environment: fixture.0
            )
        ) { error in
            guard case ContentInspectionError.fileOutsideAnalyzedFolder = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testPDFToolRejectsNonPDFReference() throws {
        let root = try fixtureDirectory()
        let url = root.appendingPathComponent("notes.txt")
        try "Plain text".write(to: url, atomically: true, encoding: .utf8)
        let fixture = try environment(root: root, fileURL: url)

        XCTAssertThrowsError(
            try ToolRouter().execute(
                decision: AgentDecision(
                    action: .inspectPDFContent,
                    candidateID: fixture.1.id,
                    fileReferences: ["F1"],
                    reason: "Attempt unsupported content inspection"
                ),
                environment: fixture.0
            )
        ) { error in
            guard case ContentInspectionError.unsupportedFileType = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testContextIncludesOnlySixRecentObservationsWithinBudget() {
        let candidateID = UUID()
        let observations = (0..<8).map { index in
            AgentObservation(
                id: UUID(),
                type: .metadata,
                candidateID: candidateID,
                content: "marker-\(index) " + String(repeating: "x", count: 200)
            )
        }
        let builder = AgentContextBuilder()
        let rendered = builder.renderObservations(observations)

        XCTAssertFalse(rendered.contains("marker-0"))
        XCTAssertFalse(rendered.contains("marker-1"))
        for index in 2..<8 {
            XCTAssertTrue(rendered.contains("marker-\(index)"))
        }
        XCTAssertLessThanOrEqual(
            rendered.count,
            AgentContextBudget.maxObservationCharacters
        )

        let oversized = AgentObservation(
            type: .content,
            candidateID: candidateID,
            content: String(repeating: "z", count: 20_000)
        )
        XCTAssertLessThanOrEqual(
            builder.renderObservations([oversized]).count,
            AgentContextBudget.maxObservationCharacters
        )
    }

    func testDuplicatePromptDoesNotEncourageContentInspection() {
        let candidate = AnalysisCandidate(
            id: UUID(),
            type: .duplicate,
            fileIDs: [UUID(), UUID()],
            confidence: 1,
            reason: "SHA256 Duplicate"
        )
        var state = AgentState(
            goal: "Investigate safely",
            pendingCandidates: [candidate]
        )
        state.iteration = 2
        state.observations = [
            AgentObservation(
                type: .candidate,
                candidateID: candidate.id,
                content: "F1 and F2"
            ),
            AgentObservation(
                type: .comparison,
                candidateID: candidate.id,
                content: "verifiedDuplicate=true"
            )
        ]

        let prompt = AgentContextBuilder().build(
            state: state,
            candidate: candidate
        )

        XCTAssertTrue(prompt.contains(
            "do not inspect PDF content unless you can state a specific unresolved question"
        ))
        XCTAssertTrue(prompt.contains("verifiedDuplicate=true"))
    }

}
