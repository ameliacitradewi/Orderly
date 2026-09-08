import Foundation

enum ObservationType: String, Codable, Sendable {
    case candidate
    case metadata
    case comparison
    case content
    case error
}

struct AgentObservation: Codable, Sendable {
    let id: UUID
    let type: ObservationType
    let candidateID: UUID
    let content: String
    let contentObservation: ContentObservation?

    init(
        id: UUID = UUID(),
        type: ObservationType,
        candidateID: UUID,
        content: String,
        contentObservation: ContentObservation? = nil
    ) {
        self.id = id
        self.type = type
        self.candidateID = candidateID
        self.content = content
        self.contentObservation = contentObservation
    }
}
