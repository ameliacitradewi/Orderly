import Foundation

final class CleanupPlanBuilder {

    func buildPlan(
        folder: URL,
        candidates: [AnalysisCandidate],
        modelPlan: ModelCleanupPlan,
        files: [FileMetadata]
    ) -> CleanupPlan {

        let candidateByID = Dictionary(
            uniqueKeysWithValues: candidates.map {
                ($0.id, $0)
            }
        )

        let fileLookup = FileLookup(files: files)

        var seenCandidateIDs = Set<UUID>()
        var actions: [CleanupAction] = []

        for recommendation in modelPlan.recommendations {

            // AI returns String.
            // The app converts it back into a real UUID.
            guard let candidateID = UUID(
                uuidString: recommendation.candidateID
            ) else {
                continue
            }

            // Prevent the same candidate from appearing twice.
            guard !seenCandidateIDs.contains(candidateID) else {
                continue
            }

            // Candidate must really exist in deterministic analysis.
            guard let candidate = candidateByID[candidateID] else {
                continue
            }

            // AI is not allowed to choose an incompatible action.
            guard isAllowed(
                recommendation.intent,
                for: candidate.type
            ) else {
                continue
            }

            guard let action = makeAction(
                from: candidate,
                recommendation: recommendation,
                folder: folder,
                fileLookup: fileLookup
            ) else {
                continue
            }

            seenCandidateIDs.insert(candidateID)
            actions.append(action)
        }

        let summary: String

        if actions.isEmpty {
            summary = "No safe cleanup actions were identified."
        } else {
            summary = cleanText(
                modelPlan.summary,
                fallback: "\(actions.count) cleanup actions were identified.",
                maxLength: 240
            )
        }

        return CleanupPlan(
            id: UUID(),
            folder: folder,
            summary: summary,
            actions: actions,
            createdAt: Date()
        )
    }

    // MARK: - Validation

    private func isAllowed(
        _ intent: RecommendationIntent,
        for candidateType: CandidateType
    ) -> Bool {

        switch (candidateType, intent) {

        case (.grouping, .organize),
             (.grouping, .review),
             (.grouping, .skip):

            return true

        case (.archive, .archive),
             (.archive, .review),
             (.archive, .skip):

            return true

        case (.duplicate, .reviewDuplicates),
             (.duplicate, .skip):

            return true

        case (.temporary, .reviewForTrash),
             (.temporary, .review),
             (.temporary, .skip):

            return true

        case (.redundant, .reviewForTrash),
             (.redundant, .review),
             (.redundant, .skip):

            return true

        case (.review, .review),
             (.review, .skip):

            return true

        default:
            return false
        }
    }

    // MARK: - Action Builder

    private func makeAction(
        from candidate: AnalysisCandidate,
        recommendation: CleanupRecommendation,
        folder: URL,
        fileLookup: FileLookup
    ) -> CleanupAction? {

        let existingFileIDs = candidate.fileIDs.filter {
            fileLookup.file(withID: $0) != nil
        }

        guard !existingFileIDs.isEmpty else {
            return nil
        }

        let confidence = validatedConfidence(
            recommendation: recommendation,
            candidate: candidate
        )

        let explanation = cleanText(
            recommendation.explanation,
            fallback: candidate.reason,
            maxLength: 400
        )

        switch recommendation.intent {

        case .organize:

            guard let destination = safeDestination(
                inside: folder,
                suggestedName:
                    recommendation.destinationFolderName
            ) else {
                return nil
            }

            return CleanupAction(
                id: UUID(),
                type: .move,
                title: cleanText(
                    recommendation.title,
                    fallback: "Organize Files",
                    maxLength: 80
                ),
                explanation: explanation,
                fileIDs: existingFileIDs,
                destination: destination,
                riskLevel: .low,
                confidence: confidence,
                isSelected: confidence >= 0.85,
                excludedFileIDs: []
            )

        case .archive:

            guard let destination = safeDestination(
                inside: folder,
                suggestedName:
                    recommendation.destinationFolderName,
                fallback: "Archive"
            ) else {
                return nil
            }

            return CleanupAction(
                id: UUID(),
                type: .move,
                title: cleanText(
                    recommendation.title,
                    fallback: "Archive Files",
                    maxLength: 80
                ),
                explanation: explanation,
                fileIDs: existingFileIDs,
                destination: destination,
                riskLevel: .medium,
                confidence: confidence,
                isSelected: confidence >= 0.90,
                excludedFileIDs: []
            )

        case .reviewDuplicates:

            // A duplicate candidate should contain at least 2 files.
            guard existingFileIDs.count >= 2 else {
                return nil
            }

            // Important:
            // Keep at least one copy excluded by default.
            guard let keeperID = defaultKeeperID(
                from: existingFileIDs,
                fileLookup: fileLookup
            ) else {
                return nil
            }

            return CleanupAction(
                id: UUID(),
                type: .trash,
                title: cleanText(
                    recommendation.title,
                    fallback: "Review Duplicate Files",
                    maxLength: 80
                ),
                explanation: explanation,
                fileIDs: existingFileIDs,
                destination: nil,
                riskLevel: .high,
                confidence: confidence,

                // Trash actions are NEVER pre-approved.
                isSelected: false,

                // One duplicate is protected by default.
                excludedFileIDs: [keeperID]
            )

        case .reviewForTrash:

            return CleanupAction(
                id: UUID(),
                type: .trash,
                title: cleanText(
                    recommendation.title,
                    fallback: "Review Files for Trash",
                    maxLength: 80
                ),
                explanation: explanation,
                fileIDs: existingFileIDs,
                destination: nil,
                riskLevel: .high,
                confidence: confidence,

                // Never preselect destructive actions.
                isSelected: false,

                excludedFileIDs: []
            )

        case .review,
             .skip:

            // These are advisory recommendations,
            // not executable filesystem actions.
            return nil
        }
    }

    // MARK: - Duplicate Safety

    private func defaultKeeperID(
        from fileIDs: [UUID],
        fileLookup: FileLookup
    ) -> UUID? {

        let files = fileLookup.files(
            withIDs: fileIDs
        )

        let sortedFiles = files.sorted { lhs, rhs in

            // Prefer visible files over hidden ones.
            if lhs.isHidden != rhs.isHidden {
                return !lhs.isHidden
            }

            // Prefer the file closer to the selected folder root.
            let lhsDepth = lhs.url.pathComponents.count
            let rhsDepth = rhs.url.pathComponents.count

            if lhsDepth != rhsDepth {
                return lhsDepth < rhsDepth
            }

            // Prefer the more recently modified copy.
            let lhsDate =
                lhs.modifiedAt ?? Date.distantPast

            let rhsDate =
                rhs.modifiedAt ?? Date.distantPast

            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }

            // Final stable tie-breaker.
            return lhs.url.path.localizedStandardCompare(
                rhs.url.path
            ) == .orderedAscending
        }

        return sortedFiles.first?.id
    }

    // MARK: - Destination Safety

    private func safeDestination(
        inside folder: URL,
        suggestedName: String,
        fallback: String? = nil
    ) -> URL? {

        var name = suggestedName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if name.isEmpty,
           let fallback {
            name = fallback
        }

        guard !name.isEmpty else {
            return nil
        }

        guard name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\n"),
              !name.contains("\r"),
              name.count <= 80
        else {
            return nil
        }

        let root =
            folder.standardizedFileURL

        let destination =
            root
                .appendingPathComponent(
                    name,
                    isDirectory: true
                )
                .standardizedFileURL

        // Destination must remain a direct child
        // of the selected folder.
        guard destination
            .deletingLastPathComponent()
            .standardizedFileURL == root
        else {
            return nil
        }

        return destination
    }

    // MARK: - Confidence

    private func validatedConfidence(
        recommendation: CleanupRecommendation,
        candidate: AnalysisCandidate
    ) -> Double {

        let aiConfidence = min(
            max(recommendation.confidence, 0),
            1
        )

        let candidateConfidence = min(
            max(candidate.confidence, 0),
            1
        )

        // AI cannot raise confidence above the
        // deterministic candidate confidence.
        return min(
            aiConfidence,
            candidateConfidence
        )
    }

    // MARK: - UI Text

    private func cleanText(
        _ value: String,
        fallback: String,
        maxLength: Int
    ) -> String {

        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let result =
            trimmed.isEmpty
            ? fallback
            : trimmed

        return String(
            result.prefix(maxLength)
        )
    }
}
