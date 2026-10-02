import Foundation

nonisolated struct FileSnapshot: Equatable, Sendable {
    let size: Int64
    let modifiedAt: Date?
    let fileNumber: UInt64
    let device: UInt64

    static func read(at url: URL) throws -> FileSnapshot {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let device = attributes[.systemNumber] as? NSNumber else {
            throw FileVerificationError.notRegularFile
        }

        return FileSnapshot(
            size: size.int64Value,
            modifiedAt: attributes[.modificationDate] as? Date,
            fileNumber: inode.uint64Value,
            device: device.uint64Value
        )
    }
}

nonisolated enum FileVerificationError: LocalizedError {
    case changed
    case notRegularFile
    case keeperUnavailable

    var errorDescription: String? {
        switch self {
        case .changed:
            return "The file changed after scanning. Scan this folder again."
        case .notRegularFile:
            return "The item is no longer a regular file. Scan this folder again."
        case .keeperUnavailable:
            return "The PCC-selected duplicate keeper could not be verified. No copy was deleted."
        }
    }
}
