import Foundation

struct InspectImageEvidenceTool {
    private let service: any ImageEvidenceInspecting

    init(service: any ImageEvidenceInspecting = AppleImageEvidenceService()) {
        self.service = service
    }

    func execute(
        file: FileMetadata,
        localReference: String?,
        globalReference: String,
        candidateID: UUID,
        analyzedFolder: URL
    ) throws -> AgentObservation {
        guard Self.supports(file) else {
            throw ImageEvidenceError.unsupportedFileType
        }
        guard Self.isInside(file.url, root: analyzedFolder) else {
            throw ImageEvidenceError.fileOutsideAnalyzedFolder
        }

        let inspected = try service.inspectImage(
            at: file.url,
            fileID: file.id,
            localReference: localReference,
            globalReference: globalReference
        )

        let content = """
        localReference=\(inspected.localReference ?? "outsideCurrentCandidate")
        globalReference=\(inspected.globalReference)
        contentType=\(inspected.contentType)
        width=\(inspected.width)
        height=\(inspected.height)
        frameCount=\(inspected.frameCount)
        orientation=\(inspected.orientation.map(String.init) ?? "unknown")
        This is deterministic raster metadata only. It does not describe image meaning and does not establish duplication.
        """

        return AgentObservation(
            type: .imageEvidence,
            candidateID: candidateID,
            content: content,
            globalReferences: [globalReference],
            imageEvidence: inspected,
            imageGlobalReferences: [globalReference]
        )
    }

    static func supports(_ file: FileMetadata) -> Bool {
        guard !file.isDirectory else { return false }
        let ext = file.extensionName.lowercased()
        return supportedRasterExtensions.contains(ext)
    }

    private static let supportedRasterExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff",
        "gif", "bmp", "webp", "avif"
    ]

    private static func isInside(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        let candidatePath = candidate.standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return candidatePath != rootPath
            && candidatePath.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")
    }
}

struct CompareImageEvidenceTool {
    private let service: any ImageEvidenceInspecting

    init(service: any ImageEvidenceInspecting = AppleImageEvidenceService()) {
        self.service = service
    }

    func execute(
        references: [String],
        candidateID: UUID,
        environment: AgentEnvironment,
        observations: [AgentObservation]
    ) throws -> AgentObservation {
        guard references.count == 2,
              Set(references).count == 2 else {
            throw AgentToolError.wrongFileCount
        }

        let visible = environment.visibleGlobalReferences(
            candidateID: candidateID,
            observations: observations
        )
        guard references.allSatisfy(visible.contains) else {
            let hidden = references.first { !visible.contains($0) } ?? references[0]
            throw AgentToolError.unobservedGlobalReference(hidden)
        }

        let files = try references.map { reference -> FileMetadata in
            guard let file = environment.filesByGlobalReference[reference] else {
                throw AgentToolError.invalidFileReference(reference)
            }
            guard InspectImageEvidenceTool.supports(file) else {
                throw ImageEvidenceError.unsupportedFileType
            }
            return file
        }

        let candidateFileIDs = Set(
            environment.evidenceByCandidate[candidateID]?.files.map(\.fileID) ?? []
        )
        guard files.contains(where: { candidateFileIDs.contains($0.id) }) else {
            throw AgentToolError.comparisonOutsideCandidate
        }

        let imageObservations = observations.filter {
            $0.candidateID == candidateID && $0.type == .imageEvidence
        }
        func evidence(for reference: String) -> ImageEvidenceObservation? {
            imageObservations.reversed().compactMap(\.imageEvidence).first {
                $0.globalReference == reference
            }
        }

        guard let first = evidence(for: references[0]),
              let second = evidence(for: references[1]) else {
            throw ImageEvidenceError.missingImageEvidence
        }

        let comparison = try service.compareImages(
            firstURL: files[0].url,
            secondURL: files[1].url,
            first: first,
            second: second
        )

        let content = """
        \(references[0]) vs \(references[1])
        sameDimensions=\(comparison.sameDimensions)
        aspectRatioDifference=\(Self.number(comparison.aspectRatioDifference))
        featurePrintDistance=\(Self.number(comparison.featurePrintDistance))
        Lower Vision feature-print distance indicates greater visual similarity, but no fixed threshold is treated as proof. This is not exact-duplicate verification and never authorizes deletion.
        """

        return AgentObservation(
            type: .imageComparison,
            candidateID: candidateID,
            content: content,
            globalReferences: references,
            imageComparison: comparison
        )
    }

    private static func number(_ value: Double) -> String {
        String(
            format: "%.4f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }
}
