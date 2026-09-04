import SwiftUI

struct CleanupPlanView: View {

    let plan: CleanupPlan
    let files: [FileMetadata]

    @State private var reviewedActions: [CleanupAction]

    init(plan: CleanupPlan, files: [FileMetadata]) {
        self.plan = plan
        self.files = files
        _reviewedActions = State(initialValue: plan.actions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {

                Text("Cleanup Plan")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(plan.summary)
                    .foregroundStyle(.secondary)

                Text(plan.folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach($reviewedActions) { $action in

                CleanupActionRow(
                    action: $action,
                    files: files
                )
            }

            Divider()

            HStack {

                Spacer()

                Button("Apply Selected") {
                    createExecutionPlan()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }

    private func createExecutionPlan() {
        let executionActions = reviewedActions.compactMap { action -> ExecutionAction? in
            guard action.isSelected, !action.selectedFileIDs.isEmpty else {
                return nil
            }

            return ExecutionAction(
                sourceActionID: action.id,
                type: action.type,
                fileIDs: action.selectedFileIDs,
                destination: action.destination,
                createdAt: Date()
            )
        }

        let executionPlan = ExecutionPlan(
            cleanupPlanID: plan.id,
            selectedActions: executionActions,
            createdAt: Date()
        )

        print("Orderly: ExecutionPlan created:")
        print(executionPlan)
    }
}
