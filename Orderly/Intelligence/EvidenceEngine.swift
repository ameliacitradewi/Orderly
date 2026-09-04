import Foundation

final class EvidenceEngine {

    func buildEvidence(
        candidates: [AnalysisCandidate],
        files: [FileMetadata],
        duplicateGroups: [DuplicateGroup],
        rootFolder: URL
    ) -> [CandidateEvidence] {

        let lookup = FileLookup(
            files: files
        )

        return candidates.compactMap { candidate in

            let candidateFiles =
                lookup.files(
                    withIDs: candidate.fileIDs
                )

            guard !candidateFiles.isEmpty else {
                return nil
            }

            return buildCandidateEvidence(
                candidate: candidate,
                files: candidateFiles,
                duplicateGroups: duplicateGroups,
                rootFolder: rootFolder
            )
        }
    }

    private func buildCandidateEvidence(
        candidate: AnalysisCandidate,
        files: [FileMetadata],
        duplicateGroups: [DuplicateGroup],
        rootFolder: URL
    ) -> CandidateEvidence {

        let referenceMap = FileReferenceMap(
            fileIDs: candidate.fileIDs
        )

        let fileEvidence: [CandidateFileEvidence] = files.compactMap { file in

            guard let reference = referenceMap.reference(
                for: file.id
            ) else {
                return nil
            }

            return CandidateFileEvidence(
                fileID: file.id,
                reference: reference,
                name: file.name,
                extensionName: file.extensionName,
                size: file.size,
                createdAt: file.createdAt,
                modifiedAt: file.modifiedAt,
                accessedAt: file.accessedAt,
                isHidden: file.isHidden,
                relativePath: relativePath(
                    for: file.url,
                    inside: rootFolder
                )
            )
        }

        let detectedSignals = signals(
            for: files,
            duplicateGroups: duplicateGroups
        )

        return CandidateEvidence(
            candidateID: candidate.id,
            files: fileEvidence,
            signals: detectedSignals
        )
    }

    private func signals(
        for files: [FileMetadata],
        duplicateGroups: [DuplicateGroup]
    ) -> [EvidenceSignal] {

        var signals = Set<EvidenceSignal>()

        if hasExactContentMatch(
            files: files,
            duplicateGroups: duplicateGroups
        ) {
            signals.insert(.exactContentMatch)
        }

        if hasSimilarFilename(files) {
            signals.insert(.similarFilename)
        }

        if files.contains(where: hasVersionLikeName) {
            signals.insert(.versionLikeName)
        }

        if hasSharedExtension(files) {
            signals.insert(.sameExtension)
        }

        if hasSimilarSize(files) {
            signals.insert(.similarSize)
        }

        if files.contains(where: \.isHidden) {
            signals.insert(.hiddenFile)
        }

        if files.contains(where: isMetadataArtifact) {
            signals.insert(.metadataArtifact)
        }

        if files.contains(where: isTemporaryLike) {
            signals.insert(.temporaryLike)
        }

        // Keep prompt output deterministic across runs.
        return EvidenceSignal.allCases.filter {
            signals.contains($0)
        }
    }

    private func hasExactContentMatch(
        files: [FileMetadata],
        duplicateGroups: [DuplicateGroup]
    ) -> Bool {

        let candidateFileIDs = Set(
            files.map(\.id)
        )

        return duplicateGroups.contains { group in
            group.files.reduce(0) { matchCount, fileID in
                matchCount + (candidateFileIDs.contains(fileID) ? 1 : 0)
            } >= 2
        }
    }

    private func hasSimilarFilename(
        _ files: [FileMetadata]
    ) -> Bool {

        guard files.count >= 2 else {
            return false
        }

        let normalizedNames = files.map {
            normalizedStem(for: $0)
        }

        for leftIndex in normalizedNames.indices {
            for rightIndex in normalizedNames.indices
            where rightIndex > leftIndex {

                let left = normalizedNames[leftIndex]
                let right = normalizedNames[rightIndex]

                guard !left.isEmpty,
                      !right.isEmpty
                else {
                    continue
                }

                if left == right {
                    return true
                }

                let shorterLength = min(
                    left.count,
                    right.count
                )

                guard shorterLength >= 4 else {
                    continue
                }

                let commonPrefixLength = zip(left, right)
                    .prefix { pair in
                        pair.0 == pair.1
                    }
                    .count

                if Double(commonPrefixLength)
                    / Double(shorterLength) >= 0.75 {
                    return true
                }
            }
        }

        return false
    }

    private func normalizedStem(
        for file: FileMetadata
    ) -> String {

        let stem = file.url
            .deletingPathExtension()
            .lastPathComponent
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )

        let tokens = stem
            .components(
                separatedBy: CharacterSet.alphanumerics.inverted
            )
            .filter { !$0.isEmpty }
            .filter { token in
                !isVersionToken(token)
            }

        return tokens.joined()
    }

    private func isVersionToken(
        _ token: String
    ) -> Bool {

        let lowercased = token.lowercased()

        if [
            "copy",
            "draft",
            "final",
            "latest",
            "new",
            "old"
        ].contains(lowercased) {
            return true
        }

        if lowercased.allSatisfy(\.isNumber) {
            return true
        }

        return lowercased.range(
            of: "^(v|ver|version|rev|revision)[0-9]+$",
            options: .regularExpression
        ) != nil
    }

    private func hasVersionLikeName(
        _ file: FileMetadata
    ) -> Bool {

        let stem = file.url
            .deletingPathExtension()
            .lastPathComponent
            .lowercased()

        let patterns = [
            "(^|[ ._-])(v|ver|version|rev|revision)[ ._-]*[0-9]+($|[ ._-])",
            "(^|[ ._-])(copy|draft|final|latest|new|old)([ ._-]*[0-9]+)?($|[ ._-])",
            "\\([0-9]+\\)$"
        ]

        return patterns.contains { pattern in
            stem.range(
                of: pattern,
                options: .regularExpression
            ) != nil
        }
    }

    private func hasSharedExtension(
        _ files: [FileMetadata]
    ) -> Bool {

        guard files.count >= 2 else {
            return false
        }

        let extensions = Set(
            files.map {
                $0.extensionName.lowercased()
            }
            .filter { !$0.isEmpty }
        )

        return extensions.count == 1
    }

    private func hasSimilarSize(
        _ files: [FileMetadata]
    ) -> Bool {

        guard files.count >= 2 else {
            return false
        }

        for leftIndex in files.indices {
            for rightIndex in files.indices
            where rightIndex > leftIndex {

                let leftSize = max(files[leftIndex].size, 0)
                let rightSize = max(files[rightIndex].size, 0)
                let largerSize = max(leftSize, rightSize)
                let difference = abs(leftSize - rightSize)

                if largerSize == 0 {
                    return true
                }

                let tolerance = max(
                    Int64(Double(largerSize) * 0.05),
                    4_096
                )

                if difference <= tolerance {
                    return true
                }
            }
        }

        return false
    }

    private func isMetadataArtifact(
        _ file: FileMetadata
    ) -> Bool {

        let name = file.name.lowercased()

        return name == ".ds_store"
            || name == "thumbs.db"
            || name == "desktop.ini"
            || name == ".directory"
            || name.hasPrefix("._")
    }

    private func isTemporaryLike(
        _ file: FileMetadata
    ) -> Bool {

        let name = file.name.lowercased()

        let temporarySuffixes = [
            ".tmp",
            ".temp",
            ".log",
            ".bak",
            ".swp",
            ".part",
            ".crdownload",
            "~"
        ]

        return temporarySuffixes.contains {
            name.hasSuffix($0)
        }
    }

    private func relativePath(
        for fileURL: URL,
        inside rootFolder: URL
    ) -> String {

        let rootComponents = rootFolder
            .standardizedFileURL
            .pathComponents

        let fileComponents = fileURL
            .standardizedFileURL
            .pathComponents

        guard fileComponents.count > rootComponents.count,
              Array(
                fileComponents.prefix(rootComponents.count)
              ) == rootComponents
        else {
            // Never expose an absolute path when metadata falls
            // outside the selected root unexpectedly.
            return fileURL.lastPathComponent
        }

        return fileComponents
            .dropFirst(rootComponents.count)
            .joined(separator: "/")
    }
}
