import Foundation

struct DocumentComparisonTool {
    private let comparator = DeterministicDocumentComparator()
    private let semanticAnalyzer: any DocumentSemanticAnalyzing

    init(semanticAnalyzer: any DocumentSemanticAnalyzing) {
        self.semanticAnalyzer = semanticAnalyzer
    }

    func execute(
        references: [String],
        candidateID: UUID,
        environment: AgentEnvironment,
        observations: [AgentObservation]
    ) async throws -> AgentObservation {
        guard references.count == 2,
              Set(references).count == 2 else {
            throw AgentToolError.wrongFileCount
        }

        let visible = environment.visibleGlobalReferences(
            candidateID: candidateID,
            observations: observations
        )
        guard references.allSatisfy(visible.contains) else {
            let hidden = references.first { !visible.contains($0) } ?? references[0]
            throw AgentToolError.unobservedGlobalReference(hidden)
        }

        let files = try references.map { reference -> FileMetadata in
            guard let file = environment.filesByGlobalReference[reference] else {
                throw AgentToolError.invalidFileReference(reference)
            }
            return file
        }

        let localIDs = Set(
            environment.evidenceByCandidate[candidateID]?.files.map(\.fileID) ?? []
        )
        guard files.contains(where: { localIDs.contains($0.id) }) else {
            throw AgentToolError.comparisonOutsideCandidate
        }

        let contentObservations = observations.filter {
            $0.candidateID == candidateID && $0.type == .content
        }
        func content(for reference: String) -> ContentObservation? {
            contentObservations.reversed().compactMap(\.contentObservation).first {
                $0.globalReference == reference
            }
        }

        guard let first = content(for: references[0]),
              let second = content(for: references[1]) else {
            throw DocumentComparisonError.missingContentEvidence
        }

        let deterministic = comparator.compare(first, second)
        let semantic = try await semanticAnalyzer.analyze(
            first: first,
            second: second,
            deterministic: deterministic
        )
        let structured = DocumentComparisonObservation(
            fileIDs: [first.fileID, second.fileID],
            globalReferences: references,
            deterministic: deterministic,
            semantic: semantic
        )

        print("======== DOCUMENT COMPARISON ========")
        print("Files:", references.joined(separator: " vs "))
        print("tokenOverlap=", Self.number(deterministic.tokenOverlap))
        print("shingleSimilarity=", Self.number(deterministic.shingleSimilarity))
        print("lengthDifference=", Self.number(deterministic.lengthDifference))
        print("comparedCharacters=", deterministic.comparedCharacterCount)
        print("======== QWEN SEMANTIC ASSESSMENT ========")
        print("relationship=", semantic.relationship.rawValue)
        print("confidence=", Self.number(semantic.confidence))
        print("summary=", semantic.summary)

        let content = """
        \(references[0]) vs \(references[1])
        tokenOverlap=\(Self.number(deterministic.tokenOverlap))
        shingleSimilarity=\(Self.number(deterministic.shingleSimilarity))
        lengthDifference=\(Self.number(deterministic.lengthDifference))
        comparedCharacters=\(deterministic.comparedCharacterCount)
        semanticRelationship=\(semantic.relationship.rawValue)
        semanticConfidence=\(Self.number(semantic.confidence))
        semanticSummary=\(PromptText.quoted(semantic.summary, bytes: 512))
        This is semantic evidence, not exact-duplicate verification. Revision and same-topic findings must remain subject to the cleanup allowlist and user approval.
        """

        return AgentObservation(
            type: .documentComparison,
            candidateID: candidateID,
            content: content,
            globalReferences: references,
            documentComparison: structured
        )
    }

    private static func number(_ value: Double) -> String {
        String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }
}
