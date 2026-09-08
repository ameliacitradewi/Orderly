import Foundation
import FoundationModels

@Generable
nonisolated enum FileDisposition: String, Sendable {
    case keep
    case trash
    case move
    case review
}

@Generable
nonisolated struct ModelFileDecision: Sendable {

    @Guide(
        description: "File reference copied exactly from the supplied candidate, such as F1 or F2."
    )
    let fileReference: String

    let disposition: FileDisposition

    @Guide(
        description: "Brief reasoning for why this specific file should be kept, moved to Trash, moved to a folder, or reviewed."
    )
    let reason: String
}

@Generable
nonisolated struct CleanupRecommendation: Sendable {

    @Guide(
        description: "Candidate ID copied exactly from the supplied candidate."
    )
    let candidateID: String

    @Guide(
        description: "Short human-readable title describing the recommendation."
    )
    let title: String

    @Guide(
        description: "Explain the overall reasoning using only the supplied evidence."
    )
    let explanation: String

    @Guide(
        description: "A decision for every supplied file reference in this candidate."
    )
    let fileDecisions: [ModelFileDecision]

    @Guide(
        description: "Suggested folder name when one or more files should be moved. Use an empty string otherwise."
    )
    let destinationFolderName: String

    @Guide(
        description: "Confidence in the recommendation.",
        .range(0.0...1.0)
    )
    let confidence: Double
}
