import AppKit
import Foundation

#if DEBUG
enum FastVLMSmokeTest {
    static func runImageSemanticInspection() async throws {
        print("======== REAL FASTVLM IMAGE SMOKE START ========")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orderly-FastVLM-Smoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let imageURL = root.appendingPathComponent("orderly-settings-screen.png")
        try makeScreenshotLikeFixture(at: imageURL)

        let fileID = UUID()
        let evidence = try AppleImageEvidenceService().inspectImage(
            at: imageURL,
            fileID: fileID,
            localReference: "F1",
            globalReference: "G1"
        )

        print("======== IMAGE DETERMINISTIC EVIDENCE ========")
        print("width=", evidence.width)
        print("height=", evidence.height)
        print("frames=", evidence.frameCount)
        print("contentType=", evidence.contentType)

        let analyzer = StructuredImageSemanticAnalyzer(
            visionModel: FastVLMVisionService()
        )
        let semantic = try await analyzer.analyze(
            imageURL: imageURL,
            evidence: evidence
        )

        print("======== FASTVLM SEMANTIC OBSERVATION ========")
        print("contentKind=", semantic.contentKind.rawValue)
        print("confidence=", semantic.confidence)
        print("summary=", semantic.summary)

        guard semantic.fileID == fileID,
              semantic.globalReference == "G1",
              semantic.localReference == "F1" else {
            throw FastVLMSmokeError.identityMismatch
        }
        guard semantic.confidence.isFinite,
              (0...1).contains(semantic.confidence),
              semantic.confidence >= 0.35 else {
            throw FastVLMSmokeError.lowConfidence
        }
        guard semantic.contentKind == .screenshot
                || semantic.contentKind == .graphic else {
            throw FastVLMSmokeError.unexpectedContentKind(
                semantic.contentKind.rawValue
            )
        }
        guard !semantic.summary.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw FastVLMSmokeError.emptySummary
        }

        print("======== REAL FASTVLM IMAGE SMOKE PASS ========")
        print("Model:", FastVLMModelManager.modelName)
        print("Content kind:", semantic.contentKind.rawValue)
        print("Confidence:", semantic.confidence)
        print("Summary:", semantic.summary)
        print("No cleanup action was executed.")
    }

    /// Renders directly into an explicit bitmap context. Avoid NSImage.lockFocus +
    /// tiffRepresentation here: in a headless/debug SwiftUI task that path can create
    /// an image representation with zero destination capacity before a drawable rep
    /// has been committed.
    private static func makeScreenshotLikeFixture(at url: URL) throws {
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
            throw FastVLMSmokeError.cannotCreateFixture
        }
        bitmap.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer {
            NSGraphicsContext.restoreGraphicsState()
        }

        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
        NSRect(x: 0, y: 550, width: 960, height: 50).fill()

        NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 220, height: 550).fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 22),
            .foregroundColor: NSColor.white
        ]
        ("Orderly" as NSString).draw(
            at: NSPoint(x: 24, y: 562),
            withAttributes: titleAttributes
        )

        let sidebarAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.22, alpha: 1)
        ]
        ("Overview" as NSString).draw(
            at: NSPoint(x: 28, y: 490),
            withAttributes: sidebarAttributes
        )
        ("Recommendations" as NSString).draw(
            at: NSPoint(x: 28, y: 450),
            withAttributes: sidebarAttributes
        )
        ("Settings" as NSString).draw(
            at: NSPoint(x: 28, y: 410),
            withAttributes: sidebarAttributes
        )

        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 30),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)
        ]
        ("Declutter Settings" as NSString).draw(
            at: NSPoint(x: 270, y: 480),
            withAttributes: headingAttributes
        )

        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17),
            .foregroundColor: NSColor(calibratedWhite: 0.25, alpha: 1)
        ]
        ("Review related screenshots before cleanup" as NSString).draw(
            at: NSPoint(x: 270, y: 430),
            withAttributes: bodyAttributes
        )
        ("Keep exact duplicate verification enabled" as NSString).draw(
            at: NSPoint(x: 270, y: 385),
            withAttributes: bodyAttributes
        )

        NSColor.systemBlue.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 270, y: 285, width: 190, height: 48),
            xRadius: 10,
            yRadius: 10
        ).fill()
        let buttonAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.white
        ]
        ("Choose Folder" as NSString).draw(
            at: NSPoint(x: 309, y: 300),
            withAttributes: buttonAttributes
        )

        context.flushGraphics()

        guard let png = bitmap.representation(
            using: .png,
            properties: [:]
        ), !png.isEmpty else {
            throw FastVLMSmokeError.cannotCreateFixture
        }
        try png.write(to: url, options: .atomic)

        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        guard let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue > 0 else {
            throw FastVLMSmokeError.cannotCreateFixture
        }

        print("======== FASTVLM FIXTURE READY ========")
        print("bytes=", fileSize.intValue)
    }
}

enum FastVLMSmokeError: LocalizedError {
    case cannotCreateFixture
    case identityMismatch
    case lowConfidence
    case unexpectedContentKind(String)
    case emptySummary

    var errorDescription: String? {
        switch self {
        case .cannotCreateFixture:
            return "Could not create the synthetic image fixture."
        case .identityMismatch:
            return "FastVLM semantic evidence lost the trusted file identity."
        case .lowConfidence:
            return "FastVLM returned confidence below the smoke-test floor."
        case .unexpectedContentKind(let kind):
            return "FastVLM classified the screenshot-like fixture as \(kind)."
        case .emptySummary:
            return "FastVLM returned an empty visual summary."
        }
    }
}
#endif
