import Foundation
import CryptoKit

actor DuplicateDetector {
    func findDuplicates(in files: [FileMetadata]) throws -> DuplicateScan {
        let bySize = Dictionary(grouping: files, by: \.size)
        var groups: [DuplicateGroup] = []
        var unreadableCount = 0
        for size in bySize.keys.sorted() {
            try Task.checkCancellation()
            let candidates = bySize[size] ?? []
            guard candidates.count > 1 else { continue }
            var byHash: [String: [FileMetadata]] = [:]
            for file in candidates {
                do {
                    let hash = try Self.digest(at: file.url, matching: file)
                    byHash[hash, default: []].append(file)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    unreadableCount += 1
                }
            }
            for hash in byHash.keys.sorted() {
                let matches = byHash[hash] ?? []
                guard matches.count > 1 else { continue }
                let ordered = matches.sorted(by: Self.newestFirst)
                // An unknown date prevents claiming which copy is newest.
                let keeper = ordered.allSatisfy { $0.modifiedAt != nil } ? ordered.first?.id : nil
                groups.append(DuplicateGroup(
                    id: UUID(), files: ordered.map(\.id), fileSize: size,
                    detectionMethod: .exactHash, sha256: hash, keeperID: keeper
                ))
            }
        }
        var groupByFile: [UUID: DuplicateGroup] = [:]
        for group in groups {
            for id in group.files { groupByFile[id] = group }
        }
        let tagged = files.map { file in
            var result = file
            if let group = groupByFile[file.id] {
                result.duplicateGroupID = group.id
                result.duplicateSHA256 = group.sha256
                result.duplicateKeeperID = group.keeperID
                result.duplicateCopyCount = group.files.count
            }
            return result
        }
        return DuplicateScan(files: tagged, groups: groups, unreadableCount: unreadableCount)
    }

    nonisolated static func newestFirst(_ left: FileMetadata, _ right: FileMetadata) -> Bool {
        let lhs = left.modifiedAt ?? .distantPast
        let rhs = right.modifiedAt ?? .distantPast
        if lhs != rhs { return lhs > rhs }
        // Stable tie-breaker, independent of scan order, names and regenerated UUIDs.
        return left.url.standardizedFileURL.path < right.url.standardizedFileURL.path
    }

    /// Stream the full byte sequence (including empty files), never a filename/PDF preview.
    nonisolated static func digest(at url: URL, matching file: FileMetadata) throws -> String {
        if file.isDirectory { return try packageDigest(at: url, matching: file) }
        let before = try FileSnapshot.read(at: url)
        guard before.size == file.size,
              file.modifiedAt == nil || before.modifiedAt == file.modifiedAt else {
            throw FileVerificationError.changed
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { break }
            hasher.update(data: data)
        }
        guard before == (try FileSnapshot.read(at: url)) else { throw FileVerificationError.changed }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private nonisolated static func packageDigest(at url: URL, matching file: FileMetadata) throws -> String {
        let before = try PackageContents.snapshot(at: url)
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        guard before.totalSize == file.size, modified == file.modifiedAt else { throw FileVerificationError.changed }
        var hasher = SHA256()
        hasher.update(data: Data("Orderly.document-package.v1\0".utf8))
        for entry in before.entries {
            let size = entry.snapshot?.size ?? 0
            let kind = entry.snapshot == nil ? "D" : "F"
            hasher.update(data: Data("\(kind):\(entry.path.utf8.count):\(entry.path):\(size):".utf8))
            guard entry.snapshot != nil else { continue }
            let handle = try FileHandle(forReadingFrom: url.appendingPathComponent(entry.path))
            defer { try? handle.close() }
            while true {
                try Task.checkCancellation()
                guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { break }
                hasher.update(data: data)
            }
        }
        let afterModified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        guard before == (try PackageContents.snapshot(at: url)), modified == afterModified else { throw FileVerificationError.changed }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

}

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
        return FileSnapshot(size: size.int64Value, modifiedAt: attributes[.modificationDate] as? Date,
                            fileNumber: inode.uint64Value, device: device.uint64Value)
    }
}

nonisolated enum FileVerificationError: LocalizedError {
    case changed, notRegularFile, keeperUnavailable
    var errorDescription: String? {
        switch self {
        case .changed: return "The file changed after scanning. Scan this folder again."
        case .notRegularFile: return "The item is no longer a regular file. Scan this folder again."
        case .keeperUnavailable: return "The newest duplicate copy could not be verified. No copy was deleted."
        }
    }
}
