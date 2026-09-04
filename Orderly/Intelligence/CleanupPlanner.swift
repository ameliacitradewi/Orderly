import Foundation

final class CleanupPlanner {

    private let builder = CleanupPlanBuilder()

    func createPlan(
        folder: URL,
        files: [FileMetadata],
        analysis: AnalysisResult,
        modelPlan: ModelCleanupPlan
    ) -> CleanupPlan {

        builder.buildPlan(
            folder: folder,
            candidates: analysis.candidates,
            modelPlan: modelPlan,
            files: files
        )
    }
}
