//
//  AnalysisCandidate.swift
//  Orderly
//

import Foundation

enum CandidateInvestigationRequirement: String, Codable, Hashable, Sendable {
    /// Normal production behavior: the agent decides which read-only evidence is
    /// necessary, subject to validators and bounded recovery.
    case automatic

    /// A trusted workflow requires semantic PDF inspection/comparison before the
    /// candidate may be considered complete. Used by deterministic evaluation and
    /// other workflows that explicitly need document semantics.
    case documentSemantic

    /// A trusted workflow requires visual inspection/comparison before the
    /// candidate may be considered complete. This never changes cleanup authority;
    /// image semantics remain non-destructive similarity evidence only.
    case imageSemantic
}

struct AnalysisCandidate: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let type: CandidateType
    let fileIDs: [UUID]
    let confidence: Double
    let reason: String
    let investigationRequirement: CandidateInvestigationRequirement

    init(
        id: UUID,
        type: CandidateType,
        fileIDs: [UUID],
        confidence: Double,
        reason: String,
        investigationRequirement: CandidateInvestigationRequirement = .automatic
    ) {
        self.id = id
        self.type = type
        self.fileIDs = fileIDs
        self.confidence = confidence
        self.reason = reason
        self.investigationRequirement = investigationRequirement
    }

    /// Older benchmark/smoke fixtures encoded the required semantic path only in
    /// their trusted internal reason string. Keep those fixtures compatible while
    /// new callers migrate to the typed requirement. This inference can only trigger
    /// additional read-only inspection of files already inside the candidate.
    var resolvedInvestigationRequirement: CandidateInvestigationRequirement {
        guard investigationRequirement == .automatic else {
            return investigationRequirement
        }

        let lowercasedReason = reason.lowercased()
        if lowercasedReason.contains("inspectpdfcontent")
            && lowercasedReason.contains("comparedocumentcontent") {
            return .documentSemantic
        }
        if lowercasedReason.contains("inspectimagecontent")
            && lowercasedReason.contains("compareimagecontent") {
            return .imageSemantic
        }
        return .automatic
    }
}

enum CandidateType: String, Codable, Hashable, Sendable {
    case grouping
    case duplicate
    case related
    case temporary
    case artifact
    case redundant
    case archive
    case review
}
