//
//  FileSystemService.swift
//  Orderly
//

import Foundation

final class FileSystemService {

    private let fileManager = FileManager.default

    func scanDirectory(
        at directoryURL: URL
    ) throws -> [FileMetadata] {

        let keys: [URLResourceKey] = [
            .nameKey,
            .isDirectoryKey,
            .isHiddenKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .contentAccessDateKey,
            .typeIdentifierKey
        ]

        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [
                .skipsPackageDescendants
            ]
        ) else {
            throw FileSystemError.cannotEnumerateDirectory
        }

        var files: [FileMetadata] = []

        for case let url as URL in enumerator {

            do {
                let resourceValues = try url.resourceValues(
                    forKeys: Set(keys)
                )

                let isDirectory =
                    resourceValues.isDirectory ?? false

                if isDirectory {
                    continue
                }

                let fileMetadata = FileMetadata(
                    id: UUID(),
                    url: url,
                    name: resourceValues.name
                        ?? url.lastPathComponent,
                    extensionName: url.pathExtension,
                    size: Int64(
                        resourceValues.fileSize ?? 0
                    ),
                    createdAt: resourceValues.creationDate,
                    modifiedAt: resourceValues.contentModificationDate,
                    accessedAt: resourceValues.contentAccessDate,
                    isDirectory: false,
                    isHidden: resourceValues.isHidden ?? false,
                    uti: resourceValues.typeIdentifier
                )

                files.append(fileMetadata)

            } catch {
                print(
                    "Orderly: Could not read \(url): \(error)"
                )
            }
        }

        return files
    }
}

enum FileSystemError: LocalizedError {
    case cannotEnumerateDirectory

    var errorDescription: String? {
        switch self {
        case .cannotEnumerateDirectory:
            return "Orderly could not read this folder."
        }
    }
}
