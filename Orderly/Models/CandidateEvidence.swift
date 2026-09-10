import Foundation

struct CandidateEvidence: Sendable {
    let candidateID: UUID
    let files: [CandidateFileEvidence]
}

struct CandidateFileEvidence: Sendable {
    let fileID: UUID
    let reference: String
    let name: String
    let tag: FileType
    let size: Int64
    let modifiedAt: Date?
    let relativePath: String
    let allowedDispositions: [FileDisposition]
    let isInstallerCandidate: Bool
    let duplicateCopyCount: Int
    let duplicateKeeperName: String?
    let duplicateKeeperModifiedAt: Date?
}
