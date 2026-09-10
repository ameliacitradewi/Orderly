import Foundation

actor ExecutionEngine {
    private let fileManager: FileManager
    private let requiresSecurityScopedAccess: Bool
    private let maxDestinationCollisionRetries = 16

    init(
        fileManager: FileManager = .default,
        requiresSecurityScopedAccess: Bool = true
    ) {
        self.fileManager = fileManager
        self.requiresSecurityScopedAccess = requiresSecurityScopedAccess
    }

    func execute(
        plan: ExecutionPlan,
        files: [FileMetadata],
        rootFolder: URL,
        onProgress: @escaping @Sendable (ExecutionProgress) async -> Void
    ) async throws -> ExecutionResult {
        let startedAt = Date()
        let root = rootFolder.standardizedFileURL

        let didStartSecurityScope: Bool
        if requiresSecurityScopedAccess {
            guard root.startAccessingSecurityScopedResource() else {
                throw ExecutionEngineError.cannotAccessFolder
            }
            didStartSecurityScope = true
        } else {
            didStartSecurityScope = false
        }

        defer {
            if didStartSecurityScope {
                root.stopAccessingSecurityScopedResource()
            }
        }

        let lookup = FileLookup(files: files)

        // Plan-shape / authority failures remain fatal. Filesystem drift is handled
        // per file immediately before mutation so one stale item cannot block safe work.
        try preflightPlan(
            plan: plan,
            lookup: lookup,
            rootFolder: root
        )

        var records: [ExecutionRecord] = []
        var completedActions = 0
        var wasCancelled = false

        executionLoop: for action in plan.selectedActions {
            do {
                try Task.checkCancellation()

                switch action.type {
                case .trash:
                    for fileID in action.fileIDs {
                        try Task.checkCancellation()
                        records.append(
                            try executeTrash(
                                fileID: fileID,
                                action: action,
                                lookup: lookup,
                                rootFolder: root
                            )
                        )
                    }

                case .move:
                    for fileID in action.fileIDs {
                        try Task.checkCancellation()
                        records.append(
                            try executeMove(
                                fileID: fileID,
                                action: action,
                                lookup: lookup,
                                rootFolder: root
                            )
                        )
                    }

                case .createFolder:
                    records.append(
                        try executeCreateFolder(
                            action: action,
                            rootFolder: root
                        )
                    )

                case .rename:
                    // Rejected during structural preflight.
                    break
                }
            } catch is CancellationError {
                wasCancelled = true
                break executionLoop
            }

            completedActions += 1
            await onProgress(
                ExecutionProgress(
                    completedActions: completedActions,
                    totalActions: plan.selectedActions.count,
                    currentMessage: progressMessage(for: action)
                )
            )
        }

        if Task.isCancelled {
            wasCancelled = true
        }

        if wasCancelled {
            await onProgress(
                ExecutionProgress(
                    completedActions: completedActions,
                    totalActions: plan.selectedActions.count,
                    currentMessage: "Execution cancelled safely. Remaining actions were not started."
                )
            )
        }

        return ExecutionResult(
            planID: plan.id,
            records: records,
            startedAt: startedAt,
            finishedAt: Date(),
            wasCancelled: wasCancelled
        )
    }

    // MARK: - Structural Preflight

    /// Validates only immutable plan authority and reference shape. Current filesystem
    /// state is intentionally revalidated per file immediately before each mutation.
    private func preflightPlan(
        plan: ExecutionPlan,
        lookup: FileLookup,
        rootFolder: URL
    ) throws {
        guard !plan.selectedActions.isEmpty else {
            throw ExecutionEngineError.emptyPlan
        }

        var claimedFileIDs = Set<UUID>()

        for action in plan.selectedActions {
            switch action.type {
            case .trash, .move:
                guard !action.fileIDs.isEmpty else {
                    throw ExecutionEngineError.emptyAction
                }
            case .createFolder:
                break
            case .rename:
                throw ExecutionEngineError.unsupportedAction(.rename)
            }

            for fileID in action.fileIDs {
                guard let file = lookup.file(withID: fileID) else {
                    throw ExecutionEngineError.unknownFile(fileID)
                }

                guard isInside(file.url, root: rootFolder) else {
                    throw ExecutionEngineError.sourceOutsideFolder(file.url)
                }

                if action.type == .trash {
                    guard CleanupPolicy.allowedDispositions(
                        for: file,
                        root: rootFolder
                    ).contains(.trash) else {
                        throw ExecutionEngineError.invalidCleanupPolicy
                    }
                } else if action.type == .move {
                    let destination = CleanupPolicy.destination(
                        for: file,
                        root: rootFolder
                    )
                    guard CleanupPolicy.allowedDispositions(
                        for: file,
                        root: rootFolder
                    ).contains(.move),
                    action.destination?.standardizedFileURL == destination,
                    file.url.deletingLastPathComponent().standardizedFileURL != destination else {
                        throw ExecutionEngineError.invalidCleanupPolicy
                    }
                }

                guard claimedFileIDs.insert(fileID).inserted else {
                    throw ExecutionEngineError.fileUsedByMultipleActions(fileID)
                }
            }

            if action.type == .move || action.type == .createFolder {
                guard let destination = action.destination else {
                    throw ExecutionEngineError.missingDestination
                }
                guard isInside(destination, root: rootFolder) else {
                    throw ExecutionEngineError.destinationOutsideFolder(destination)
                }
            }
        }
    }

    // MARK: - Trash

    private func executeTrash(
        fileID: UUID,
        action: ExecutionAction,
        lookup: FileLookup,
        rootFolder: URL
    ) throws -> ExecutionRecord {
        try Task.checkCancellation()

        guard let file = lookup.file(withID: fileID) else {
            return skippedRecord(
                action: action,
                fileID: fileID,
                sourceURL: nil,
                fileSize: 0,
                message: "Skipped because file metadata could not be resolved. Scan again before retrying."
            )
        }

        let source = file.url.standardizedFileURL
        guard fileManager.fileExists(atPath: source.path) else {
            return skippedRecord(
                action: action,
                fileID: fileID,
                sourceURL: source,
                fileSize: file.size,
                message: "Skipped \(file.name) because it no longer exists."
            )
        }

        guard isInside(source, root: rootFolder) else {
            return skippedRecord(
                action: action,
                fileID: fileID,
                sourceURL: source,
                fileSize: file.size,
                message: "Skipped \(file.name) because its current path is outside the authorized folder."
            )
        }

        // Exact duplicates are rehashed here, immediately before Trash. Non-duplicate
        // deletions are revalidated by size/mtime. Any verification uncertainty skips.
        do {
            try DeletionVerifier.verify(
                file: file,
                lookup: lookup,
                root: rootFolder
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return skippedRecord(
                action: action,
                fileID: fileID,
                sourceURL: source,
                fileSize: file.size,
                message: "Skipped \(file.name): \(error.localizedDescription)"
            )
        }

        try Task.checkCancellation()

        do {
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
    ) throws -> ExecutionRecord {
        try Task.checkCancellation()

        guard let file = lookup.file(withID: fileID) else {
            return skippedRecord(
                action: action,
                fileID: fileID,
                sourceURL: nil,
                fileSize: 0,
                message: "Skipped because file metadata could not be resolved. Scan again before retrying."
            )
        }

        guard let destinationFolder = action.destination?.standardizedFileURL else {
            return skippedRecord(
                action: action,
                fileID: fileID,
                sourceURL: file.url,
                fileSize: file.size,
                message: "Skipped \(file.name) because no approved destination is available."
            )
        }

        let source = file.url.standardizedFileURL
        guard fileManager.fileExists(atPath: source.path) else {
            return skippedRecord(
                action: action,
                fileID: fileID,
                sourceURL: source,
                fileSize: file.size,
                message: "Skipped \(file.name) because it no longer exists."
            )
        }

        guard isInside(source, root: rootFolder),
              isInside(destinationFolder, root: rootFolder) else {
            return skippedRecord(
                action: action,
                fileID: fileID,
                sourceURL: source,
                fileSize: file.size,
                message: "Skipped \(file.name) because the current source or destination is outside the authorized folder."
            )
        }

        if let reason = currentStateMismatch(
            for: file,
            source: source
        ) {
            return skippedRecord(
                action: action,
                fileID: fileID,
                sourceURL: source,
                fileSize: file.size,
                message: "Skipped \(file.name): \(reason)"
            )
        }

        do {
            if fileManager.fileExists(atPath: destinationFolder.path) {
                let values = try destinationFolder.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
                guard values.isDirectory == true,
                      values.isSymbolicLink != true else {
                    return skippedRecord(
                        action: action,
                        fileID: fileID,
                        sourceURL: source,
                        fileSize: file.size,
                        message: "Skipped \(file.name) because the approved destination is no longer a regular folder."
                    )
                }
            } else {
                try Task.checkCancellation()
                try fileManager.createDirectory(
                    at: destinationFolder,
                    withIntermediateDirectories: false
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return failureRecord(
                action: action,
                fileID: fileID,
                sourceURL: source,
                fileSize: file.size,
                message: "Could not prepare \(destinationFolder.lastPathComponent): \(error.localizedDescription)"
            )
        }

        // Revalidate a second time after destination preparation to narrow the TOCTOU
        // window before the actual filesystem mutation.
        if let reason = currentStateMismatch(
            for: file,
            source: source
        ) {
            return skippedRecord(
                action: action,
                fileID: fileID,
                sourceURL: source,
                fileSize: file.size,
                message: "Skipped \(file.name): \(reason)"
            )
        }

        try Task.checkCancellation()

        var collisionAttempts = 0
        while collisionAttempts < maxDestinationCollisionRetries {
            let destination = availableDestination(
                in: destinationFolder,
                name: file.name
            )

            do {
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
                if Self.isDestinationCollision(error) {
                    collisionAttempts += 1
                    continue
                }

                return failureRecord(
                    action: action,
                    fileID: fileID,
                    sourceURL: source,
                    fileSize: file.size,
                    message: error.localizedDescription
                )
            }
        }

        return failureRecord(
            action: action,
            fileID: fileID,
            sourceURL: source,
            fileSize: file.size,
            message: "Could not choose a collision-free destination for \(file.name)."
        )
    }

    // MARK: - Create Folder

    private func executeCreateFolder(
        action: ExecutionAction,
        rootFolder: URL
    ) throws -> ExecutionRecord {
        try Task.checkCancellation()

        guard let destination = action.destination?.standardizedFileURL else {
            return skippedRecord(
                action: action,
                fileID: nil,
                sourceURL: nil,
                fileSize: 0,
                message: "Skipped folder creation because no approved destination was supplied."
            )
        }

        guard isInside(destination, root: rootFolder) else {
            return skippedRecord(
                action: action,
                fileID: nil,
                sourceURL: nil,
                fileSize: 0,
                message: "Skipped folder creation because the destination is outside the authorized directory."
            )
        }

        do {
            if fileManager.fileExists(atPath: destination.path) {
                let values = try destination.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
                guard values.isDirectory == true,
                      values.isSymbolicLink != true else {
                    return skippedRecord(
                        action: action,
                        fileID: nil,
                        sourceURL: nil,
                        fileSize: 0,
                        message: "Skipped creating \(destination.lastPathComponent) because that name is already used by a non-folder or symbolic link."
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
                    message: "Folder \(destination.lastPathComponent) already exists."
                )
            }

            try Task.checkCancellation()
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: false
            )

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
        } catch is CancellationError {
            throw CancellationError()
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

    // MARK: - Revalidation

    /// Returns nil only when the live item still matches the metadata approved by the
    /// cleanup session. Verification failure is a safe skip, never permission to mutate.
    private func currentStateMismatch(
        for file: FileMetadata,
        source: URL
    ) -> String? {
        do {
            if file.isDirectory {
                let current = try PackageContents.snapshot(at: source)
                let attributes = try fileManager.attributesOfItem(
                    atPath: source.path
                )
                let modified = attributes[.modificationDate] as? Date
                guard current.totalSize == file.size,
                      modified == file.modifiedAt else {
                    return FileVerificationError.changed.localizedDescription
                }
            } else {
                let current = try FileSnapshot.read(at: source)
                guard current.size == file.size,
                      current.modifiedAt == file.modifiedAt else {
                    return FileVerificationError.changed.localizedDescription
                }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func isInside(
        _ candidate: URL,
        root: URL
    ) -> Bool {
        candidate.standardizedFileURL.resolvingSymlinksInPath()
            == root.standardizedFileURL.resolvingSymlinksInPath()
            || DeletionVerifier.isInside(candidate, root: root)
    }

    private func availableDestination(
        in folder: URL,
        name: String
    ) -> URL {
        var candidate = folder.appendingPathComponent(name)
        let original = URL(fileURLWithPath: name)
        let ext = original.pathExtension
        let stem = original.deletingPathExtension().lastPathComponent
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let nextName = "\(stem) (\(suffix))"
                + (ext.isEmpty ? "" : ".\(ext)")
            candidate = folder.appendingPathComponent(nextName)
            suffix += 1
        }
        return candidate
    }

    private static func isDestinationCollision(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain
            && nsError.code == CocoaError.Code.fileWriteFileExists.rawValue
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

    private func skippedRecord(
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
            status: .skipped,
            message: message
        )
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
    case unsupportedAction(CleanupActionType)

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
