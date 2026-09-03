import Foundation

struct FileLookup {

    private let filesByID: [UUID: FileMetadata]

    init(files: [FileMetadata]) {
        self.filesByID = Dictionary(
            uniqueKeysWithValues: files.map { file in
                (file.id, file)
            }
        )
    }

    func file(withID id: UUID) -> FileMetadata? {
        filesByID[id]
    }

    func files(withIDs ids: [UUID]) -> [FileMetadata] {
        ids.compactMap { filesByID[$0] }
    }
}
