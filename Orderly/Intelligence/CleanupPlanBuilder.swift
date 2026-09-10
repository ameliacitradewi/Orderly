import Foundation

final class CleanupPlanBuilder {
    func buildPlan(folder: URL, candidates: [AnalysisCandidate], modelPlan: ModelCleanupPlan,
                   files: [FileMetadata]) -> CleanupPlan {
        let byCandidate = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let lookup = FileLookup(files: files)
        var proposed: [UUID: FileDisposition] = [:]
        for recommendation in modelPlan.recommendations {
            guard let id = UUID(uuidString: recommendation.candidateID), let candidate = byCandidate[id] else { continue }
            let references = FileReferenceMap(fileIDs: candidate.fileIDs)
            for decision in recommendation.fileDecisions {
                guard let id = references.fileID(for: decision.fileReference), proposed[id] == nil else { continue }
                proposed[id] = decision.disposition
            }
        }

        // Agent proposals are consumed as-is. Missing proposals default to review,
        // and policy is reapplied only as a capability check.
        var groups: [String: [FileMetadata]] = [:]
        for file in files {
            let decision = proposed[file.id] ?? .review
            let allowed = CleanupPolicy.allowedDispositions(
                for: file,
                root: folder
            )
            guard allowed.contains(decision) else { continue }

            switch decision {
            case .trash:
                let key = file.duplicateGroupID.map { "duplicate:\($0.uuidString)" }
                    ?? (CleanupPolicy.isSafeArtifact(file) ? "artifacts" : "installers")
                groups["delete:" + key, default: []].append(file)
            case .move:
                let destination = CleanupPolicy.destination(
                    for: file,
                    root: folder
                )
                guard file.url.deletingLastPathComponent().standardizedFileURL
                    != destination else { continue }
                groups["organize:" + file.fileType.tagName, default: []].append(file)
            case .keep, .review: break
            }
        }
        let actions = groups.keys.sorted().compactMap { key -> CleanupAction? in
            guard let group = groups[key], let first = group.first else { return nil }
            let deleting = key.hasPrefix("delete:")
            let title: String
            if !deleting { title = "Organize \(first.fileType.tagName)" }
            else if first.duplicateGroupID != nil { title = "Delete \(group.count) duplicate \(group.count == 1 ? "copy" : "copies")" }
            else if CleanupPolicy.isSafeArtifact(first) { title = "Delete regenerable artifacts" }
            else { title = "Delete installers you no longer need" }
            return CleanupAction(
                type: deleting ? .trash : .move, title: title,
                explanation: deleting ? CleanupPolicy.explanation(for: first, files: lookup)
                    : "Move these files into the \(first.fileType.tagName) folder.",
                fileIDs: group.map(\.id), destination: deleting ? nil : CleanupPolicy.destination(for: first, root: folder),
                riskLevel: deleting ? .high : .low,
                confidence: deleting && first.duplicateGroupID == nil && CleanupPolicy.isInstallerCandidate(first) ? 0.6 : 1,
                isSelected: false
            )
        }
        return CleanupPlan(id: UUID(), folder: folder, summary: modelPlan.summary,
                           actions: actions, createdAt: Date())
    }
}
