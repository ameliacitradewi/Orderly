//
//  DuplicateDetector.swift
//  Orderly
//

import Foundation
import CryptoKit

final class DuplicateDetector {

    func findDuplicates(
        in files: [FileMetadata]
    ) async -> [DuplicateGroup] {

        let groupedBySize = Dictionary(
            grouping: files.filter { !$0.isDirectory },
            by: { $0.size }
        )

        var duplicateGroups: [DuplicateGroup] = []

        for (_, candidates) in groupedBySize {

            guard candidates.count > 1 else {
                continue
            }

            var hashGroups: [String: [FileMetadata]] = [:]

            for file in candidates {

                guard let hash = await hashFile(
                    at: file.url
                ) else {
                    continue
                }

                hashGroups[hash, default: []].append(file)
            }

            for (_, matchingFiles) in hashGroups {

                guard matchingFiles.count > 1 else {
                    continue
                }

                let group = DuplicateGroup(
                    id: UUID(),
                    files: matchingFiles.map(\.id),
                    fileSize: matchingFiles[0].size,
                    detectionMethod: .exactHash
                )

                duplicateGroups.append(group)
            }
        }

        return duplicateGroups
    }

    private func hashFile(
        at url: URL
    ) async -> String? {

        do {

            let handle = try FileHandle(
                forReadingFrom: url
            )

            defer {
                try? handle.close()
            }

            var hasher = SHA256()

            while true {

                let data = try handle.read(
                    upToCount: 1_048_576
                )

                guard let data, !data.isEmpty else {
                    break
                }

                hasher.update(data: data)
            }

            let digest = hasher.finalize()

            return digest
                .map {
                    String(
                        format: "%02x",
                        $0
                    )
                }
                .joined()

        } catch {

            print(
                "Orderly: Failed to hash \(url): \(error)"
            )

            return nil
        }
    }
}
