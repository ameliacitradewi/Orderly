//
//  ModelPlanValidator.swift
//  Orderly
//
//  Created by Amelia Citra on 07/09/26.
//

import Foundation

struct ValidatedRecommendation {

    let recommendation: CleanupRecommendation
    let candidate: AnalysisCandidate
    let decisions: [UUID: ModelFileDecision]
    let issues: [ValidationIssue]

    var isValid: Bool {
        issues.isEmpty
    }
}

enum ValidationIssue: Equatable {

    case unknownFileReference(String)

    case duplicateDecision(String)

    case missingDecision(UUID)

    case allDuplicateCopiesTrashed

    case unknownCandidate
}

final class ModelPlanValidator {

    func validate(
        recommendation: CleanupRecommendation,
        candidate: AnalysisCandidate
    ) -> ValidatedRecommendation {

        let referenceMap = FileReferenceMap(
            fileIDs: candidate.fileIDs
        )

        var decisions: [UUID: ModelFileDecision] = [:]
        var issues: [ValidationIssue] = []

        for decision in recommendation.fileDecisions {

            let reference =
                decision.fileReference
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

            guard let fileID =
                referenceMap.fileID(
                    for: reference
                )
            else {

                issues.append(
                    .unknownFileReference(
                        reference
                    )
                )

                continue
            }

            guard decisions[fileID] == nil else {

                issues.append(
                    .duplicateDecision(
                        reference
                    )
                )

                continue
            }

            decisions[fileID] = decision
        }

        // Every candidate file must get a decision.

        for fileID in candidate.fileIDs {

            if decisions[fileID] == nil {

                issues.append(
                    .missingDecision(
                        fileID
                    )
                )
            }
        }

        // Exact duplicate protection.

        if candidate.type == .duplicate {

            let dispositions =
                decisions.values.map {
                    $0.disposition
                }

            if decisions.count ==
                candidate.fileIDs.count,
               dispositions.allSatisfy({
                   $0 == .trash
               }) {

                issues.append(
                    .allDuplicateCopiesTrashed
                )
            }
        }

        return ValidatedRecommendation(
            recommendation: recommendation,
            candidate: candidate,
            decisions: decisions,
            issues: issues
        )
    }
}
