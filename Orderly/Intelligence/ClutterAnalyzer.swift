import Foundation

final class ClutterAnalyzer {

    func analyze(
        files: [FileMetadata],
        duplicateGroups: [DuplicateGroup]
    ) -> [AnalysisCandidate] {

        var candidates: [AnalysisCandidate] = []

        // MARK: Exact duplicates

        let duplicateFileIDs = Set(
            duplicateGroups.flatMap(\.files)
        )

        for group in duplicateGroups {

            candidates.append(
                AnalysisCandidate(
                    id: UUID(),
                    type: .duplicate,
                    fileIDs: group.files,
                    confidence: 1.0,
                    reason: "These files have identical contents verified by SHA-256."
                )
            )
        }

        // Do not create overlapping candidates
        // for files already covered by exact duplicates.
        let remainingFiles = files.filter {
            !duplicateFileIDs.contains($0.id)
        }

        // MARK: Metadata artifacts

        let artifactFiles =
            remainingFiles.filter {
                isMetadataArtifact($0)
            }

        if !artifactFiles.isEmpty {

            candidates.append(
                AnalysisCandidate(
                    id: UUID(),
                    type: .artifact,
                    fileIDs: artifactFiles.map(\.id),
                    confidence: 0.95,
                    reason: "These files have characteristics commonly associated with filesystem metadata artifacts."
                )
            )
        }

        let artifactIDs =
            Set(artifactFiles.map(\.id))

        // MARK: Temporary-like files

        let temporaryFiles =
            remainingFiles.filter {
                !artifactIDs.contains($0.id)
                    && isLikelyTemporary($0)
            }

        if !temporaryFiles.isEmpty {

            candidates.append(
                AnalysisCandidate(
                    id: UUID(),
                    type: .temporary,
                    fileIDs: temporaryFiles.map(\.id),
                    confidence: 0.80,
                    reason: "These files have filenames commonly associated with temporary or intermediate files."
                )
            )
        }

        let temporaryIDs =
            Set(temporaryFiles.map(\.id))

        // MARK: Possible versions / related files

        let relationshipFiles =
            remainingFiles.filter {
                !artifactIDs.contains($0.id)
                    && !temporaryIDs.contains($0.id)
            }

        for group in relatedFileGroups(
            relationshipFiles
        ) {

            candidates.append(
                AnalysisCandidate(
                    id: UUID(),
                    type: .related,
                    fileIDs: group.map(\.id),
                    confidence: 0.75,
                    reason: "These files have closely related filenames and may represent different versions of the same item."
                )
            )
        }

        return candidates
    }

    // MARK: - Related Files

    private func relatedFileGroups(
        _ files: [FileMetadata]
    ) -> [[FileMetadata]] {

        var groups: [String: [FileMetadata]] = [:]

        for file in files {

            let canonical =
                canonicalStem(for: file)

            guard canonical.count >= 2 else {
                continue
            }

            let extensionName =
                file.extensionName.lowercased()

            let key =
                "\(extensionName)|\(canonical)"

            groups[key, default: []]
                .append(file)
        }

        return groups.values
            .filter {
                $0.count >= 2
            }
    }

    /// Removes common version/copy suffixes only.
    ///
    /// Example:
    /// new.zip       -> new
    /// new_v2.zip    -> new
    /// report_final  -> report
    /// report_v3     -> report
    private func canonicalStem(
        for file: FileMetadata
    ) -> String {

        var stem = file.url
            .deletingPathExtension()
            .lastPathComponent
            .lowercased()

        let patterns = [

            // _v2, -version3, rev_4
            #"(?i)[ ._-]+(?:v|ver|version|rev|revision)[ ._-]*[0-9]+$"#,

            // copy, final, draft, old, latest
            #"(?i)[ ._-]+(?:copy|draft|final|latest|old)(?:[ ._-]*[0-9]+)?$"#,

            // Finder-style "(2)"
            #"\s*\([0-9]+\)$"#
        ]

        for pattern in patterns {

            stem = stem.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        return stem
            .trimmingCharacters(
                in: CharacterSet(
                    charactersIn: " ._-"
                )
            )
    }

    // MARK: - Evidence Candidate Detection

    private func isMetadataArtifact(
        _ file: FileMetadata
    ) -> Bool {

        let name =
            file.name.lowercased()

        return name == ".ds_store"
            || name == "thumbs.db"
            || name == "desktop.ini"
            || name == ".directory"
            || name.hasPrefix("._")
    }

    private func isLikelyTemporary(
        _ file: FileMetadata
    ) -> Bool {

        let name =
            file.name.lowercased()

        let suffixes = [
            ".tmp",
            ".temp",
            ".log",
            ".bak",
            ".swp",
            ".part",
            ".crdownload",
            "~"
        ]

        return suffixes.contains {
            name.hasSuffix($0)
        }
    }
}
