import Foundation

struct FileReferenceMap: Sendable {

    private let idByReference: [String: UUID]
    private let referenceByID: [UUID: String]

    init(fileIDs: [UUID]) {

        var idMap: [String: UUID] = [:]
        var referenceMap: [UUID: String] = [:]

        for (index, id) in fileIDs.enumerated() {

            let reference =
                "F\(index + 1)"

            idMap[reference] = id
            referenceMap[id] = reference
        }

        idByReference = idMap
        referenceByID = referenceMap
    }

    func fileID(
        for reference: String
    ) -> UUID? {

        idByReference[reference]
    }

    func reference(
        for fileID: UUID
    ) -> String? {

        referenceByID[fileID]
    }
}
