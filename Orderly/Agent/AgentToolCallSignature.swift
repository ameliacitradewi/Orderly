import Foundation

struct AgentToolCallSignature: Hashable, Sendable {
    let action: AgentAction
    let candidateID: UUID
    let fileReferences: [String]

    init(
        action: AgentAction,
        candidateID: UUID,
        fileReferences: [String]
    ) {
        self.action = action
        self.candidateID = candidateID
        self.fileReferences = fileReferences.sorted()
    }
}
