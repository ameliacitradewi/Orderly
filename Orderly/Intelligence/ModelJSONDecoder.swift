import Foundation

enum ModelJSONDecoder {
    static func decode<T: Decodable>(
        _ type: T.Type,
        from rawOutput: String,
        using decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let value = try? decoder.decode(type, from: data) {
            return value
        }

        for object in objects(in: rawOutput) {
            guard let data = object.data(using: .utf8) else { continue }
            if let value = try? decoder.decode(type, from: data) {
                return value
            }
        }

        throw ModelJSONDecodingError.noDecodableObject
    }

    private static func objects(in text: String) -> [String] {
        var objects: [String] = []
        var objectStart: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                if depth == 0 { objectStart = index }
                depth += 1
            } else if character == "}", depth > 0 {
                depth -= 1
                if depth == 0, let start = objectStart {
                    objects.append(String(text[start...index]))
                    objectStart = nil
                }
            }

            index = text.index(after: index)
        }

        return objects
    }
}

enum ModelJSONDecodingError: LocalizedError {
    case noDecodableObject

    var errorDescription: String? {
        "The model response did not contain a valid JSON object."
    }
}
