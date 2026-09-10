import Foundation

struct FindRelatedFilesTool {
    static let maxRelatedResults = 8
    static let minimumScore = 0.5

    private struct Match {
        let entry: GlobalFileCatalog.Entry
        let score: Double
        let reasons: [String]
    }

    func execute(sourceID: UUID, candidateID: UUID, environment: AgentEnvironment) throws -> AgentObservation {
        guard let source = environment.catalog.entries.first(where: { $0.file.id == sourceID }) else {
            throw AgentToolError.unavailableFileMetadata
        }
        var matches = 0
        var best: [Match] = []
        for entry in environment.catalog.entries where entry.file.id != sourceID {
            try Task.checkCancellation()
            guard let match = score(source, entry) else { continue }
            matches += 1
            best.append(match)
            best.sort {
                if $0.score != $1.score { return $0.score > $1.score }
                let left = $0.entry.file.url.standardizedFileURL.path
                let right = $1.entry.file.url.standardizedFileURL.path
                return left == right ? $0.entry.file.id.uuidString < $1.entry.file.id.uuidString : left < right
            }
            if best.count > Self.maxRelatedResults { best.removeLast() }
        }
        let localIDs = Set(environment.evidenceByCandidate[candidateID]?.files.map(\.fileID) ?? [])
        let results = best.map { match in
            """
            \(match.entry.reference):
            name=\(PromptText.quoted(match.entry.file.name, bytes: 128))
            scope=\(localIDs.contains(match.entry.file.id) ? "currentCandidate" : "elsewhereInFolder")
            score=\(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), match.score))
            reasons=\(match.reasons.joined(separator: "; "))
            """
        }.joined(separator: "\n\n")
        return AgentObservation(
            type: .discovery, candidateID: candidateID,
            content: """
            source=\(source.reference)
            name=\(PromptText.quoted(source.file.name, bytes: 128))
            matches=\(matches)
            returned=\(best.count)
            Retrieval candidates only. Scores are metadata similarity, not probabilities or proof of shared content, duplication, or semantic relationship. Inspect selected G references before drawing conclusions.

            \(results.isEmpty ? "No matches above the retrieval threshold." : results)
            """,
            globalReferences: [source.reference] + best.map { $0.entry.reference },
            pdfGlobalReferences: best.compactMap {
                InspectPDFContentTool.supports($0.entry.file) ? $0.entry.reference : nil
            },
            imageGlobalReferences: best.compactMap {
                InspectImageEvidenceTool.supports($0.entry.file) ? $0.entry.reference : nil
            }
        )
    }

    private func score(_ source: GlobalFileCatalog.Entry, _ other: GlobalFileCatalog.Entry) -> Match? {
        let a = source.file
        let b = other.file
        let union = source.filenameTokens.union(other.filenameTokens)
        let nameSimilarity = union.isEmpty ? 0
            : Double(source.filenameTokens.intersection(other.filenameTokens).count) / Double(union.count)
        let secondsApart = a.modifiedAt.flatMap { left in
            b.modifiedAt.map { abs(left.timeIntervalSince($0)) }
        }
        // Broad category, directory and size alone are too weak to warrant retrieval.
        guard nameSimilarity >= 0.25 || (secondsApart.map { $0 <= 3_600 } ?? false) else { return nil }
        var score = 0.0
        var reasons: [String] = []
        if !a.extensionName.isEmpty && a.extensionName.lowercased() == b.extensionName.lowercased() {
            score += 0.1
            reasons.append("same extension")
        }
        if a.fileType == b.fileType {
            score += 0.1
            reasons.append("same file type")
        }
        if nameSimilarity > 0 {
            score += 0.4 * nameSimilarity
            reasons.append("similar normalized filename pattern")
        }
        if let secondsApart, secondsApart <= 3_600 {
            score += 0.2 * (1 - secondsApart / 3_600)
            reasons.append("modified \(Int(secondsApart))s apart")
        }
        if a.size > 0 && b.size > 0 {
            let ratio = Double(min(a.size, b.size)) / Double(max(a.size, b.size))
            if ratio >= 0.8 {
                score += 0.1 * ratio
                reasons.append("similar size")
            }
        }
        if source.parent == other.parent {
            score += 0.1
            reasons.append("same parent directory")
        }
        guard score >= Self.minimumScore else { return nil }
        return Match(entry: other, score: min(score, 1), reasons: reasons)
    }
}
