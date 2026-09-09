import Foundation

enum ObservationType: String, Codable, Sendable {
    case candidate
    case metadata
    case comparison
    case content
    case discovery
    case error
}

struct AgentObservation: Codable, Sendable {
    let id: UUID
    let type: ObservationType
    let candidateID: UUID
    let content: String
    let contentObservation: ContentObservation?
    let globalReferences: [String]?
    let comparison: FileComparisonObservation?
    let pdfFileReferences: [String]?
    let unavailablePDFReferences: [String]?

    init(
        id: UUID = UUID(),
        type: ObservationType,
        candidateID: UUID,
        content: String,
        contentObservation: ContentObservation? = nil,
        globalReferences: [String]? = nil,
        comparison: FileComparisonObservation? = nil,
        pdfFileReferences: [String]? = nil,
        unavailablePDFReferences: [String]? = nil
    ) {
        self.id = id
        self.type = type
        self.candidateID = candidateID
        self.content = content
        self.contentObservation = contentObservation
        self.globalReferences = globalReferences
        self.comparison = comparison
        self.pdfFileReferences = pdfFileReferences
        self.unavailablePDFReferences = unavailablePDFReferences
    }
}

/// Trusted comparison facts, separate from filenames and other untrusted text.
struct FileComparisonObservation: Codable, Sendable {
    let fileIDs: [UUID]
    let verifiedDuplicate: Bool

    init(_ a: FileMetadata, _ b: FileMetadata) {
        fileIDs = [a.id, b.id]
        verifiedDuplicate = a.id != b.id && a.size == b.size
            && a.duplicateGroupID != nil && a.duplicateGroupID == b.duplicateGroupID
            && a.duplicateSHA256?.isEmpty == false && a.duplicateSHA256 == b.duplicateSHA256
    }

    init(fileIDs: [UUID], verifiedDuplicate: Bool) {
        self.fileIDs = fileIDs
        self.verifiedDuplicate = verifiedDuplicate
    }
}
