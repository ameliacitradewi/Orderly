import Foundation

nonisolated struct DeletionVerifier: Sendable {
    static func isInside(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let path = candidate.standardizedFileURL.resolvingSymlinksInPath().path
        return path != rootPath && path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")
    }

    static func verify(file: FileMetadata, lookup: FileLookup, root: URL) throws {
        guard isInside(file.url, root: root),
              CleanupPolicy.allowedDispositions(for: file, root: root).contains(.trash) else {
            throw FileVerificationError.keeperUnavailable
        }
        if let group = file.duplicateGroupID {
            guard let marker = file.duplicateSHA256,
                  let keeperID = file.duplicateKeeperID, keeperID != file.id,
                  let keeper = lookup.file(withID: keeperID), keeper.duplicateGroupID == group,
                  keeper.duplicateSHA256 == marker, keeper.duplicateKeeperID == keeper.id,
                  isInside(keeper.url, root: root) else {
                throw FileVerificationError.keeperUnavailable
            }

            if marker.hasPrefix("allpcc-") {
                // allpcc intentionally avoids local content hashing. Immediately
                // before the approved mutation, revalidate only the authority
                // boundary and that both PCC-referenced files still exist.
                guard FileManager.default.fileExists(atPath: keeper.url.path),
                      FileManager.default.fileExists(atPath: file.url.path) else {
                    throw FileVerificationError.keeperUnavailable
                }
                return
            }

            // Legacy deterministic duplicate groups still use local digest
            // verification when their marker is an actual digest.
            guard try DuplicateDetector.digest(at: keeper.url, matching: keeper) == marker,
                  try DuplicateDetector.digest(at: file.url, matching: file) == marker else {
                throw FileVerificationError.keeperUnavailable
            }
        } else {
            if file.size == 0 && file.modifiedAt == nil {
                // Synthetic allpcc file records deliberately have no local
                // metadata snapshot. User approval plus live path/existence checks
                // are the final execution boundary for these records.
                guard FileManager.default.fileExists(atPath: file.url.path) else {
                    throw FileVerificationError.changed
                }
                return
            }

            let snapshot = try FileSnapshot.read(at: file.url)
            guard snapshot.size == file.size, snapshot.modifiedAt == file.modifiedAt else {
                throw FileVerificationError.changed
            }
        }
    }
}
