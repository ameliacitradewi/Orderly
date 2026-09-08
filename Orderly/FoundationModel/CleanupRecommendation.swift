import Foundation

enum FileDisposition: String, Codable, Sendable, Hashable {
    case keep
    case trash
    case move
    case review
}

struct ModelFileDecision: Codable, Sendable {
    let fileReference: String
    let disposition: FileDisposition
    let reason: String
}

struct CleanupRecommendation: Codable, Sendable {
    let candidateID: String
    let title: String
    let explanation: String
    let fileDecisions: [ModelFileDecision]
    let destinationFolderName: String
    let confidence: Double
}
