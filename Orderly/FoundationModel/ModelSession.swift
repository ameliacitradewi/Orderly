import Foundation
import FoundationModels

@MainActor
final class OrderlyModelSession {

    private let model = SystemLanguageModel.default

    func analyze(
        analysis: AnalysisResult
    ) async throws -> ModelCleanupPlan {

        try validateModelAvailability()

        let session = LanguageModelSession(
            instructions: """
            You are Orderly, a conservative macOS file organization planner.

            You receive cleanup candidates that were already produced
            by deterministic application logic.

            Your task is to recommend whether each candidate should be
            organized, archived, reviewed, reviewed as duplicates,
            reviewed for Trash, or skipped.

            Rules:
            - Use only Candidate IDs provided in the prompt.
            - Never invent Candidate IDs.
            - Never invent files.
            - Never create file UUIDs.
            - Never create absolute filesystem paths.
            - Never execute filesystem operations.
            - Never permanently delete files.
            - Treat duplicate candidates as review-only.
            - Prefer review or skip when evidence is weak.
            - Base explanations only on the supplied candidate metadata.
            - Suggested destinations must be folder names, not paths.
            """
        )

        let prompt = buildPrompt(
            analysis: analysis
        )

        let response = try await session.respond(
            to: prompt,
            generating: ModelCleanupPlan.self
        )

        return response.content
    }

    private func buildPrompt(
        analysis: AnalysisResult
    ) -> String {

        let typeSummary = analysis.fileTypes
            .map {
                "\($0.type.rawValue): \($0.count)"
            }
            .joined(separator: ", ")

        let candidateSummary = analysis.candidates
            .map { candidate in
                """
                Candidate ID: \(candidate.id.uuidString)
                Type: \(candidate.type.rawValue)
                File count: \(candidate.fileIDs.count)
                Confidence: \(String(format: "%.2f", candidate.confidence))
                Reason: \(candidate.reason)
                """
            }
            .joined(separator: "\n\n")

        return """
        Review these precomputed cleanup candidates.

        Folder:
        \(analysis.analyzedFolder.lastPathComponent)

        Total files:
        \(analysis.totalFiles)

        Total size:
        \(ByteCountFormatter.string(
            fromByteCount: analysis.totalSize,
            countStyle: .file
        ))

        File types:
        \(typeSummary)

        Exact duplicate groups:
        \(analysis.duplicateGroups.count)

        Candidates:
        \(candidateSummary.isEmpty
            ? "No cleanup candidates."
            : candidateSummary)

        Valid intent rules:

        grouping:
        organize, review, or skip

        archive:
        archive, review, or skip

        duplicate:
        reviewDuplicates or skip

        temporary:
        reviewForTrash, review, or skip

        redundant:
        reviewForTrash, review, or skip

        review:
        review or skip

        Return recommendations only for Candidate IDs supplied above.
        """
    }

    private func validateModelAvailability() throws {

        switch model.availability {

        case .available:
            return

        case .unavailable(let reason):
            throw OrderlyModelError.modelUnavailable(reason)
        }
    }
}

enum OrderlyModelError: LocalizedError {

    case modelUnavailable(
        SystemLanguageModel.Availability.UnavailableReason
    )

    var errorDescription: String? {

        switch self {

        case .modelUnavailable(let reason):

            switch reason {

            case .appleIntelligenceNotEnabled:
                return """
                Apple Intelligence is not enabled on this Mac.
                """

            case .deviceNotEligible:
                return """
                This Mac does not support Apple Intelligence.
                """

            case .modelNotReady:
                return """
                The on-device Foundation Model is not ready yet.
                """

            @unknown default:
                return """
                The on-device Foundation Model is currently unavailable.
                """
            }
        }
    }
}
