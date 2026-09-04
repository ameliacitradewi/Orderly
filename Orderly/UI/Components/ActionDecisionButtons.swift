import SwiftUI

struct ActionDecisionButtons: View {

    @Binding var decision: ReviewDecision

    var body: some View {

        HStack(spacing: 8) {

            Button {
                decision = .rejected
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .tint(
                decision == .rejected
                ? OrderlyTheme.destructive
                : nil
            )
            .help("Reject this action")
            .accessibilityLabel("Reject action")

            Button {
                decision = .approved
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.bordered)
            .tint(
                decision == .approved
                ? OrderlyTheme.success
                : nil
            )
            .help("Approve this action")
            .accessibilityLabel("Approve action")
        }
    }
}
