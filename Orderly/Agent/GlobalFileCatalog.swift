import Foundation

/// References are stable for one scan snapshot, including when its input order changes.
/// A new scan may assign different references; G references are never filesystem paths.
struct GlobalFileCatalog: Sendable {
    let filesByGlobalReference: [String: FileMetadata]
    let globalReferenceByFileID: [UUID: String]
    let entries: [Entry]

    struct Entry: Sendable {
        let reference: String
        let file: FileMetadata
        let filenameTokens: Set<String>
        let parent: String
    }

    init(files: [FileMetadata]) {
        let sorted = files.sorted {
            let left = $0.url.standardizedFileURL.path
            let right = $1.url.standardizedFileURL.path
            return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
        }
        var entries: [Entry] = []
        var filesByReference: [String: FileMetadata] = [:]
        var referencesByID: [UUID: String] = [:]
        for file in sorted where referencesByID[file.id] == nil {
            let reference = "G\(entries.count + 1)"
            filesByReference[reference] = file
            referencesByID[file.id] = reference
            let stem = (file.name as NSString).deletingPathExtension
                .folding(options: [.caseInsensitive, .diacriticInsensitive],
                         locale: Locale(identifier: "en_US_POSIX"))
            // Dates, counters and separators do not hide a shared filename pattern.
            let tokens = Set(stem.split { !$0.isLetter }.map(String.init))
            entries.append(Entry(reference: reference, file: file,
                                 filenameTokens: tokens,
                                 parent: file.url.deletingLastPathComponent().standardizedFileURL.path))
        }
        self.entries = entries
        self.filesByGlobalReference = filesByReference
        self.globalReferenceByFileID = referencesByID
    }

    func relativePath(for file: FileMetadata, root: URL) -> String {
        let components = file.url.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents
        guard components.starts(with: rootComponents) else { return file.name }
        return components.dropFirst(rootComponents.count).joined(separator: "/")
    }
}
