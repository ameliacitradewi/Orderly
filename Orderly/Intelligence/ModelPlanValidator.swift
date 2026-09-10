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
            if !file.allowedDispositions.contains(decision.disposition) {
                issues.append("\(decision.disposition.rawValue) is not allowed for \(ref).")
            }
        }
        if seen != Set(expected.keys) { issues.append("Missing file decisions.") }
        return issues
    }
}
