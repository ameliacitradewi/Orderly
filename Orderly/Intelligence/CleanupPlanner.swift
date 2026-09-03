import Foundation

final class CleanupPlanner {

    private let builder = CleanupPlanBuilder()

    func createPlan(
        folder: URL,
        files: [FileMetadata],
        analysis: AnalysisResult
    ) -> CleanupPlan {
        builder.buildPlan(
            folder: folder,
            candidates: analysis.candidates,
            files: files
        )
    }
}
