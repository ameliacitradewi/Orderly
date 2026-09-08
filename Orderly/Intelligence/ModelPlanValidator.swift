import Foundation

final class ModelPlanValidator {
    func issues(decisions: [ModelFileDecision], files: [CandidateFileEvidence]) -> [String] {
        let expected = Dictionary(uniqueKeysWithValues: files.map { ($0.reference, $0) })
        var seen = Set<String>()
        var issues: [String] = []
        for decision in decisions {
            guard let ref = FileReferenceMap.normalizedReference(decision.fileReference),
                  let file = expected[ref] else {
                issues.append("Unknown reference.")
                continue
            }
            guard seen.insert(ref).inserted else {
                issues.append("Duplicate decision for \(ref).")
                continue
            }
            if let required = file.requiredDisposition {
                if decision.disposition != required { issues.append("\(ref) must be \(required.rawValue).") }
            } else if !file.isInstallerCandidate || ![FileDisposition.trash, .move].contains(decision.disposition) {
                issues.append("Invalid installer recommendation for \(ref).")
            }
        }
        if seen != Set(expected.keys) { issues.append("Missing file decisions.") }
        return issues
    }
}
