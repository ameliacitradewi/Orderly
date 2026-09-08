import Foundation

final class ToolRouter {
    private let inspectPDFContentTool: InspectPDFContentTool

    init(
        contentInspectionService: any ContentInspectionService = PDFTextExtractor()
    ) {
        inspectPDFContentTool = InspectPDFContentTool(
            contentInspectionService: contentInspectionService
        )
    }

    func execute(
        decision: AgentDecision,
        environment: AgentEnvironment
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
            name=\(file.name)
            tag=\(file.tag.tagName)
            size=\(file.size)
            modified=\(file.modifiedAt?.formatted(.iso8601) ?? "unknown")
            allowedDispositions=\(file.allowedDispositions.map(\.rawValue).joined(separator: ","))
            duplicateCopies=\(file.duplicateCopyCount)
            duplicateKeeper=\(file.duplicateKeeperName ?? "none")
            """
        }

        return AgentObservation(
            type: .candidate,
            candidateID: candidateID,
            content: lines.joined(separator: "\n\n")
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
        let file = try file(
            reference: reference,
            in: evidence
        )

        let content = """
        reference=\(file.reference)
        name=\(file.name)
        tag=\(file.tag.tagName)
        size=\(file.size)
        modified=\(file.modifiedAt?.formatted(.iso8601) ?? "unknown")
        path=\(file.relativePath)
        installer=\(file.isInstallerCandidate)
        allowedDispositions=\(file.allowedDispositions.map(\.rawValue).joined(separator: ","))
        duplicateCopies=\(file.duplicateCopyCount)
        duplicateKeeper=\(file.duplicateKeeperName ?? "none")
        """

        return AgentObservation(
            type: .metadata,
            candidateID: candidateID,
            content: content
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

        guard decision.fileReferences.count == 2 else {
            throw AgentToolError.wrongFileCount
        }

        let refA = decision.fileReferences[0]
        let refB = decision.fileReferences[1]
        let a = try file(reference: refA, in: evidence)
        let b = try file(reference: refB, in: evidence)
        let sameSize = a.size == b.size
        let verifiedDuplicate =
            sameSize
            && a.duplicateCopyCount > 1
            && a.duplicateCopyCount == b.duplicateCopyCount

        let content = """
        \(a.reference) vs \(b.reference)

        sameSize=\(sameSize)
        verifiedDuplicate=\(verifiedDuplicate)

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
            content: content
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
        guard let metadata = environment.analysis.files.first(where: {
            $0.id == candidateFile.fileID
        }) else {
            throw AgentToolError.unavailableFileMetadata
        }

        return try inspectPDFContentTool.execute(
            file: metadata,
            fileReference: reference,
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
