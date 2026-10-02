import Foundation

nonisolated struct DeletionVerifier: Sendable {
    static func isInside(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let path = candidate.standardizedFileURL.resolvingSymlinksInPath().path
        return path != rootPath
            && path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")
    }

    static func verify(
        file: FileMetadata,
        lookup: FileLookup,
        root: URL
    ) throws {
        guard isInside(file.url, root: root),
              CleanupPolicy.allowedDispositions(
                for: file,
                root: root
              ).contains(.trash) else {
            throw FileVerificationError.keeperUnavailable
        }

        if let group = file.duplicateGroupID {
            guard let marker = file.duplicateMarker,
                  marker.hasPrefix("allpcc-"),
                  let keeperID = file.duplicateKeeperID,
                  keeperID != file.id,
                  let keeper = lookup.file(withID: keeperID),
                  keeper.duplicateGroupID == group,
                  keeper.duplicateMarker == marker,
                  keeper.duplicateKeeperID == keeper.id,
                  isInside(keeper.url, root: root),
                  FileManager.default.fileExists(atPath: keeper.url.path),
                  FileManager.default.fileExists(atPath: file.url.path) else {
                throw FileVerificationError.keeperUnavailable
            }
            return
        }

        if file.size == 0 && file.modifiedAt == nil {
            // allpcc intentionally does not keep a local metadata snapshot.
            guard FileManager.default.fileExists(atPath: file.url.path) else {
                throw FileVerificationError.changed
            }
            return
        }

        // Kept for execution-engine tests and any non-PCC record created outside
        // the allpcc scanner.
        let snapshot = try FileSnapshot.read(at: file.url)
        guard snapshot.size == file.size,
              snapshot.modifiedAt == file.modifiedAt else {
            throw FileVerificationError.changed
        }
    }
}
