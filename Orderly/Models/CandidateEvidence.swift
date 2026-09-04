import Foundation

struct CandidateEvidence: Sendable {

    let candidateID: UUID

    let files: [CandidateFileEvidence]

    let signals: [EvidenceSignal]
}

struct CandidateFileEvidence: Sendable {

    let fileID: UUID

    /// Compact ID shown to the model.
    let reference: String

    let name: String
    let extensionName: String

    let size: Int64

    let createdAt: Date?
    let modifiedAt: Date?
    let accessedAt: Date?

    let isHidden: Bool

    let relativePath: String
}

enum EvidenceSignal: String, Sendable, CaseIterable {

    case exactContentMatch

    case similarFilename

    case versionLikeName

    case sameExtension

    case similarSize

    case hiddenFile

    case metadataArtifact

    case temporaryLike
}
