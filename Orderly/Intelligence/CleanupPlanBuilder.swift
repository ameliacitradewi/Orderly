import Foundation

final class CleanupPlanBuilder {

    func buildPlan(
        folder: URL,
        candidates: [AnalysisCandidate],
        files: [FileMetadata]
    ) -> CleanupPlan {
        let actions = candidates.compactMap { candidate in
            makeAction(from: candidate, files: files)
        }

        return CleanupPlan(
            id: UUID(),
            folder: folder,
            summary: makeSummary(actions: actions),
            actions: actions,
            createdAt: Date()
        )
    }

    private func makeAction(
        from candidate: AnalysisCandidate,
        files: [FileMetadata]
    ) -> CleanupAction? {
        let existingFileIDs = candidate.fileIDs.filter { candidateID in
            files.contains { file in
                file.id == candidateID
            }
        }

        guard !existingFileIDs.isEmpty else {
            return nil
        }

        switch candidate.type {
        case .grouping:
            return CleanupAction(
                id: UUID(),
                type: .move,
                title: "Group Files",
                explanation: candidate.reason,
                fileIDs: existingFileIDs,
                destination: nil,
                riskLevel: .low,
                confidence: candidate.confidence,
                isSelected: candidate.confidence >= 0.85,
                excludedFileIDs: []
            )
        case .duplicate:
            return CleanupAction(
                id: UUID(),
                type: .trash,
                title: "Review Duplicate Files",
                explanation: candidate.reason,
                fileIDs: existingFileIDs,
                destination: nil,
                riskLevel: .high,
                confidence: candidate.confidence,
                isSelected: false,
                excludedFileIDs: []
            )
        case .temporary:
            return CleanupAction(
                id: UUID(),
                type: .trash,
                title: "Move Temporary Files to Trash",
                explanation: candidate.reason,
                fileIDs: existingFileIDs,
                destination: nil,
                riskLevel: .high,
                confidence: candidate.confidence,
                isSelected: false,
                excludedFileIDs: []
            )
        case .redundant:
            return CleanupAction(
                id: UUID(),
                type: .trash,
                title: "Review Redundant Files",
                explanation: candidate.reason,
                fileIDs: existingFileIDs,
                destination: nil,
                riskLevel: .high,
                confidence: candidate.confidence,
                isSelected: false,
                excludedFileIDs: []
            )
        case .archive:
            return CleanupAction(
                id: UUID(),
                type: .move,
                title: "Organize Archive Files",
                explanation: candidate.reason,
                fileIDs: existingFileIDs,
                destination: nil,
                riskLevel: .medium,
                confidence: candidate.confidence,
                isSelected: candidate.confidence >= 0.90,
                excludedFileIDs: []
            )
        case .review:
            return CleanupAction(
                id: UUID(),
                type: .move,
                title: "Review These Files",
                explanation: candidate.reason,
                fileIDs: existingFileIDs,
                destination: nil,
                riskLevel: .medium,
                confidence: candidate.confidence,
                isSelected: false,
                excludedFileIDs: []
            )
        }
    }

    private func makeSummary(actions: [CleanupAction]) -> String {
        if actions.isEmpty {
            return "No cleanup actions were identified."
        }

        return "\(actions.count) cleanup actions were identified."
    }
}
