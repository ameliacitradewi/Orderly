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

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case fileIDs
        case confidence
        case reason
        case investigationRequirement
    }

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
        self.investigationRequirement = Self.resolveRequirement(
            explicit: investigationRequirement,
            reason: reason
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let type = try container.decode(CandidateType.self, forKey: .type)
        let fileIDs = try container.decode([UUID].self, forKey: .fileIDs)
        let confidence = try container.decode(Double.self, forKey: .confidence)
        let reason = try container.decode(String.self, forKey: .reason)
        let requirement = try container.decodeIfPresent(
            CandidateInvestigationRequirement.self,
            forKey: .investigationRequirement
        ) ?? .automatic

        self.init(
            id: id,
            type: type,
            fileIDs: fileIDs,
            confidence: confidence,
            reason: reason,
            investigationRequirement: requirement
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(fileIDs, forKey: .fileIDs)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(reason, forKey: .reason)
        try container.encode(investigationRequirement, forKey: .investigationRequirement)
    }

    private static func resolveRequirement(
        explicit: CandidateInvestigationRequirement,
        reason: String
    ) -> CandidateInvestigationRequirement {
        guard explicit == .automatic else { return explicit }

        // Older benchmark/smoke fixtures encoded a mandatory semantic path only in
        // their trusted internal reason string. Preserve that behavior while callers
        // migrate to the typed field. Inference can only require extra read-only
        // inspection of files already inside this candidate; it never grants cleanup
        // authority or exposes a new filesystem path.
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
