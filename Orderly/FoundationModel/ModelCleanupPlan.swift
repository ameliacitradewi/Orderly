import Foundation
import FoundationModels

@Generable
struct ModelCleanupPlan: Sendable {

    @Guide(
        description: "A concise one-sentence summary of the recommended cleanup."
    )
    let summary: String

    @Guide(
        description: "Cleanup recommendations based only on the supplied candidates."
    )
    let recommendations: [CleanupRecommendation]
}
