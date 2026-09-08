import Foundation

enum AgentToolError: LocalizedError {
    case missingCandidate
    case unknownCandidate
    case invalidFileReference(String)
    case unavailableFileMetadata
    case wrongFileCount
    case notAToolAction

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
        }
    }
}
