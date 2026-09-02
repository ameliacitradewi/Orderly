//
//  FileClassifier.swift
//  Orderly
//

import Foundation

final class FileClassifier {

    func summarize(
        files: [FileMetadata]
    ) -> [FileTypeSummary] {

        var result: [FileType: (count: Int, size: Int64)] = [:]

        for file in files {

            let type = file.fileType

            let current = result[type] ?? (
                count: 0,
                size: 0
            )

            result[type] = (
                count: current.count + 1,
                size: current.size + file.size
            )
        }

        return result.map {
            FileTypeSummary(
                type: $0.key,
                count: $0.value.count,
                totalSize: $0.value.size
            )
        }
        .sorted {
            $0.count > $1.count
        }
    }
}
