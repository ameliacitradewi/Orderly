import Foundation

enum AgentToolError: LocalizedError {
    case missingCandidate
    case unknownCandidate
    case invalidFileReference(String)
    case unavailableFileMetadata
    case wrongFileCount
    case notAToolAction
    case unobservedGlobalReference(String)
    case comparisonOutsideCandidate

    var errorDescription: String? {
        switch self {
        case .missingCandidate:
            return "The agent did not provide a candidate ID."
        case .unknownCandidate:
            return "The requested candidate does not exist."
        case .invalidFileReference(let reference):
            return "Unknown file reference: \(reference)."
        case .unavailableFileMetadata:
            return "The requested file metadata is unavailable."
        case .wrongFileCount:
            return "The tool received the wrong number of file references."
        case .notAToolAction:
            return "This agent decision does not require a tool."
        case .unobservedGlobalReference(let reference):
            return "Global reference \(reference) has not been observed in this investigation. Use inspectCandidate or findRelatedFiles first."
        case .comparisonOutsideCandidate:
            return "A global comparison must include at least one file from the current candidate."
        }
    }
}
