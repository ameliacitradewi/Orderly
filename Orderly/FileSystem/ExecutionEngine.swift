import Foundation

actor ExecutionEngine {

    private let fileManager =
        FileManager.default

    func execute(
        plan: ExecutionPlan,
        files: [FileMetadata],
        rootFolder: URL,
        onProgress:
            @escaping @Sendable (
                ExecutionProgress
            ) async -> Void
    ) async throws -> ExecutionResult {

        let startedAt = Date()

        let root =
            rootFolder
                .standardizedFileURL

        guard root
            .startAccessingSecurityScopedResource()
        else {
            throw ExecutionEngineError
                .cannotAccessFolder
        }

        defer {
            root.stopAccessingSecurityScopedResource()
        }

        let lookup =
            FileLookup(files: files)

        try preflight(
            plan: plan,
            lookup: lookup,
            rootFolder: root
        )

        var records: [ExecutionRecord] = []

        for (
            index,
            action
        ) in plan.selectedActions.enumerated() {

            let actionRecords = execute(
                action: action,
                lookup: lookup,
                rootFolder: root
            )

            records.append(
                contentsOf: actionRecords
            )

            let progress = ExecutionProgress(
                completedActions: index + 1,
                totalActions: plan.selectedActions.count,
                currentMessage: progressMessage(
                    for: action
                )
            )

            await onProgress(
                progress
            )
        }

        return ExecutionResult(
            planID: plan.id,
            records: records,
            startedAt: startedAt,
            finishedAt: Date()
        )
    }

    // MARK: - Preflight

    private func preflight(
        plan: ExecutionPlan,
        lookup: FileLookup,
        rootFolder: URL
    ) throws {

        guard !plan.selectedActions.isEmpty else {
            throw ExecutionEngineError
                .emptyPlan
        }

        var claimedFileIDs = Set<UUID>()

        for action in plan.selectedActions {

            switch action.type {

            case .trash,
                 .move:

                guard !action.fileIDs.isEmpty else {
                    throw ExecutionEngineError
                        .emptyAction
                }

            case .createFolder:
                break

            case .rename:
                throw ExecutionEngineError
                    .unsupportedAction(
                        .rename
                    )
            }

            for fileID in action.fileIDs {

                guard let file = lookup.file(
                    withID: fileID
                ) else {
                    throw ExecutionEngineError
                        .unknownFile(fileID)
                }

                guard isInside(
                    file.url,
                    root: rootFolder
                ) else {
                    throw ExecutionEngineError
                        .sourceOutsideFolder(
                            file.url
                        )
                }

                if action.type == .trash {
                    guard CleanupPolicy.allowedDispositions(for: file, root: rootFolder).contains(.trash) else {
                        throw ExecutionEngineError.invalidCleanupPolicy
                    }
                } else if action.type == .move {
                    let destination = CleanupPolicy.destination(
                        for: file,
                        root: rootFolder
                    )
                    guard CleanupPolicy.allowedDispositions(for: file, root: rootFolder).contains(.move),
                          action.destination?.standardizedFileURL == destination,
                          file.url.deletingLastPathComponent().standardizedFileURL != destination else {
                        throw ExecutionEngineError.invalidCleanupPolicy
                    }
                }

                guard !claimedFileIDs.contains(
                    fileID
                ) else {
                    throw ExecutionEngineError
                        .fileUsedByMultipleActions(
                            fileID
                        )
                }

                claimedFileIDs.insert(
                    fileID
                )
            }

            if action.type == .move
                || action.type == .createFolder {

                guard let destination =
                    action.destination
                else {
                    throw ExecutionEngineError
                        .missingDestination
                }

                guard isInside(
                    destination,
                    root: rootFolder
                ) else {
                    throw ExecutionEngineError
                        .destinationOutsideFolder(
                            destination
                        )
                }
            }
        }
    }

    // MARK: - Action Execution

    private func execute(
        action: ExecutionAction,
        lookup: FileLookup,
        rootFolder: URL
    ) -> [ExecutionRecord] {

        switch action.type {

        case .trash:

            return action.fileIDs.map {
                executeTrash(
                    fileID: $0,
                    action: action,
                    lookup: lookup,
                    rootFolder: rootFolder
                )
            }

        case .move:

            return action.fileIDs.map {
                executeMove(
                    fileID: $0,
                    action: action,
                    lookup: lookup,
                    rootFolder: rootFolder
                )
            }

        case .createFolder:

            return [
                executeCreateFolder(
                    action: action,
                    rootFolder: rootFolder
                )
            ]

        case .rename:
            return []
        }
    }

    // MARK: - Trash

    private func executeTrash(
        fileID: UUID,
        action: ExecutionAction,
        lookup: FileLookup,
        rootFolder: URL
    ) -> ExecutionRecord {

        guard let file = lookup.file(
            withID: fileID
        ) else {
            return failureRecord(
                action: action,
                fileID: fileID,
                sourceURL: nil,
                fileSize: 0,
                message: "File metadata could not be resolved."
            )
        }

        let source =
            file.url.standardizedFileURL

        guard fileManager.fileExists(
            atPath: source.path
        ) else {
            return failureRecord(
                action: action,
                fileID: fileID,
                sourceURL: source,
                fileSize: file.size,
                message: "The file no longer exists."
            )
        }

        guard isInside(
            source,
            root: rootFolder
        ) else {
            return failureRecord(
                action: action,
                fileID: fileID,
                sourceURL: source,
                fileSize: file.size,
                message: "The file is outside the authorized folder."
            )
        }

        do {

            try DeletionVerifier.verify(file: file, lookup: lookup, root: rootFolder)
            var resultingURL: NSURL?

            try fileManager.trashItem(
                at: source,
                resultingItemURL: &resultingURL
            )

            return ExecutionRecord(
                id: UUID(),
                actionID: action.id,
                fileID: fileID,
                operation: .trash,
                sourceURL: source,
                resultingURL: resultingURL as URL?,
                fileSize: file.size,
                status: .succeeded,
                message: "Moved \(file.name) to Trash."
            )

        } catch {

            return failureRecord(
                action: action,
                fileID: fileID,
                sourceURL: source,
                fileSize: file.size,
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Move

    private func executeMove(
        fileID: UUID,
        action: ExecutionAction,
        lookup: FileLookup,
        rootFolder: URL
    ) -> ExecutionRecord {

        guard let file = lookup.file(
            withID: fileID
        ) else {
            return failureRecord(
                action: action,
                fileID: fileID,
                sourceURL: nil,
                fileSize: 0,
                message: "File metadata could not be resolved."
            )
        }

        guard let destinationFolder =
            action.destination?
                .standardizedFileURL
        else {
            return failureRecord(
                action: action,
                fileID: fileID,
                sourceURL: file.url,
                fileSize: file.size,
                message: "No destination was supplied."
            )
        }

        let source =
            file.url.standardizedFileURL

        guard isInside(
            source,
            root: rootFolder
        ),
        isInside(
            destinationFolder,
            root: rootFolder
        ) else {
            return failureRecord(
                action: action,
                fileID: fileID,
                sourceURL: source,
                fileSize: file.size,
                message: "Move would leave the authorized folder."
            )
        }

        do {

            if !fileManager.fileExists(
                atPath: destinationFolder.path
            ) {

                try fileManager.createDirectory(
                    at: destinationFolder,
                    withIntermediateDirectories: false
                )
            }

            let folderValues = try destinationFolder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard folderValues.isDirectory == true, folderValues.isSymbolicLink != true else {
                throw ExecutionEngineError.invalidCleanupPolicy
            }
            if file.isDirectory {
                let current = try PackageContents.snapshot(at: source)
                let attributes = try fileManager.attributesOfItem(atPath: source.path)
                guard current.totalSize == file.size, attributes[.modificationDate] as? Date == file.modifiedAt else {
                    throw FileVerificationError.changed
                }
            } else {
                let current = try FileSnapshot.read(at: source)
                guard current.size == file.size, current.modifiedAt == file.modifiedAt else {
                    throw FileVerificationError.changed
                }
            }
            let destination = availableDestination(in: destinationFolder, name: file.name)

            try fileManager.moveItem(
                at: source,
                to: destination
            )

            return ExecutionRecord(
                id: UUID(),
                actionID: action.id,
                fileID: fileID,
                operation: .move,
                sourceURL: source,
                resultingURL: destination,
                fileSize: file.size,
                status: .succeeded,
                message: "Moved \(file.name) to \(destinationFolder.lastPathComponent)."
            )

        } catch {

            return failureRecord(
                action: action,
                fileID: fileID,
                sourceURL: source,
                fileSize: file.size,
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Create Folder

    private func executeCreateFolder(
        action: ExecutionAction,
        rootFolder: URL
    ) -> ExecutionRecord {

        guard let destination =
            action.destination?
                .standardizedFileURL
        else {
            return failureRecord(
                action: action,
                fileID: nil,
                sourceURL: nil,
                fileSize: 0,
                message: "No folder destination was supplied."
            )
        }

        guard isInside(
            destination,
            root: rootFolder
        ) else {
            return failureRecord(
                action: action,
                fileID: nil,
                sourceURL: nil,
                fileSize: 0,
                message: "Folder is outside the authorized directory."
            )
        }

        do {

            if !fileManager.fileExists(
                atPath: destination.path
            ) {

                try fileManager.createDirectory(
                    at: destination,
                    withIntermediateDirectories: false
                )
            }

            return ExecutionRecord(
                id: UUID(),
                actionID: action.id,
                fileID: nil,
                operation: .createFolder,
                sourceURL: nil,
                resultingURL: destination,
                fileSize: 0,
                status: .succeeded,
                message: "Created \(destination.lastPathComponent)."
            )

        } catch {

            return failureRecord(
                action: action,
                fileID: nil,
                sourceURL: nil,
                fileSize: 0,
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Helpers

    private func isInside(
        _ candidate: URL,
        root: URL
    ) -> Bool {

        candidate.standardizedFileURL.resolvingSymlinksInPath() == root.standardizedFileURL.resolvingSymlinksInPath()
            || DeletionVerifier.isInside(candidate, root: root)
    }

    private func availableDestination(in folder: URL, name: String) -> URL {
        var candidate = folder.appendingPathComponent(name)
        let original = URL(fileURLWithPath: name)
        let ext = original.pathExtension
        let stem = original.deletingPathExtension().lastPathComponent
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let nextName = "\(stem) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)")
            candidate = folder.appendingPathComponent(nextName)
            suffix += 1
        }
        return candidate
    }

    private func progressMessage(
        for action: ExecutionAction
    ) -> String {

        switch action.type {

        case .trash:
            return "Moving files to Trash..."

        case .move:
            return "Organizing files..."

        case .createFolder:
            return "Creating folder..."

        case .rename:
            return "Renaming..."
        }
    }

    private func failureRecord(
        action: ExecutionAction,
        fileID: UUID?,
        sourceURL: URL?,
        fileSize: Int64,
        message: String
    ) -> ExecutionRecord {

        ExecutionRecord(
            id: UUID(),
            actionID: action.id,
            fileID: fileID,
            operation: action.type,
            sourceURL: sourceURL,
            resultingURL: nil,
            fileSize: fileSize,
            status: .failed,
            message: message
        )
    }
}

nonisolated enum ExecutionEngineError: LocalizedError {

    case cannotAccessFolder
    case invalidCleanupPolicy

    case emptyPlan

    case emptyAction

    case unknownFile(UUID)

    case fileUsedByMultipleActions(UUID)

    case sourceOutsideFolder(URL)

    case destinationOutsideFolder(URL)

    case missingDestination

    case unsupportedAction(
        CleanupActionType
    )

    var errorDescription: String? {

        switch self {

        case .invalidCleanupPolicy:
            return "The action conflicts with the tag or duplicate-retention rules. Scan this folder again."

        case .cannotAccessFolder:
            return "Orderly could not obtain write access to this folder."

        case .emptyPlan:
            return "There are no approved actions to execute."

        case .emptyAction:
            return "An approved action does not contain any files."

        case .unknownFile:
            return "An approved action references a file that no longer exists in the cleanup session."

        case .fileUsedByMultipleActions:
            return "The same file is referenced by more than one approved action."

        case .sourceOutsideFolder:
            return "An action references a file outside the selected folder."

        case .destinationOutsideFolder:
            return "An action tries to move files outside the selected folder."

        case .missingDestination:
            return "An organize action has no destination folder."

        case .unsupportedAction(let type):
            return "\(type.rawValue) is not supported by the execution engine yet."
        }
    }
}
