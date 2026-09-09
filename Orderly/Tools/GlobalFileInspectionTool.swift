import Foundation

/// Reads only the scan snapshot. Neither operation opens a path supplied by the model.
struct GlobalFileInspectionTool {
    func inspect(file: FileMetadata, reference: String, candidateID: UUID,
                 environment: AgentEnvironment) -> AgentObservation {
        let local = environment.evidenceByCandidate[candidateID]?.files.first { $0.fileID == file.id }?.reference
        let relativePath = environment.catalog.relativePath(for: file, root: environment.analysis.analyzedFolder)
        return AgentObservation(
            type: .metadata, candidateID: candidateID,
            content: """
            globalReference=\(reference)
            localReference=\(local ?? "outsideCurrentCandidate")
            name=\(PromptText.quoted(file.name, bytes: 128))
            path=\(PromptText.quoted(relativePath, bytes: 192))
            tag=\(file.fileType.tagName)
            extension=\(PromptText.quoted(file.extensionName, bytes: 32))
            size=\(file.size)
            modified=\(file.modifiedAt?.formatted(.iso8601) ?? "unknown")
            duplicateCopies=\(file.duplicateCopyCount)
            Snapshot metadata only; semantic content has not been inspected. External files are context only and cannot receive proposals in this candidate.
            """,
            globalReferences: [reference],
            pdfGlobalReferences: InspectPDFContentTool.supports(file) ? [reference] : nil,
            imageGlobalReferences: InspectImageEvidenceTool.supports(file) ? [reference] : nil
        )
    }

    func compare(_ a: FileMetadata, _ b: FileMetadata, references: [String],
                 candidateID: UUID) -> AgentObservation {
        let comparison = FileComparisonObservation(a, b)
        let delta = a.modifiedAt.flatMap { left in b.modifiedAt.map { abs(left.timeIntervalSince($0)) } }
        return AgentObservation(
            type: .comparison, candidateID: candidateID,
            content: """
            \(references[0]) vs \(references[1])
            nameA=\(PromptText.quoted(a.name, bytes: 128))
            nameB=\(PromptText.quoted(b.name, bytes: 128))
            sameSize=\(a.size == b.size)
            sameFileType=\(a.fileType == b.fileType)
            modificationSecondsApart=\(delta.map { String($0) } ?? "unknown")
            verifiedDuplicate=\(comparison.verifiedDuplicate)
            Verification uses the scan's SHA256 group and digest, never a retrieval score. A false result means an exact match is not verified; metadata alone does not establish a shared project, revision, or session.
            """,
            globalReferences: references, comparison: comparison
        )
    }
}
