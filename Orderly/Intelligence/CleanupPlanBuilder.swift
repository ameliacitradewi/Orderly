import Foundation

final class CleanupPlanBuilder {

    func buildPlan(
        folder: URL,
        candidates: [AnalysisCandidate],
        modelPlan: ModelCleanupPlan,
        files: [FileMetadata]
    ) -> CleanupPlan {

        let candidateByID =
            Dictionary(
                uniqueKeysWithValues: candidates.map {
                    ($0.id, $0)
                }
            )

        let fileLookup =
            FileLookup(files: files)

        var processedCandidates =
            Set<UUID>()

        var actions: [CleanupAction] = []

        for recommendation in modelPlan.recommendations {

            let rawID =
                recommendation
                    .candidateID
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

            guard let candidateID =
                UUID(uuidString: rawID)
            else {
                continue
            }

            guard !processedCandidates.contains(candidateID),
                  let candidate = candidateByID[candidateID]
            else {
                continue
            }

            let referenceMap =
                FileReferenceMap(
                    fileIDs: candidate.fileIDs
                )

            var decisions: [UUID: FileDisposition] = [:]

            for decision in recommendation.fileDecisions {

                let reference =
                    decision
                        .fileReference
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )

                guard let fileID =
                    referenceMap.fileID(
                        for: decision.fileReference
                    )
                else {
                    // AI referenced an unknown file.
                    continue
                }

                guard candidate.fileIDs.contains(fileID),
                      fileLookup.file(withID: fileID) != nil
                else {
                    continue
                }

                // First valid decision wins.
                guard decisions[fileID] == nil else {
                    continue
                }

                decisions[fileID] =
                    decision.disposition
            }

            // Preserve the deterministic candidate order.
            let trashFileIDs = candidate.fileIDs.filter {
                decisions[$0] == .trash
            }

            let moveFileIDs = candidate.fileIDs.filter {
                decisions[$0] == .move
            }

            // MARK: Exact-duplicate safety invariant
            //
            // This is not deciding WHICH file should
            // be retained. The AI decides that.
            //
            // The app only refuses a plan that would
            // remove every copy.

            let safeTrashFileIDs: [UUID]

            if candidate.type == .duplicate,
               Set(trashFileIDs) == Set(candidate.fileIDs) {

                safeTrashFileIDs = []

            } else {

                safeTrashFileIDs =
                    trashFileIDs
            }

            let confidence =
                validatedConfidence(
                    recommendation: recommendation,
                    candidate: candidate
                )

            let explanation =
                cleanText(
                    recommendation.explanation,
                    fallback: candidate.reason,
                    maxLength: 500
                )

            // MARK: Trash recommendation

            if !safeTrashFileIDs.isEmpty {

                actions.append(
                    CleanupAction(
                        id: UUID(),
                        type: .trash,
                        title: cleanText(
                            recommendation.title,
                            fallback: "Review Files for Trash",
                            maxLength: 80
                        ),
                        explanation: explanation,
                        fileIDs: safeTrashFileIDs,
                        destination: nil,
                        riskLevel: .high,
                        confidence: confidence,
                        isSelected: false,
                        excludedFileIDs: []
                    )
                )
            }

            // MARK: Move recommendation

            if !moveFileIDs.isEmpty,
               let destination =
                    safeDestination(
                        inside: folder,
                        suggestedName: recommendation
                            .destinationFolderName
                    ) {

                actions.append(
                    CleanupAction(
                        id: UUID(),
                        type: .move,
                        title: cleanText(
                            recommendation.title,
                            fallback: "Organize Files",
                            maxLength: 80
                        ),
                        explanation: explanation,
                        fileIDs: moveFileIDs,
                        destination: destination,
                        riskLevel: .low,
                        confidence: confidence,
                        isSelected: false,
                        excludedFileIDs: []
                    )
                )
            }

            processedCandidates.insert(candidateID)
        }

        let summary =
            actions.isEmpty
            ? "No safe cleanup actions were recommended."
            : cleanText(
                modelPlan.summary,
                fallback: "\(actions.count) cleanup actions were recommended.",
                maxLength: 240
            )

        return CleanupPlan(
            id: UUID(),
            folder: folder,
            summary: summary,
            actions: actions,
            createdAt: Date()
        )
    }

    // MARK: - Destination Security

    private func safeDestination(
        inside folder: URL,
        suggestedName: String
    ) -> URL? {

        let name =
            suggestedName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        guard !name.isEmpty,
              name != ".",
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

        let aiConfidence =
            min(
                max(recommendation.confidence, 0),
                1
            )

        let evidenceConfidence =
            min(
                max(candidate.confidence, 0),
                1
            )

        return min(
            aiConfidence,
            evidenceConfidence
        )
    }

    private func cleanText(
        _ value: String,
        fallback: String,
        maxLength: Int
    ) -> String {

        let trimmed =
            value.trimmingCharacters(
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
