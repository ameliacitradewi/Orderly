import Foundation

struct ReviewedCleanupAction: Identifiable {

    let id: UUID

    var action: CleanupAction
    var decision: ReviewDecision

    init(
        action: CleanupAction
    ) {
        self.id = action.id
        self.action = action
        self.decision = .pending
    }
}
