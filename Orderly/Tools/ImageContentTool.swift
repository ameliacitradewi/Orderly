import Foundation

struct InspectImageContentTool {
    private let evidenceService: any ImageEvidenceInspecting
    private let semanticAnalyzer: any ImageSemanticAnalyzing

    init(
        evidenceService: any ImageEvidenceInspecting = AppleImageEvidenceService(),
        semanticAnalyzer: any ImageSemanticAnalyzing
    ) {
        self.evidenceService = evidenceService
        self.semanticAnalyzer = semanticAnalyzer
    }

    func execute(
        file: FileMetadata,
        localReference: String?,
        globalReference: String,
        candidateID: UUID,
        analyzedFolder: URL
    ) async throws -> AgentObservation {
        guard InspectImageEvidenceTool.supports(file) else {
            throw ImageEvidenceError.unsupportedFileType
        }
        guard Self.isInside(file.url, root: analyzedFolder) else {
            throw ImageEvidenceError.fileOutsideAnalyzedFolder
        }

        let evidence = try evidenceService.inspectImage(
            at: file.url,
            fileID: file.id,
            localReference: localReference,
            globalReference: globalReference
        )
        let semantic = try await semanticAnalyzer.analyze(
            imageURL: file.url,
            evidence: evidence
        )

        let content = """
        localReference=\(localReference ?? "outsideCurrentCandidate")
        globalReference=\(globalReference)
        contentType=\(evidence.contentType)
        width=\(evidence.width)
        height=\(evidence.height)
        frameCount=\(evidence.frameCount)
        contentKind=\(semantic.contentKind.rawValue)
        semanticConfidence=\(Self.number(semantic.confidence))
        semanticSummary=\(PromptText.quoted(semantic.summary, bytes: 640))
        Visual semantics come from bounded FastVLM perception structured by the text model. They do not prove exact duplication and never authorize deletion.
        """

        return AgentObservation(
            type: .imageContent,
            candidateID: candidateID,
            content: content,
            globalReferences: [globalReference],
            imageEvidence: evidence,
            imageSemantic: semantic,
            imageGlobalReferences: [globalReference]
        )
    }

    private static func isInside(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let candidatePath = candidate.standardizedFileURL.resolvingSymlinksInPath().path
        return candidatePath != rootPath
            && candidatePath.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

struct CompareImageContentTool {
    private let evidenceService: any ImageEvidenceInspecting
    private let semanticAnalyzer: any ImagePairSemanticAnalyzing

    init(
        evidenceService: any ImageEvidenceInspecting = AppleImageEvidenceService(),
        semanticAnalyzer: any ImagePairSemanticAnalyzing
    ) {
        self.evidenceService = evidenceService
        self.semanticAnalyzer = semanticAnalyzer
    }

    func execute(
        references: [String],
        candidateID: UUID,
        environment: AgentEnvironment,
        observations: [AgentObservation]
    ) async throws -> AgentObservation {
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

        let imageContent = observations.filter {
            $0.candidateID == candidateID && $0.type == .imageContent
        }
        func observation(for reference: String) -> AgentObservation? {
            imageContent.reversed().first {
                $0.imageSemantic?.globalReference == reference
                    && $0.imageEvidence?.globalReference == reference
            }
        }

        guard let firstObservation = observation(for: references[0]),
              let secondObservation = observation(for: references[1]),
              let firstEvidence = firstObservation.imageEvidence,
              let secondEvidence = secondObservation.imageEvidence,
              let firstSemantic = firstObservation.imageSemantic,
              let secondSemantic = secondObservation.imageSemantic else {
            throw ImageComparisonError.missingImageContentEvidence
        }

        let deterministic = try evidenceService.compareImages(
            firstURL: files[0].url,
            secondURL: files[1].url,
            first: firstEvidence,
            second: secondEvidence
        )
        let semantic = try await semanticAnalyzer.analyze(
            first: firstSemantic,
            second: secondSemantic,
            deterministic: deterministic
        )
        let comparison = ImageComparisonObservation(
            fileIDs: deterministic.fileIDs,
            globalReferences: references,
            deterministic: deterministic,
            semantic: semantic
        )

        let content = """
        \(references[0]) vs \(references[1])
        sameDimensions=\(deterministic.sameDimensions)
        aspectRatioDifference=\(Self.number(deterministic.aspectRatioDifference))
        featurePrintDistance=\(Self.number(deterministic.featurePrintDistance))
        semanticRelationship=\(semantic.relationship.rawValue)
        semanticConfidence=\(Self.number(semantic.confidence))
        semanticSummary=\(PromptText.quoted(semantic.summary, bytes: 640))
        Vision feature distance and semantic image relationships are similarity evidence only. They are not exact-duplicate verification and never authorize deletion.
        """

        return AgentObservation(
            type: .imageSemanticComparison,
            candidateID: candidateID,
            content: content,
            globalReferences: references,
            imageComparison: deterministic,
            imageSemanticComparison: comparison
        )
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
