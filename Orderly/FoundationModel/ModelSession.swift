//
//  ModelSession.swift
//  Orderly
//
//  Created by Amelia Citra on 03/09/26.
//

import Foundation
import FoundationModels

@MainActor
final class OrderlyModelSession {

    private var session: LanguageModelSession?

    func analyze(
        files: [FileMetadata],
        analysis: AnalysisResult
    ) async throws -> String {

        let session = LanguageModelSession(
            instructions: """
            You are Orderly, a macOS file organization assistant.

            Your job is to analyze file metadata and suggest
            safe organization actions.

            Rules:
            - Never delete files.
            - Never invent files.
            - Never assume a file's contents unless the metadata
              provides evidence.
            - Prefer organization over deletion.
            - Be conservative when confidence is low.
            - Do not execute any filesystem operation.
            - Return concise, actionable recommendations.
            """
        )

        self.session = session

        let prompt = buildPrompt(
            analysis: analysis
        )

        let response = try await session.respond(
            to: prompt
        )

        return response.content
    }

    private func buildPrompt(
        analysis: AnalysisResult
    ) -> String {
        let typeSummary = analysis.fileTypes.map {
            "\($0.type.rawValue): \($0.count) files"
        }.joined(separator: ", ")

        let candidateSummary = analysis.candidates.map { candidate in
            """
            Candidate ID: \(candidate.id.uuidString)
            Type: \(candidate.type.rawValue)
            Files: \(candidate.fileIDs.count)
            Confidence: \(candidate.confidence)
            Reason: \(candidate.reason)
            """
        }.joined(separator: "\n\n")

        return """
        Analyze these precomputed cleanup candidates.

        Folder:
        \(analysis.analyzedFolder.path)

        Total files:
        \(analysis.totalFiles)

        Total size:
        \(analysis.totalSize) bytes

        File types:
        \(typeSummary)

        Duplicate groups:
        \(analysis.duplicateGroups.count)

        Candidates:
        \(candidateSummary)

        Select or explain candidates by Candidate ID only.
        The application owns the file identities and will resolve each
        candidate ID to its concrete file UUIDs.

        For every recommendation provide:
        1. Candidate ID
        2. Action
        3. Suggested destination
        4. Confidence
        5. Reason

        Do not execute anything.
        """
    }
}
