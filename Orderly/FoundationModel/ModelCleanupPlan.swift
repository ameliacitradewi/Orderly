import Foundation

struct ModelCleanupPlan: Codable, Sendable {
    let summary: String
    let recommendations: [CleanupRecommendation]
}
