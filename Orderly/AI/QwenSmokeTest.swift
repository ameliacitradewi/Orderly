//
//  QwenSmokeTest.swift
//  Orderly
//
//  Created by Amelia Citra on 08/09/26.
//

import CoreGraphics
import CoreText
import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

enum QwenSmokeTest {
    private enum SmokeError: LocalizedError {
        case cannotCreatePDF
        case missingFixtureFile(String)
        case missingAgentAction(AgentAction)
        case missingDocumentComparison
        case wrongSemanticRelationship(DocumentSemanticRelationship)

        var errorDescription: String? {
            switch self {
            case .cannotCreatePDF:
                return "The document smoke fixture PDF could not be created."
            case .missingFixtureFile(let name):
                return "The document smoke fixture is missing \(name)."
            case .missingAgentAction(let action):
                return "The real Qwen agent did not choose required action \(action.rawValue)."
            case .missingDocumentComparison:
                return "The real Qwen agent did not produce a documentComparison observation."
            case .wrongSemanticRelationship(let relationship):
                return "Expected sameDocumentRevision, got \(relationship.rawValue)."
            }
        }
    }

    /// Minimal model-load sanity check kept for quick MLX diagnostics.
    static func run() async throws -> String {
        print("======== QWEN LOAD START ========")

        let model = try await #huggingFaceLoadModelContainer(
            configuration: LLMRegistry.qwen3_8b_4bit
        )

        print("======== QWEN MODEL LOADED ========")

        let session = ChatSession(model)

        let response = try await session.respond(
            to: """
            You are running inside Orderly, a macOS file cleanup application.
            Reply with exactly: QWEN_OK
            """
        )

        print("======== QWEN RESPONSE ========")
        print(response)

        return response
    }

    /// Runs the real agent and the real Qwen semantic analyzer against actual PDFs.
    /// No filesystem cleanup action is executed. The temporary fixture is removed after the run.
    @MainActor
    static func runDocumentComparison() async throws {
        print("======== REAL QWEN DOCUMENT SMOKE START ========")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orderly-Qwen-Document-Smoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let v1URL = root.appendingPathComponent("client-proposal-v1.pdf")
        let finalURL = root.appendingPathComponent("client-proposal-final.pdf")
        let invoiceURL = root.appendingPathComponent("invoice-2026.pdf")
        let paperURL = root.appendingPathComponent("research-paper.pdf")

        try writePDF(
            at: v1URL,
            text: """
            Client Transformation Proposal
            Introduction
            This proposal describes a six month transformation program for the Acme client.
            Scope
            Discovery, workflow redesign, implementation, training, and launch support.
            Budget
            The proposed program budget is 120000 USD.
            Timeline
            Discovery begins in October followed by implementation and launch.
            """
        )

        try writePDF(
            at: finalURL,
            text: """
            Client Transformation Proposal
            Introduction
            This proposal describes a six month transformation program for the Acme client.
            Scope
            Discovery, workflow redesign, implementation, training, and launch support.
            Budget
            The approved program budget is 135000 USD including post-launch support.
            Timeline
            Discovery begins in October followed by implementation and launch.
            Conclusion
            This final revision adds post-launch support and the approved budget.
            """
        )

        try writePDF(
            at: invoiceURL,
            text: """
            Invoice 2026-091
            Vendor: Example Services
            Amount Due: 4820 USD
            Payment terms: net 30 days.
            """
        )

        try writePDF(
            at: paperURL,
            text: """
            Research Notes on Distributed Systems
            This paper discusses consensus protocols, replication, and fault tolerance.
            """
        )

        let now = Date()
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: v1URL.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(180)], ofItemAtPath: finalURL.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-86_400)], ofItemAtPath: invoiceURL.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-172_800)], ofItemAtPath: paperURL.path)

        let scannedFiles = try await FileSystemService().scanDirectory(at: root)
        guard let v1 = scannedFiles.first(where: { $0.name == v1URL.lastPathComponent }) else {
            throw SmokeError.missingFixtureFile(v1URL.lastPathComponent)
        }
        guard scannedFiles.contains(where: { $0.name == finalURL.lastPathComponent }) else {
            throw SmokeError.missingFixtureFile(finalURL.lastPathComponent)
        }

        let candidate = AnalysisCandidate(
            id: UUID(),
            type: .grouping,
            fileIDs: [v1.id],
            confidence: 1,
            reason: "A document version may have a related revision elsewhere in the selected folder; investigate before concluding."
        )

        let analysis = AnalysisResult(
            analyzedFolder: root,
            totalFiles: scannedFiles.count,
            totalSize: scannedFiles.reduce(0) { $0 + $1.size },
            fileTypes: [],
            duplicateGroups: [],
            candidates: [candidate],
            analyzedAt: Date(),
            files: scannedFiles,
            unreadableHashCount: 0
        )

        let evidence = EvidenceEngine().buildEvidence(
            candidates: analysis.candidates,
            files: analysis.files,
            duplicateGroups: analysis.duplicateGroups,
            rootFolder: root
        )

        let llm = QwenMLXService()
        let state = try await OrderlyAgent(llm: llm).run(
            analysis: analysis,
            evidence: evidence
        )

        let actions = Set(state.executedToolCalls.map(\.action))
        for required in [
            AgentAction.findRelatedFiles,
            .inspectPDFContent,
            .inspectGlobalPDFContent,
            .compareDocumentContent
        ] where !actions.contains(required) {
            throw SmokeError.missingAgentAction(required)
        }

        guard let comparison = state.observations
            .compactMap(\.documentComparison)
            .first else {
            throw SmokeError.missingDocumentComparison
        }

        guard comparison.semantic.relationship == .sameDocumentRevision else {
            throw SmokeError.wrongSemanticRelationship(
                comparison.semantic.relationship
            )
        }

        print("======== REAL QWEN DOCUMENT SMOKE PASS ========")
        print("Required actions:", actions.map(\.rawValue).sorted().joined(separator: ", "))
        print("Semantic relationship:", comparison.semantic.relationship.rawValue)
        print("Semantic confidence:", comparison.semantic.confidence)
        print("Summary:", comparison.semantic.summary)
        print("No cleanup action was executed.")
    }

    private static func writePDF(
        at url: URL,
        text: String
    ) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw SmokeError.cannotCreatePDF
        }

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(
            consumer: consumer,
            mediaBox: &mediaBox,
            nil
        ) else {
            throw SmokeError.cannotCreatePDF
        }

        context.beginPDFPage(nil)

        let font = CTFontCreateWithName(
            "Helvetica" as CFString,
            12,
            nil
        )
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(
            rect: CGRect(x: 48, y: 48, width: 516, height: 696),
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
        context.closePDF()
    }
}
