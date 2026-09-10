import Foundation

struct AgentPlanAdapter {
    func makeModelPlan(
        state: AgentState,
        analysis: AnalysisResult
    ) -> ModelCleanupPlan {
        let findingsByCandidate = Dictionary(
            uniqueKeysWithValues: state.findings.map {
                ($0.candidateID, $0)
            }
        )
        let recommendations = analysis.candidates.compactMap {
            candidate -> CleanupRecommendation? in
            guard let finding = findingsByCandidate[candidate.id] else {
                return nil
            }
            return recommendation(for: finding)
        }

        let fallbackCount = Set(state.candidateFailures.map(\.candidateID)).count
        let summary: String
        if fallbackCount == 0 {
            summary = "Orderly agent investigated \(recommendations.count) candidates."
        } else {
            summary = "Orderly prepared \(recommendations.count) candidate recommendations. \(fallbackCount) used a safe non-destructive fallback because investigation could not complete."
        }

        return ModelCleanupPlan(
            summary: summary,
            recommendations: recommendations
        )
    }

    private func recommendation(
        for finding: AgentFinding
    ) -> CleanupRecommendation {
        CleanupRecommendation(
            candidateID: finding.candidateID.uuidString,
            title: title(for: finding.relationship),
            explanation: finding.summary,
            fileDecisions: finding.proposals.map {
                ModelFileDecision(
                    fileReference: $0.fileReference,
                    disposition: $0.disposition,
                    reason: $0.reason
                )
            },
            destinationFolderName: "",
            confidence: finding.confidence
        )
    }

    private func title(
        for relationship: CandidateRelationship
    ) -> String {
        switch relationship {
        case .exactDuplicate:
            return "Clean up duplicate files"
        case .grouping:
            return "Organize category files"
        case .artifact:
            return "Clean up generated files"
        case .related:
            return "Review related files"
        case .unrelated:
            return "Organize files"
        case .uncertain:
            return "Review files"
        }
    }
}
