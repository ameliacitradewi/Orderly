import Foundation

struct PromptText: Sendable {
    static func quoted(_ text: String, bytes: Int) -> String {
        let bounded = String(decoding: text.utf8.prefix(bytes), as: UTF8.self)
        let data = try? JSONEncoder().encode(bounded)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}
