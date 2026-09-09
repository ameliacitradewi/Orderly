import Foundation

enum ObservationType: String, Codable, Sendable {
    case candidate
    case metadata
    case comparison
    case content
    case discovery
    case documentComparison
    case imageEvidence
    case imageComparison
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
    let documentComparison: DocumentComparisonObservation?
    let imageEvidence: ImageEvidenceObservation?
    let imageComparison: DeterministicImageComparison?
    let pdfFileReferences: [String]?
    let pdfGlobalReferences: [String]?
    let imageFileReferences: [String]?
    let imageGlobalReferences: [String]?
    let unavailablePDFReferences: [String]?
    let unavailableImageReferences: [String]?

    init(
        id: UUID = UUID(),
        type: ObservationType,
        candidateID: UUID,
        content: String,
        contentObservation: ContentObservation? = nil,
        globalReferences: [String]? = nil,
        comparison: FileComparisonObservation? = nil,
        documentComparison: DocumentComparisonObservation? = nil,
        imageEvidence: ImageEvidenceObservation? = nil,
        imageComparison: DeterministicImageComparison? = nil,
        pdfFileReferences: [String]? = nil,
        pdfGlobalReferences: [String]? = nil,
        imageFileReferences: [String]? = nil,
        imageGlobalReferences: [String]? = nil,
        unavailablePDFReferences: [String]? = nil,
        unavailableImageReferences: [String]? = nil
    ) {
        self.id = id
        self.type = type
        self.candidateID = candidateID
        self.content = content
        self.contentObservation = contentObservation
        self.globalReferences = globalReferences
        self.comparison = comparison
        self.documentComparison = documentComparison
        self.imageEvidence = imageEvidence
        self.imageComparison = imageComparison
        self.pdfFileReferences = pdfFileReferences
        self.pdfGlobalReferences = pdfGlobalReferences
        self.imageFileReferences = imageFileReferences
        self.imageGlobalReferences = imageGlobalReferences
        self.unavailablePDFReferences = unavailablePDFReferences
        self.unavailableImageReferences = unavailableImageReferences
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
