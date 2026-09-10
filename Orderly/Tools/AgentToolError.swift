import Foundation

enum AgentToolError: LocalizedError {
    case missingCandidate
    case unknownCandidate
    case invalidFileReference(String)
    case unobservedGlobalReference(String)
    case wrongFileCount
    case comparisonOutsideCandidate
    case unavailableFileMetadata
    case semanticAnalyzerUnavailable
    case notAToolAction

    var errorDescription: String? {
        switch self {
        case .missingCandidate:
            return "The tool request is missing a candidate ID."
        case .unknownCandidate:
            return "The requested candidate is not available."
        case .invalidFileReference(let reference):
            return "Unknown file reference: \(reference)."
        case .unobservedGlobalReference(let reference):
            return "Global file reference \(reference) has not been exposed by a trusted observation for this candidate."
        case .wrongFileCount:
            return "The tool request contains the wrong number of file references."
        case .comparisonOutsideCandidate:
            return "A cross-file comparison must include at least one file from the current candidate."
        case .unavailableFileMetadata:
            return "Metadata for the requested file is unavailable in the scan snapshot."
        case .semanticAnalyzerUnavailable:
            return "Semantic document comparison is not configured for this agent."
        case .notAToolAction:
            return "The requested action is not a synchronous read-only tool action."
        }
    }
}
