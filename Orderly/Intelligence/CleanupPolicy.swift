import Foundation

nonisolated struct CleanupPolicy: Sendable {
    static func isSafeArtifact(_ file: FileMetadata) -> Bool {
        file.fileType == .artifact && [".ds_store", "thumbs.db"].contains(file.name.lowercased())
    }

    static func isInstallerCandidate(_ file: FileMetadata) -> Bool {
        guard file.fileType == .application, !file.isDirectory else { return false }
        let ext = file.extensionName.lowercased()
        if ["deb", "rpm", "snap", "flatpak", "flatpakref", "appinstaller", "msu", "ipsw", "dmg", "pkg", "mpkg", "msi", "msp", "msix", "msixbundle", "appx", "appxbundle",
            "apk", "apks", "aab", "ipa", "xap", "xpi", "vbox-extpack", "cia"].contains(ext) { return true }
        return ext == "exe" && file.name.lowercased().range(
            of: "(^|[ ._-])(setup|install|installer)([ ._0-9-]|$)", options: .regularExpression
        ) != nil
    }

    /// Returns the actions an agent may propose. This method constrains a
    /// decision; it never chooses one on the agent's behalf.
    static func allowedDispositions(
        for file: FileMetadata,
        root: URL
    ) -> [FileDisposition] {
        if let keeper = file.duplicateKeeperID,
           file.id == keeper {
            return [.keep]
        }

        if file.duplicateGroupID != nil {
            guard file.duplicateKeeperID != nil else {
                return [.keep, .review]
            }
            return [.keep, .trash, .review]
        }

        if isSafeArtifact(file) {
            return [.keep, .trash, .review]
        }

        if isInstallerCandidate(file) {
            return [.keep, .move, .trash, .review]
        }

        return [.keep, .move, .review]
    }

    static func destination(for file: FileMetadata, root: URL) -> URL {
        let folder = root.standardizedFileURL
        if folder.lastPathComponent == file.fileType.tagName { return folder }
        return folder.appendingPathComponent(file.fileType.tagName, isDirectory: true).standardizedFileURL
    }

    static func explanation(for file: FileMetadata, files: FileLookup) -> String {
        if file.duplicateGroupID != nil {
            guard let keeperID = file.duplicateKeeperID, let keeper = files.file(withID: keeperID) else {
                return "SHA256 matches, but a Last Modified date is missing. Keep all copies for review."
            }
            let date = keeper.modifiedAt?.formatted(.iso8601) ?? "unknown"
            return "SHA256 confirms \(file.duplicateCopyCount) identical copies. Keep \(keeper.name) "
                + "(\(keeper.url.path)), Last Modified: \(date). Delete the remaining copies to macOS Trash. "
                + "Equal dates use alphabetical path order."
        }
        if isSafeArtifact(file) {
            return "These Finder or thumbnail cache files can be regenerated. Delete moves them to macOS Trash."
        }
        if isInstallerCandidate(file) {
            return "Delete the installer only if installation is complete and you no longer need it for reinstalling offline. Files go to macOS Trash."
        }
        return "Organize these files into the \(file.fileType.tagName) folder according to their tags."
    }
}
