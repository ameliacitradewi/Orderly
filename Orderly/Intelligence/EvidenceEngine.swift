import Foundation

final class EvidenceEngine {
    func buildEvidence(candidates: [AnalysisCandidate], files: [FileMetadata],
                       duplicateGroups: [DuplicateGroup], rootFolder: URL) -> [CandidateEvidence] {
        let lookup = FileLookup(files: files)
        return candidates.map { candidate in
            let references = FileReferenceMap(fileIDs: candidate.fileIDs)
            return CandidateEvidence(candidateID: candidate.id, files: candidate.fileIDs.compactMap { id in
                guard let file = lookup.file(withID: id), let reference = references.reference(for: id) else { return nil }
                let keeper = file.duplicateKeeperID.flatMap { lookup.file(withID: $0) }
                let components = file.url.standardizedFileURL.pathComponents
                let root = rootFolder.standardizedFileURL.pathComponents
                let relative = Array(components.prefix(root.count)) == root
                    ? components.dropFirst(root.count).joined(separator: "/") : file.name
                return CandidateFileEvidence(
                    fileID: id, reference: reference, name: file.name, tag: file.fileType,
                    size: file.size, modifiedAt: file.modifiedAt, relativePath: relative,
                    requiredDisposition: CleanupPolicy.requiredDisposition(for: file, root: rootFolder),
                    isInstallerCandidate: CleanupPolicy.isInstallerCandidate(file),
                    duplicateCopyCount: file.duplicateCopyCount,
                    duplicateKeeperName: keeper?.name, duplicateKeeperModifiedAt: keeper?.modifiedAt
                )
            })
        }
    }
}
