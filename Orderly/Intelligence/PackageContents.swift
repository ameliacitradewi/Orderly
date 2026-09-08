import Foundation

/// Legacy Pages/Numbers/Keynote/RTFD packages are indivisible documents.
/// Include relative paths and entry boundaries in their SHA256 stream so different
/// package structures cannot compare equal merely by concatenating their bytes.
nonisolated struct PackageContents: Sendable, Equatable {
    static let supportedExtensions: Set<String> = ["pages", "page", "numbers", "key", "keynote", "rtfd"]

    nonisolated struct Entry: Sendable, Equatable {
        let path: String
        let snapshot: FileSnapshot? // Nil is an empty or nonempty directory entry.
    }
    let entries: [Entry]
    var totalSize: Int64 { entries.reduce(0) { $0 + ($1.snapshot?.size ?? 0) } }

    static func snapshot(at root: URL) throws -> PackageContents {
        let fm = FileManager.default
        let rootAttributes = try fm.attributesOfItem(atPath: root.path)
        guard rootAttributes[.type] as? FileAttributeType == .typeDirectory,
              supportedExtensions.contains(root.pathExtension.lowercased()) else {
            throw FileVerificationError.notRegularFile
        }
        var enumerationFailed = false
        guard let enumerator = fm.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [], errorHandler: { _, _ in enumerationFailed = true; return false }
        ) else { throw FileVerificationError.notRegularFile }
        var entries: [Entry] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw FileVerificationError.notRegularFile }
            let relative = url.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
            entries.append(Entry(path: relative, snapshot: values.isDirectory == true ? nil : try FileSnapshot.read(at: url)))
        }
        guard !enumerationFailed else { throw FileVerificationError.notRegularFile }
        return PackageContents(entries: entries.sorted { $0.path < $1.path })
    }
}
