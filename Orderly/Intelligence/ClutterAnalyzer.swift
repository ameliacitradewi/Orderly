//
//  ClutterAnalyzer.swift
//  Orderly
//

import Foundation

final class ClutterAnalyzer {

    func analyze(
        files: [FileMetadata],
        duplicateGroups: [DuplicateGroup]
    ) -> [AnalysisCandidate] {

        var candidates: [AnalysisCandidate] = []

        for group in duplicateGroups {

            candidates.append(
                AnalysisCandidate(
                    id: UUID(),
                    type: .duplicate,
                    fileIDs: group.files,
                    confidence: 1.0,
                    reason: "These files have identical contents."
                )
            )
        }

        let temporaryFiles = files.filter {
            isLikelyTemporary($0)
        }

        if !temporaryFiles.isEmpty {

            candidates.append(
                AnalysisCandidate(
                    id: UUID(),
                    type: .temporary,
                    fileIDs: temporaryFiles.map(\.id),
                    confidence: 0.8,
                    reason: "These files appear to be temporary files."
                )
            )
        }

        return candidates
    }

    private func isLikelyTemporary(
        _ file: FileMetadata
    ) -> Bool {

        let name = file.name.lowercased()

        let temporaryPatterns = [
            ".tmp",
            ".temp",
            ".log",
            "~",
            ".bak"
        ]

        return temporaryPatterns.contains {
            name.hasSuffix($0)
        }
    }
}
