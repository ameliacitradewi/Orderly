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

        // Resolve EVERY scanned file, even if a model response was malformed or incomplete.
        // Keep the global duplicate keeper protected from artifact/installer recommendations.
        var groups: [String: [FileMetadata]] = [:]
        for file in files {
            let decision = CleanupPolicy.resolve(proposed[file.id], for: file, root: folder)
            switch decision {
            case .trash:
                let key = file.duplicateGroupID.map { "duplicate:\($0.uuidString)" }
                    ?? (CleanupPolicy.isSafeArtifact(file) ? "artifacts" : "installers")
                groups["delete:" + key, default: []].append(file)
            case .move:
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
