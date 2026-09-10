import Foundation

struct AgentDecisionDecoder {
    func decode(_ response: String) throws -> AgentDecision {
        do {
            return try ModelJSONDecoder.decode(
                AgentDecision.self,
                from: response
            )
        } catch {
            print("======== AGENT RAW RESPONSE ========")
            print(response)
            throw AgentError.invalidResponse
        }
    }
}
