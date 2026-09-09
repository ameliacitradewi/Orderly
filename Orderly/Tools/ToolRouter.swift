import Foundation

final class ToolRouter {
    private let inspectPDFContentTool: InspectPDFContentTool
    private let documentComparisonTool: DocumentComparisonTool?

    init(
        contentInspectionService: any ContentInspectionService = PDFTextExtractor(),
        documentSemanticAnalyzer: (any DocumentSemanticAnalyzing)? = nil
    ) {
        inspectPDFContentTool = InspectPDFContentTool(
            contentInspectionService: contentInspectionService
        )
        if let documentSemanticAnalyzer {
            documentComparisonTool = DocumentComparisonTool(
                semanticAnalyzer: documentSemanticAnalyzer
            )
        } else {
            documentComparisonTool = nil
        }
    }

    func executeAsync(
        decision: AgentDecision,
        environment: AgentEnvironment,
        observations: [AgentObservation] = []
    ) async throws -> AgentObservation {
        if decision.action == .compareDocumentContent {
            let (candidateID, _) = try candidateEvidence(
                for: decision,
                environment: environment
            )
            guard let documentComparisonTool else {
                throw AgentToolError.semanticAnalyzerUnavailable
            }
            return try await documentComparisonTool.execute(
                references: decision.fileReferences,
                candidateID: candidateID,
                environment: environment,
                observations: observations
            )
        }

        return try execute(
            decision: decision,
            environment: environment,
            observations: observations
        )
    }

    func execute(
        decision: AgentDecision,
        environment: AgentEnvironment,
        observations: [AgentObservation] = []
    ) throws -> AgentObservation {
        switch decision.action {
        case .inspectCandidate:
            return try inspectCandidate(
                decision,
                environment: environment
            )
        case .inspectFile:
            return try inspectFile(
                decision,
                environment: environment
            )
        case .compareFiles:
            return try compareFiles(
                decision,
                environment: environment
            )
        case .inspectPDFContent:
            return try inspectPDFContent(
                decision,
                environment: environment
            )
        case .findRelatedFiles:
            let (candidateID, evidence) = try candidateEvidence(
                for: decision,
                environment: environment
            )
            guard decision.fileReferences.count == 1 else {
                throw AgentToolError.wrongFileCount
            }
            let source = try file(
                reference: decision.fileReferences[0],
                in: evidence
            )
            return try FindRelatedFilesTool().execute(
                sourceID: source.fileID,
                candidateID: candidateID,
                environment: environment
            )
        case .inspectGlobalFile, .compareGlobalFiles:
            let (candidateID, evidence) = try candidateEvidence(
                for: decision,
                environment: environment
            )
            let expectedCount = decision.action == .inspectGlobalFile ? 1 : 2
            guard decision.fileReferences.count == expectedCount,
                  Set(decision.fileReferences).count == expectedCount else {
                throw AgentToolError.wrongFileCount
            }
            let visible = environment.visibleGlobalReferences(
                candidateID: candidateID,
                observations: observations
            )
            let files = try decision.fileReferences.map { reference in
                guard let metadata = environment.filesByGlobalReference[reference] else {
                    throw AgentToolError.invalidFileReference(reference)
                }
                guard visible.contains(reference) else {
                    throw AgentToolError.unobservedGlobalReference(reference)
                }
                return metadata
            }
            let tool = GlobalFileInspectionTool()
            if decision.action == .inspectGlobalFile {
                return tool.inspect(
                    file: files[0],
                    reference: decision.fileReferences[0],
                    candidateID: candidateID,
                    environment: environment
                )
            }
            guard files.contains(where: { file in
                evidence.files.contains { $0.fileID == file.id }
            }) else {
                throw AgentToolError.comparisonOutsideCandidate
            }
            return tool.compare(
                files[0],
                files[1],
                references: decision.fileReferences,
                candidateID: candidateID
            )
        case .inspectGlobalPDFContent:
            return try inspectGlobalPDFContent(
                decision,
                environment: environment,
                observations: observations
            )
        case .compareDocumentContent:
            throw AgentToolError.notAToolAction
        case .finishCandidate:
            throw AgentToolError.notAToolAction
        }
    }

    private func inspectCandidate(
        _ decision: AgentDecision,
        environment: AgentEnvironment
    ) throws -> AgentObservation {
        let (candidateID, evidence) = try candidateEvidence(
            for: decision,
            environment: environment
        )

        let lines = evidence.files.map { file in
            """
            \(file.reference):
            globalReference=\(environment.globalReferenceByFileID[file.fileID] ?? "unavailable")
            name=\(file.name)
            tag=\(file.tag.tagName)
            size=\(file.size)
            modified=\(file.modifiedAt?.formatted(.iso8601) ?? "unknown")
            allowedDispositions=\(file.allowedDispositions.map(\.rawValue).joined(separator: ","))
            duplicateCopies=\(file.duplicateCopyCount)
            duplicateKeeper=\(file.duplicateKeeperName ?? "none")
            """
        }

        let pdfFiles = evidence.files.filter { file in
            guard let global = environment.globalReferenceByFileID[file.fileID],
                  let metadata = environment.filesByGlobalReference[global] else {
                return false
            }
            return InspectPDFContentTool.supports(metadata)
        }
        let imageFiles = evidence.files.filter { file in
            guard let global = environment.globalReferenceByFileID[file.fileID],
                  let metadata = environment.filesByGlobalReference[global] else {
                return false
            }
            return InspectImageEvidenceTool.supports(metadata)
        }

        return AgentObservation(
            type: .candidate,
            candidateID: candidateID,
            content: lines.joined(separator: "\n\n"),
            globalReferences: evidence.files.compactMap {
                environment.globalReferenceByFileID[$0.fileID]
            },
            pdfFileReferences: pdfFiles.map(\.reference),
            pdfGlobalReferences: pdfFiles.compactMap {
                environment.globalReferenceByFileID[$0.fileID]
            },
            imageFileReferences: imageFiles.map(\.reference),
            imageGlobalReferences: imageFiles.compactMap {
                environment.globalReferenceByFileID[$0.fileID]
            }
        )
    }

    private func inspectFile(
        _ decision: AgentDecision,
        environment: AgentEnvironment
    ) throws -> AgentObservation {
        let (candidateID, evidence) = try candidateEvidence(
            for: decision,
            environment: environment
        )

        guard decision.fileReferences.count == 1 else {
            throw AgentToolError.wrongFileCount
        }

        let reference = decision.fileReferences[0]
        let candidateFile = try file(
            reference: reference,
            in: evidence
        )
        let globalReference = environment.globalReferenceByFileID[candidateFile.fileID]
        let metadata = globalReference.flatMap {
            environment.filesByGlobalReference[$0]
        }

        let content = """
        reference=\(candidateFile.reference)
        globalReference=\(globalReference ?? "unavailable")
        name=\(candidateFile.name)
        tag=\(candidateFile.tag.tagName)
        size=\(candidateFile.size)
        modified=\(candidateFile.modifiedAt?.formatted(.iso8601) ?? "unknown")
        path=\(candidateFile.relativePath)
        installer=\(candidateFile.isInstallerCandidate)
        allowedDispositions=\(candidateFile.allowedDispositions.map(\.rawValue).joined(separator: ","))
        duplicateCopies=\(candidateFile.duplicateCopyCount)
        duplicateKeeper=\(candidateFile.duplicateKeeperName ?? "none")
        """

        return AgentObservation(
            type: .metadata,
            candidateID: candidateID,
            content: content,
            globalReferences: globalReference.map { [$0] },
            pdfGlobalReferences: (metadata.map(InspectPDFContentTool.supports) == true)
                ? globalReference.map { [$0] }
                : nil,
            imageGlobalReferences: (metadata.map(InspectImageEvidenceTool.supports) == true)
                ? globalReference.map { [$0] }
                : nil
        )
    }

    private func compareFiles(
        _ decision: AgentDecision,
        environment: AgentEnvironment
    ) throws -> AgentObservation {
        let (candidateID, evidence) = try candidateEvidence(
            for: decision,
            environment: environment
        )

        guard decision.fileReferences.count == 2,
              Set(decision.fileReferences).count == 2 else {
            throw AgentToolError.wrongFileCount
        }

        let refA = decision.fileReferences[0]
        let refB = decision.fileReferences[1]
        let a = try file(reference: refA, in: evidence)
        let b = try file(reference: refB, in: evidence)
        let sameSize = a.size == b.size
        guard let globalA = environment.globalReferenceByFileID[a.fileID],
              let globalB = environment.globalReferenceByFileID[b.fileID],
              let metadataA = environment.filesByGlobalReference[globalA],
              let metadataB = environment.filesByGlobalReference[globalB] else {
            throw AgentToolError.unavailableFileMetadata
        }
        let comparison = FileComparisonObservation(metadataA, metadataB)

        let content = """
        \(a.reference) vs \(b.reference)

        sameSize=\(sameSize)
        verifiedDuplicate=\(comparison.verifiedDuplicate)

        fileA:
        name=\(a.name)
        size=\(a.size)
        modified=\(a.modifiedAt?.formatted(.iso8601) ?? "unknown")
        duplicateCopies=\(a.duplicateCopyCount)
        duplicateKeeper=\(a.duplicateKeeperName ?? "none")

        fileB:
        name=\(b.name)
        size=\(b.size)
        modified=\(b.modifiedAt?.formatted(.iso8601) ?? "unknown")
        duplicateCopies=\(b.duplicateCopyCount)
        duplicateKeeper=\(b.duplicateKeeperName ?? "none")
        """

        return AgentObservation(
            type: .comparison,
            candidateID: candidateID,
            content: content,
            globalReferences: [globalA, globalB],
            comparison: comparison
        )
    }

    private func inspectPDFContent(
        _ decision: AgentDecision,
        environment: AgentEnvironment
    ) throws -> AgentObservation {
        let (candidateID, evidence) = try candidateEvidence(
            for: decision,
            environment: environment
        )
        guard decision.fileReferences.count == 1 else {
            throw AgentToolError.wrongFileCount
        }

        let reference = decision.fileReferences[0]
        let candidateFile = try file(
            reference: reference,
            in: evidence
        )
        guard let globalReference = environment.globalReferenceByFileID[candidateFile.fileID],
              let metadata = environment.filesByGlobalReference[globalReference] else {
            throw AgentToolError.unavailableFileMetadata
        }

        return try inspectPDFContentTool.execute(
            file: metadata,
            localReference: reference,
            globalReference: globalReference,
            candidateID: candidateID,
            analyzedFolder: environment.analysis.analyzedFolder
        )
    }

    private func inspectGlobalPDFContent(
        _ decision: AgentDecision,
        environment: AgentEnvironment,
        observations: [AgentObservation]
    ) throws -> AgentObservation {
        let (candidateID, evidence) = try candidateEvidence(
            for: decision,
            environment: environment
        )
        guard decision.fileReferences.count == 1 else {
            throw AgentToolError.wrongFileCount
        }

        let reference = decision.fileReferences[0]
        let visible = environment.visibleGlobalReferences(
            candidateID: candidateID,
            observations: observations
        )
        guard visible.contains(reference) else {
            throw AgentToolError.unobservedGlobalReference(reference)
        }
        guard let metadata = environment.filesByGlobalReference[reference] else {
            throw AgentToolError.invalidFileReference(reference)
        }
        let localReference = evidence.files.first {
            $0.fileID == metadata.id
        }?.reference

        return try inspectPDFContentTool.execute(
            file: metadata,
            localReference: localReference,
            globalReference: reference,
            candidateID: candidateID,
            analyzedFolder: environment.analysis.analyzedFolder
        )
    }

    private func candidateEvidence(
        for decision: AgentDecision,
        environment: AgentEnvironment
    ) throws -> (UUID, CandidateEvidence) {
        guard let candidateID = decision.candidateID else {
            throw AgentToolError.missingCandidate
        }
        guard let evidence = environment.evidenceByCandidate[candidateID] else {
            throw AgentToolError.unknownCandidate
        }
        return (candidateID, evidence)
    }

    private func file(
        reference: String,
        in evidence: CandidateEvidence
    ) throws -> CandidateFileEvidence {
        guard let file = evidence.files.first(where: {
            $0.reference == reference
        }) else {
            throw AgentToolError.invalidFileReference(reference)
        }
        return file
    }
}
