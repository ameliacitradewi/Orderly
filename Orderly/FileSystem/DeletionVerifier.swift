import Foundation

nonisolated struct DeletionVerifier: Sendable {
    static func isInside(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let path = candidate.standardizedFileURL.resolvingSymlinksInPath().path
        return path != rootPath && path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")
    }

    static func verify(file: FileMetadata, lookup: FileLookup, root: URL) throws {
        guard isInside(file.url, root: root),
              CleanupPolicy.resolve(.trash, for: file, root: root) == .trash else {
            throw FileVerificationError.keeperUnavailable
        }
        if let group = file.duplicateGroupID {
            guard let hash = file.duplicateSHA256,
                  let keeperID = file.duplicateKeeperID, keeperID != file.id,
                  let keeper = lookup.file(withID: keeperID), keeper.duplicateGroupID == group,
                  keeper.duplicateSHA256 == hash, keeper.duplicateKeeperID == keeper.id,
                  isInside(keeper.url, root: root) else { throw FileVerificationError.keeperUnavailable }
            // Rehash both byte streams immediately before each deletion. Cached hashes
            // alone are insufficient when a file changes while the user reviews the plan.
            guard try DuplicateDetector.digest(at: keeper.url, matching: keeper) == hash,
                  try DuplicateDetector.digest(at: file.url, matching: file) == hash else {
                throw FileVerificationError.keeperUnavailable
            }
        } else {
            let snapshot = try FileSnapshot.read(at: file.url)
            guard snapshot.size == file.size, snapshot.modifiedAt == file.modifiedAt else {
                throw FileVerificationError.changed
            }
        }
    }
}
