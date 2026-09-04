import Foundation
import FoundationModels

@Generable
enum RecommendationIntent: String, Sendable {
    case organize
    case archive
    case review
    case reviewDuplicates
    case reviewForTrash
    case skip
}

@Generable
struct CleanupRecommendation: Sendable {

    @Guide(
        description: "Candidate ID copied exactly from the provided candidates."
    )
    let candidateID: String

    let intent: RecommendationIntent

    @Guide(
        description: "A short action title for the user."
    )
    let title: String

    @Guide(
        description: "A short explanation based only on the provided candidate metadata."
    )
    let explanation: String

    @Guide(
        description: "A folder name only. Use an empty string when no destination is needed."
    )
    let destinationFolderName: String

    @Guide(
        description: "Confidence in this recommendation.",
        .range(0.0...1.0)
    )
    let confidence: Double
}
