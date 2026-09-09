import AppKit
import Foundation

#if DEBUG
enum ImageAgentSmokeTest {
    private enum SmokeError: LocalizedError {
        case cannotCreateFixture
        case missingFixtureFile(String)
        case missingAgentAction(AgentAction)
        case missingImageComparison
        case unexpectedRelationship(ImageSemanticRelationship)
        case missingRelatedFinding

        var errorDescription: String? {
            switch self {
            case .cannotCreateFixture:
                return "Could not create the image-agent smoke fixture."
            case .missingFixtureFile(let name):
                return "The image-agent smoke fixture is missing \(name)."
            case .missingAgentAction(let action):
                return "The real agent did not choose required image action \(action.rawValue)."
            case .missingImageComparison:
                return "The real agent did not produce an imageSemanticComparison observation."
            case .unexpectedRelationship(let relationship):
                return "Expected a related image relationship, got \(relationship.rawValue)."
            case .missingRelatedFinding:
                return "The real agent did not finish with a related finding for the image variant."
            }
        }
    }

    @MainActor
    static func run() async throws {
        print("======== REAL HYBRID IMAGE AGENT SMOKE START ========")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orderly-Image-Agent-Smoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let firstURL = root.appendingPathComponent("orderly-settings-screen.png")
        let secondURL = root.appendingPathComponent("orderly-settings-screen-edited.png")
        try makeScreenshotLikeFixture(at: firstURL, edited: false)
        try makeScreenshotLikeFixture(at: secondURL, edited: true)

        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: firstURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(120)],
            ofItemAtPath: secondURL.path
        )

        let scannedFiles = try await FileSystemService().scanDirectory(at: root)
        guard let first = scannedFiles.first(where: { $0.name == firstURL.lastPathComponent }) else {
            throw SmokeError.missingFixtureFile(firstURL.lastPathComponent)
        }
        guard scannedFiles.contains(where: { $0.name == secondURL.lastPathComponent }) else {
            throw SmokeError.missingFixtureFile(secondURL.lastPathComponent)
        }

        let candidate = AnalysisCandidate(
            id: UUID(),
            type: .grouping,
            fileIDs: [first.id],
            confidence: 1,
            reason: "A visually related screenshot variant is expected elsewhere in the selected folder. Use global discovery and visual comparison before concluding."
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

        let state = try await OrderlyAgent(
            llm: QwenMLXService(),
            visionLanguageService: FastVLMVisionService()
        ).run(
            analysis: analysis,
            evidence: evidence
        )

        let actions = Set(state.executedToolCalls.map(\.action))
        for required in [
            AgentAction.inspectImageContent,
            .findRelatedFiles,
            .inspectGlobalImageContent,
            .compareImageContent
        ] where !actions.contains(required) {
            throw SmokeError.missingAgentAction(required)
        }

        guard let comparison = state.observations
            .compactMap(\.imageSemanticComparison)
            .first else {
            throw SmokeError.missingImageComparison
        }
        switch comparison.semantic.relationship {
        case .sameImageVariant, .sameScene, .sameSubject:
            break
        case .unrelated, .uncertain:
            throw SmokeError.unexpectedRelationship(
                comparison.semantic.relationship
            )
        }

        guard state.findings.first?.relationship == .related else {
            throw SmokeError.missingRelatedFinding
        }

        print("======== REAL HYBRID IMAGE AGENT SMOKE PASS ========")
        print("Required actions:", actions.map(\.rawValue).sorted().joined(separator: ", "))
        print("Visual relationship:", comparison.semantic.relationship.rawValue)
        print("Semantic confidence:", comparison.semantic.confidence)
        print("Summary:", comparison.semantic.summary)
        print("No cleanup action was executed.")
    }

    private static func makeScreenshotLikeFixture(
        at url: URL,
        edited: Bool
    ) throws {
        let width = 960
        let height = 600
        let size = NSSize(width: width, height: height)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw SmokeError.cannotCreateFixture
        }
        bitmap.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
        NSRect(x: 0, y: 550, width: 960, height: 50).fill()
        NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 220, height: 550).fill()

        draw(
            "Orderly",
            at: NSPoint(x: 24, y: 562),
            font: .boldSystemFont(ofSize: 22),
            color: .white
        )
        draw(
            "Overview\n\nRecommendations\n\nSettings",
            at: NSPoint(x: 28, y: 405),
            font: .systemFont(ofSize: 16, weight: .medium),
            color: NSColor(calibratedWhite: 0.22, alpha: 1)
        )
        draw(
            "Declutter Settings",
            at: NSPoint(x: 270, y: 480),
            font: .boldSystemFont(ofSize: 30),
            color: NSColor(calibratedWhite: 0.12, alpha: 1)
        )
        draw(
            edited
                ? "Review related screenshots before cleanup\n\nKeep exact duplicate verification enabled\n\nShow visual variants before cleanup"
                : "Review related screenshots before cleanup\n\nKeep exact duplicate verification enabled",
            at: NSPoint(x: 270, y: 360),
            font: .systemFont(ofSize: 17),
            color: NSColor(calibratedWhite: 0.25, alpha: 1)
        )

        NSColor.systemBlue.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 270, y: 260, width: 190, height: 48),
            xRadius: 10,
            yRadius: 10
        ).fill()
        draw(
            "Choose Folder",
            at: NSPoint(x: 309, y: 275),
            font: .boldSystemFont(ofSize: 16),
            color: .white
        )

        if edited {
            NSColor.systemOrange.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 730, y: 470, width: 120, height: 34),
                xRadius: 8,
                yRadius: 8
            ).fill()
            draw(
                "Updated",
                at: NSPoint(x: 757, y: 479),
                font: .boldSystemFont(ofSize: 14),
                color: .white
            )
        }

        context.flushGraphics()
        guard let png = bitmap.representation(using: .png, properties: [:]),
              !png.isEmpty else {
            throw SmokeError.cannotCreateFixture
        }
        try png.write(to: url, options: .atomic)
    }

    private static func draw(
        _ text: String,
        at point: NSPoint,
        font: NSFont,
        color: NSColor
    ) {
        (text as NSString).draw(
            at: point,
            withAttributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
    }
}
#endif
