import Foundation

actor FileSystemService {
    /// Enumerates only filesystem handles for the PCC pipeline.
    ///
    /// The allpcc branch intentionally does not collect file size, dates, UTI,
    /// extended attributes, hashes, or other local metadata for AI analysis.
    /// Local code keeps only the URL/UUID mapping required for sandbox access,
    /// user review, and the final approved filesystem operation.
    func scanDirectory(at directoryURL: URL) throws -> [FileMetadata] {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants]
        ) else {
            throw FileSystemError.cannotEnumerateDirectory
        }

        let rootPath = directoryURL.standardizedFileURL
            .resolvingSymlinksInPath().path
        var files: [FileMetadata] = []

        for case let url as URL in enumerator {
            try Task.checkCancellation()

            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            let resolvedPath = resolved.path
            guard resolvedPath != rootPath,
                  resolvedPath.hasPrefix(rootPath == "/" ? "/" : rootPath + "/") else {
                enumerator.skipDescendants()
                continue
            }

            // This directory check is only a filesystem-boundary operation so the
            // app doesn't hand directories to the model. Its result is never used
            // as AI evidence or included in a prompt.
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: resolvedPath,
                isDirectory: &isDirectory
            ) else {
                continue
            }
            if isDirectory.boolValue {
                continue
            }

            let name = url.lastPathComponent
            files.append(
                FileMetadata(
                    id: UUID(),
                    url: url,
                    name: name,
                    extensionName: url.pathExtension,
                    size: 0,
                    createdAt: nil,
                    modifiedAt: nil,
                    accessedAt: nil,
                    isDirectory: false,
                    isHidden: name.hasPrefix("."),
                    uti: nil
                )
            )
        }

        return files.sorted { $0.url.path < $1.url.path }
    }
}

nonisolated enum FileSystemError: LocalizedError {
    case cannotEnumerateDirectory
    var errorDescription: String? { "Orderly could not read this folder." }
}
