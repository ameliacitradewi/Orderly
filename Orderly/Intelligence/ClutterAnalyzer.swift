import Foundation

final class ClutterAnalyzer {
    static let batchSize = 4

    func analyze(files: [FileMetadata], duplicateGroups: [DuplicateGroup]) -> [AnalysisCandidate] {
        let lookup = FileLookup(files: files)
        var candidates: [AnalysisCandidate] = []
        // Retention is stored on every member. Batches need not include the keeper,
        // and a group of hundreds of copies never becomes one oversized prompt.
        for group in duplicateGroups {
            appendBatches(lookup.files(withIDs: group.files), type: .duplicate,
                          reason: "SHA256 Duplicate", to: &candidates)
        }
        for tag in FileType.allCases {
            let unique = files.filter { $0.duplicateGroupID == nil && $0.fileType == tag }
                .sorted { $0.url.path < $1.url.path }
            appendBatches(unique, type: tag == .artifact ? .artifact : .grouping,
                          reason: "Organize or delete \(tag.tagName).", to: &candidates)
        }
        return candidates
    }

    private func appendBatches(_ files: [FileMetadata], type: CandidateType, reason: String,
                               to candidates: inout [AnalysisCandidate]) {
        for start in stride(from: 0, to: files.count, by: Self.batchSize) {
            let batch = files[start..<min(start + Self.batchSize, files.count)]
            candidates.append(AnalysisCandidate(id: UUID(), type: type, fileIDs: batch.map(\.id),
                                                confidence: 1, reason: reason))
        }
    }
}
