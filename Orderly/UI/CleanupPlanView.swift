import SwiftUI

struct CleanupPlanView: View {

    let plan: CleanupPlan
    let files: [FileMetadata]

    @State private var selectedTab:
        ReviewTab = .plan

    @State private var reviewedActions:
        [ReviewedCleanupAction]

    init(
        plan: CleanupPlan,
        files: [FileMetadata]
    ) {

        self.plan = plan
        self.files = files

        _reviewedActions = State(
            initialValue: plan.actions.map {
                ReviewedCleanupAction(
                    action: $0
                )
            }
        )
    }

    var body: some View {

        VStack(spacing: 0) {

            VStack(spacing: 18) {

                FolderSummaryHeader(
                    folder: plan.folder,
                    files: files
                )

                ReviewTabBar(
                    selectedTab: $selectedTab
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            switch selectedTab {
            case .plan:
                planContent

            case .files:
                FileDetailsView(
                    files: files
                )
            }

            BottomActionBar(
                approvedCount: approvedActions.count,
                reclaimableSize: approvedSize,
                onExecute: {
                    createExecutionPlan()
                }
            )
        }
    }

    private var planContent: some View {

        ScrollView {

            LazyVStack(
                alignment: .leading,
                spacing: 12
            ) {

                Label(
                    "Orderly identified \(reviewedActions.count) actions. Approve or reject each one before continuing.",
                    systemImage: "sparkles"
                )
                .font(.callout)
                .foregroundStyle(
                    OrderlyTheme.secondaryText
                )

                ForEach(
                    $reviewedActions
                ) { $reviewedAction in

                    CleanupActionRow(
                        action: $reviewedAction.action,
                        files: files,
                        decision: $reviewedAction.decision
                    )
                }
            }
            .padding(24)
        }
    }

    private var approvedActions:
        [ReviewedCleanupAction] {

        reviewedActions.filter {
            $0.decision == .approved
        }
    }

    private var approvedSize: Int64 {

        let lookup = FileLookup(
            files: files
        )

        return approvedActions
            .flatMap {
                lookup.files(
                    withIDs: $0.action.selectedFileIDs
                )
            }
            .reduce(0) {
                $0 + $1.size
            }
    }

    private func createExecutionPlan() {

        let executionActions =
            approvedActions.compactMap {
                reviewedAction
                -> ExecutionAction? in

                let action =
                    reviewedAction.action

                guard !action
                    .selectedFileIDs
                    .isEmpty
                else {
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

        let executionPlan =
            ExecutionPlan(
                cleanupPlanID: plan.id,
                selectedActions: executionActions,
                createdAt: Date()
            )

        print(
            "Orderly: ExecutionPlan created:"
        )

        print(executionPlan)
    }
}
