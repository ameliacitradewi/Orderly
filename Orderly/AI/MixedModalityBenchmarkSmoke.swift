import AppKit
import CoreGraphics
import CoreText
import Foundation

#if DEBUG
enum MixedModalityBenchmarkSmoke {
    private enum BenchmarkError: LocalizedError {
        case cannotCreateFixture
        case missingFixtureFile(String)
        case missingDuplicateCandidate
        case incompleteRun(Int, Int)
        case unexpectedCandidateFailures(Int)
        case incompleteAgentSuccess(Double)
        case unexpectedFallback(Double)
        case missingVerifiedDuplicateComparison
        case missingDocumentComparison
        case missingImageComparison
        case missingFastVLMInference

        var errorDescription: String? {
            switch self {
            case .cannotCreateFixture:
                return "Could not create the mixed-modality benchmark fixture."
            case .missingFixtureFile(let name):
                return "The mixed benchmark fixture is missing \(name)."
            case .missingDuplicateCandidate:
                return "Deterministic analysis did not produce the expected duplicate candidate."
            case .incompleteRun(let findings, let candidates):
                return "The benchmark completed only \(findings) of \(candidates) candidates."
            case .unexpectedCandidateFailures(let count):
                return "The production coordinator isolated \(count) candidate failure(s); the baseline benchmark requires zero fallbacks."
            case .incompleteAgentSuccess(let rate):
                let formatted = String(
                    format: "%.3f",
                    locale: Locale(identifier: "en_US_POSIX"),
                    rate
                )
                return "The baseline benchmark requires agentSuccessRate=1.0, but observed \(formatted)."
            case .unexpectedFallback(let rate):
                let formatted = String(
                    format: "%.3f",
                    locale: Locale(identifier: "en_US_POSIX"),
                    rate
                )
                return "The baseline benchmark requires fallbackRate=0.0, but observed \(formatted)."
            case .missingVerifiedDuplicateComparison:
                return "The benchmark did not exercise verified SHA duplicate comparison."
            case .missingDocumentComparison:
                return "The benchmark did not produce semantic document comparison evidence."
            case .missingImageComparison:
                return "The benchmark did not produce semantic image comparison evidence."
            case .missingFastVLMInference:
                return "The benchmark image candidate completed without exercising FastVLM inference."
            }
        }
    }

    @MainActor
    static func run() async throws {
        print("======== MIXED MODALITY BENCHMARK START ========")
        print("orchestration=ResilientAgentCoordinator")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orderly-Mixed-Benchmark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let duplicateAURL = root.appendingPathComponent("meeting-notes-copy-a.txt")
        let duplicateBURL = root.appendingPathComponent("meeting-notes-copy-b.txt")
        let proposalAURL = root.appendingPathComponent("client-proposal-a.pdf")
        let proposalBURL = root.appendingPathComponent("client-proposal-b.pdf")
        let imageAURL = root.appendingPathComponent("orderly-settings-a.png")
        let imageBURL = root.appendingPathComponent("orderly-settings-b.png")

        let duplicateText = """
        Weekly planning notes
        - Review launch checklist
        - Confirm QA handoff
        - Prepare release summary
        """
        try duplicateText.write(to: duplicateAURL, atomically: true, encoding: .utf8)
        try duplicateText.write(to: duplicateBURL, atomically: true, encoding: .utf8)

        try writePDF(
            at: proposalAURL,
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
            at: proposalBURL,
            text: """
            Client Transformation Proposal
            Introduction
            This proposal describes a six month transformation program for the Acme client.
            Scope
            Discovery, workflow redesign, implementation, training, launch support, and post-launch support.
            Budget
            The approved program budget is 135000 USD.
            Timeline
            Discovery begins in October followed by implementation and launch.
            """
        )

        try writeScreenshot(at: imageAURL, edited: false)
        try writeScreenshot(at: imageBURL, edited: true)

        let now = Date()
        for (url, offset) in [
            (duplicateAURL, 0.0),
            (duplicateBURL, 20.0),
            (proposalAURL, 60.0),
            (proposalBURL, 120.0),
            (imageAURL, 180.0),
            (imageBURL, 240.0)
        ] {
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(offset)],
                ofItemAtPath: url.path
            )
        }

        let scannedFiles = try await FileSystemService().scanDirectory(at: root)
        let analyzed = try await AnalysisEngine().analyze(
            folder: root,
            files: scannedFiles
        )

        func requiredFile(_ name: String) throws -> FileMetadata {
            guard let file = analyzed.files.first(where: { $0.name == name }) else {
                throw BenchmarkError.missingFixtureFile(name)
            }
            return file
        }

        let duplicateA = try requiredFile(duplicateAURL.lastPathComponent)
        let duplicateB = try requiredFile(duplicateBURL.lastPathComponent)
        let proposalA = try requiredFile(proposalAURL.lastPathComponent)
        let proposalB = try requiredFile(proposalBURL.lastPathComponent)
        let imageA = try requiredFile(imageAURL.lastPathComponent)
        let imageB = try requiredFile(imageBURL.lastPathComponent)

        let duplicateIDs = Set([duplicateA.id, duplicateB.id])
        guard let duplicateCandidate = analyzed.candidates.first(where: {
            $0.type == .duplicate && duplicateIDs.isSubset(of: Set($0.fileIDs))
        }) else {
            throw BenchmarkError.missingDuplicateCandidate
        }

        // Keep the deterministic scan/hash result, but use focused two-file semantic
        // candidates so this benchmark measures each intelligence path independently
        // instead of depending on ClutterAnalyzer category batch composition.
        let documentCandidate = AnalysisCandidate(
            id: UUID(),
            type: .grouping,
            fileIDs: [proposalA.id, proposalB.id],
            confidence: 1,
            reason: "Two proposal PDFs may be revisions of the same underlying document; inspect their content and compare if needed."
        )
        let imageCandidate = AnalysisCandidate(
            id: UUID(),
            type: .grouping,
            fileIDs: [imageA.id, imageB.id],
            confidence: 1,
            reason: "Two screenshots may be visual variants of the same underlying screen; inspect and compare them if needed."
        )

        let benchmarkCandidates = [
            duplicateCandidate,
            documentCandidate,
            imageCandidate
        ]
        let analysis = AnalysisResult(
            analyzedFolder: analyzed.analyzedFolder,
            totalFiles: analyzed.totalFiles,
            totalSize: analyzed.totalSize,
            fileTypes: analyzed.fileTypes,
            duplicateGroups: analyzed.duplicateGroups,
            candidates: benchmarkCandidates,
            analyzedAt: analyzed.analyzedAt,
            files: analyzed.files,
            unreadableHashCount: analyzed.unreadableHashCount
        )
        let evidence = EvidenceEngine().buildEvidence(
            candidates: analysis.candidates,
            files: analysis.files,
            duplicateGroups: analysis.duplicateGroups,
            rootFolder: root
        )

        await LocalModelRuntimeMetrics.shared.reset()
        let memoryBeforeModels = ResidentMemorySampler.currentBytes()
        let memoryTask = Task.detached(priority: .utility) { () -> UInt64 in
            var peak = ResidentMemorySampler.currentBytes() ?? 0
            while !Task.isCancelled {
                if let current = ResidentMemorySampler.currentBytes() {
                    peak = max(peak, current)
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            return peak
        }

        let productionCoordinator = ResilientAgentCoordinator(
            agent: OrderlyAgent(
                llm: QwenMLXService(),
                visionLanguageService: FastVLMVisionService()
            )
        )

        let planningStartedAt = Date()
        let state: AgentState
        do {
            state = try await productionCoordinator.run(
                analysis: analysis,
                evidence: evidence
            )
        } catch {
            memoryTask.cancel()
            _ = await memoryTask.value
            throw error
        }
        let totalPlanningSeconds = Date().timeIntervalSince(planningStartedAt)
        memoryTask.cancel()
        let peakResidentBytes = await memoryTask.value
        let memoryAfterRun = ResidentMemorySampler.currentBytes()
        let modelRuntime = await LocalModelRuntimeMetrics.shared.snapshot()
        let evaluation = AgentEvaluator().evaluate(
            state: state,
            analysis: analysis
        )

        // A production fallback is good runtime behavior, but it is not accepted as a
        // clean benchmark success. The baseline must prove that all three intelligence
        // paths complete through the model-driven agent without coordinator recovery.
        guard state.findings.count == benchmarkCandidates.count else {
            throw BenchmarkError.incompleteRun(
                state.findings.count,
                benchmarkCandidates.count
            )
        }
        guard state.candidateFailures.isEmpty else {
            throw BenchmarkError.unexpectedCandidateFailures(
                state.candidateFailures.count
            )
        }
        guard evaluation.agentSuccessRate >= 0.999_999 else {
            throw BenchmarkError.incompleteAgentSuccess(
                evaluation.agentSuccessRate
            )
        }
        guard evaluation.fallbackRate <= 0.000_001 else {
            throw BenchmarkError.unexpectedFallback(
                evaluation.fallbackRate
            )
        }
        guard state.observations.contains(where: {
            $0.candidateID == duplicateCandidate.id
                && $0.type == .comparison
                && $0.comparison?.verifiedDuplicate == true
        }) else {
            throw BenchmarkError.missingVerifiedDuplicateComparison
        }
        guard state.observations.contains(where: {
            $0.candidateID == documentCandidate.id
                && $0.type == .documentComparison
        }) else {
            throw BenchmarkError.missingDocumentComparison
        }
        guard state.observations.contains(where: {
            $0.candidateID == imageCandidate.id
                && $0.type == .imageSemanticComparison
        }) else {
            throw BenchmarkError.missingImageComparison
        }
        guard modelRuntime.fastVLM.inferenceCount > 0 else {
            throw BenchmarkError.missingFastVLMInference
        }

        print("======== MIXED MODALITY QUALITY REPORT ========")
        print(evaluation.debugSummary())

        print("======== MIXED MODALITY RUNTIME REPORT ========")
        print("totalPlanningSeconds=", number(totalPlanningSeconds))
        print("residentBytesBeforeModels=", bytes(memoryBeforeModels))
        print("peakResidentBytes=", peakResidentBytes)
        print("residentBytesAfterRun=", bytes(memoryAfterRun))
        if let baseline = memoryBeforeModels {
            print("peakResidentDeltaBytes=", peakResidentBytes > baseline ? peakResidentBytes - baseline : 0)
        } else {
            print("peakResidentDeltaBytes= unavailable")
        }
        print(modelRuntime.debugSummary())

        print("======== MIXED MODALITY FINDINGS ========")
        for finding in state.findings {
            print(
                "candidate=", finding.candidateID.uuidString,
                "relationship=", finding.relationship.rawValue,
                "confidence=", number(finding.confidence)
            )
            for proposal in finding.proposals {
                print(
                    "  ", proposal.fileReference,
                    "->", proposal.disposition.rawValue,
                    "|", proposal.reason
                )
            }
        }

        print("======== MIXED MODALITY BENCHMARK PASS ========")
        print("productionCoordinatorFallbacks=0")
        print("No cleanup action was executed.")
    }

    private static func writePDF(at url: URL, text: String) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw BenchmarkError.cannotCreateFixture
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(
            consumer: consumer,
            mediaBox: &mediaBox,
            nil
        ) else {
            throw BenchmarkError.cannotCreateFixture
        }

        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
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

    private static func writeScreenshot(at url: URL, edited: Bool) throws {
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
            throw BenchmarkError.cannotCreateFixture
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

        draw("Orderly", at: NSPoint(x: 24, y: 562), font: .boldSystemFont(ofSize: 22), color: .white)
        draw("Overview\n\nRecommendations\n\nSettings", at: NSPoint(x: 28, y: 405), font: .systemFont(ofSize: 16, weight: .medium), color: NSColor(calibratedWhite: 0.22, alpha: 1))
        draw("Declutter Settings", at: NSPoint(x: 270, y: 480), font: .boldSystemFont(ofSize: 30), color: NSColor(calibratedWhite: 0.12, alpha: 1))
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
        draw("Choose Folder", at: NSPoint(x: 309, y: 275), font: .boldSystemFont(ofSize: 16), color: .white)

        if edited {
            NSColor.systemOrange.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 730, y: 470, width: 120, height: 34),
                xRadius: 8,
                yRadius: 8
            ).fill()
            draw("Updated", at: NSPoint(x: 757, y: 479), font: .boldSystemFont(ofSize: 14), color: .white)
        }

        context.flushGraphics()
        guard let png = bitmap.representation(using: .png, properties: [:]),
              !png.isEmpty else {
            throw BenchmarkError.cannotCreateFixture
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

    private static func number(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func bytes(_ value: UInt64?) -> String {
        value.map(String.init) ?? "unavailable"
    }
}
#endif