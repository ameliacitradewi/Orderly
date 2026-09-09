import Foundation

enum AgentAction: String, Codable, Sendable, Hashable {
    case inspectCandidate
    case inspectFile
    case compareFiles
    case inspectPDFContent
    case inspectImageContent
    case findRelatedFiles
    case inspectGlobalFile
    case inspectGlobalPDFContent
    case inspectGlobalImageContent
    case compareGlobalFiles
    case compareDocumentContent
    case compareImageContent
    case finishCandidate
}

struct AgentDecision: Codable, Sendable {
    let action: AgentAction
    let candidateID: UUID?
    let fileReferences: [String]
    let reason: String
    let finding: AgentFinding?

    init(
        action: AgentAction,
        candidateID: UUID?,
        fileReferences: [String],
        reason: String,
        finding: AgentFinding? = nil
    ) {
        self.action = action
        self.candidateID = candidateID
        self.fileReferences = fileReferences
        self.reason = reason
        self.finding = finding
    }
}
