import Foundation

enum AgentError: LocalizedError {
    case invalidResponse
    case wrongCandidate
    case maximumIterationsReached
    case finishWithoutFinding
    case invalidConfidence

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Qwen returned an invalid agent decision."
        case .wrongCandidate:
            return "The agent attempted to act on another candidate."
        case .maximumIterationsReached:
            return "The agent reached the maximum investigation steps."
        case .finishWithoutFinding:
            return "The agent finished without producing a finding."
        case .invalidConfidence:
            return "The agent returned an invalid confidence value."
        }
    }
}
