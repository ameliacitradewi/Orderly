import Foundation

struct FileReferenceMap {

    private let idByReference: [String: UUID]
    private let referenceByID: [UUID: String]

    init(fileIDs: [UUID]) {

        var idMap: [String: UUID] = [:]
        var referenceMap: [UUID: String] = [:]

        for (index, id) in fileIDs.enumerated() {

            let reference = "F\(index + 1)"

            idMap[reference] = id
            referenceMap[id] = reference
        }

        self.idByReference = idMap
        self.referenceByID = referenceMap
    }

    func fileID(
        for rawReference: String
    ) -> UUID? {

        guard let reference =
            Self.normalizedReference(
                rawReference
            )
        else {
            return nil
        }

        return idByReference[reference]
    }

    func reference(
        for fileID: UUID
    ) -> String? {

        referenceByID[fileID]
    }

    static func normalizedReference(
        _ rawValue: String
    ) -> String? {

        let value =
            rawValue
                .uppercased()
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        // Already canonical:
        // F1
        // F2
        if isCanonicalReference(value) {
            return value
        }

        // Accept harmless model formatting such as:
        //
        // FILE F1
        // FILE: F1
        // File F2
        // reference F1
        //
        // But still extract only a valid F<number> token.

        let separators =
            CharacterSet.alphanumerics
                .union(
                    CharacterSet(
                        charactersIn: "_"
                    )
                )
                .inverted

        let tokens =
            value.components(
                separatedBy: separators
            )
            .filter {
                !$0.isEmpty
            }

        let references =
            tokens.filter {
                isCanonicalReference($0)
            }

        // Require exactly one valid reference.
        // "F1 F2" remains invalid.
        guard references.count == 1 else {
            return nil
        }

        return references[0]
    }

    private static func isCanonicalReference(
        _ value: String
    ) -> Bool {

        guard value.first == "F" else {
            return false
        }

        let numberPart =
            value.dropFirst()

        guard !numberPart.isEmpty else {
            return false
        }

        return numberPart.allSatisfy {
            $0.isNumber
        }
    }
}
