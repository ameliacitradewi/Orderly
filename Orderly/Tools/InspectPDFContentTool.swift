import Foundation

struct InspectPDFContentTool {
    private let contentInspectionService: any ContentInspectionService

    init(
        contentInspectionService: any ContentInspectionService = PDFTextExtractor()
    ) {
        self.contentInspectionService = contentInspectionService
    }

    func execute(
        file: FileMetadata,
        fileReference: String,
        candidateID: UUID,
        analyzedFolder: URL
    ) throws -> AgentObservation {
        guard Self.supports(file) else {
            throw ContentInspectionError.unsupportedFileType
        }

        guard Self.isInside(file.url, root: analyzedFolder) else {
            throw ContentInspectionError.fileOutsideAnalyzedFolder
        }

        let inspected = try contentInspectionService.inspectPDF(
            at: file.url,
            fileReference: fileReference,
            maxExcerptCharacters: AgentContextBudget.maxContentExcerptCharacters
        )
        let content = """
        reference=\(inspected.fileReference)
        contentType=\(inspected.contentType)
        pages=\(inspected.pageCount.map(String.init) ?? "unknown")
        extractedCharacters=\(inspected.extractedCharacterCount)
        truncated=\(inspected.truncated)
        excerpt:
        \(inspected.excerpt)
        """

        return AgentObservation(
            type: .content,
            candidateID: candidateID,
            content: content,
            contentObservation: inspected
        )
    }

    static func supports(_ file: FileMetadata) -> Bool {
        !file.isDirectory && file.extensionName.lowercased() == "pdf"
    }

    private static func isInside(
        _ candidate: URL,
        root: URL
    ) -> Bool {
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
