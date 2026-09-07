import Foundation

actor FileSystemService {
    func scanDirectory(at directoryURL: URL) throws -> [FileMetadata] {
        let keys: Set<URLResourceKey> = [
            .nameKey, .isDirectoryKey, .isRegularFileKey, .isPackageKey, .isSymbolicLinkKey,
            .isHiddenKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey,
            .contentAccessDateKey, .typeIdentifierKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]
        ) else { throw FileSystemError.cannotEnumerateDirectory }
        var files: [FileMetadata] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            do {
                let values = try url.resourceValues(forKeys: keys)
                guard values.isSymbolicLink != true else { enumerator.skipDescendants(); continue }
                let isDirectory = values.isDirectory ?? false
                let isDocumentPackage = isDirectory && PackageContents.supportedExtensions.contains(url.pathExtension.lowercased())
                if isDocumentPackage { enumerator.skipDescendants() }
                guard values.isRegularFile == true || isDocumentPackage else { continue }
                let size = isDocumentPackage ? try PackageContents.snapshot(at: url).totalSize
                    : Int64(values.fileSize ?? 0)
                files.append(FileMetadata(
                    id: UUID(), url: url, name: values.name ?? url.lastPathComponent,
                    extensionName: url.pathExtension, size: size, createdAt: values.creationDate,
                    modifiedAt: values.contentModificationDate, accessedAt: values.contentAccessDate,
                    isDirectory: isDirectory, isHidden: values.isHidden ?? false, uti: values.typeIdentifier
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Do not invent metadata for an inaccessible item.
                continue
            }
        }
        return files.sorted { $0.url.path < $1.url.path }
    }
}

nonisolated enum FileSystemError: LocalizedError {
    case cannotEnumerateDirectory
    var errorDescription: String? { "Orderly could not read this folder." }
}
