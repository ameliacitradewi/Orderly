import SwiftUI

enum ReviewTab: Equatable {
    case plan
    case files
}

struct ReviewTabBar: View {

    @Binding var selectedTab: ReviewTab

    var body: some View {

        HStack(spacing: 24) {

            tab(
                "Declutter Plan",
                .plan
            )

            tab(
                "File Details",
                .files
            )

            Spacer()
        }
        .overlay(
            alignment: .bottom
        ) {
            Divider()
        }
    }

    @ViewBuilder
    private func tab(
        _ title: String,
        _ tab: ReviewTab
    ) -> some View {

        Button(title) {
            selectedTab = tab
        }
        .buttonStyle(.plain)
        .padding(.vertical, 10)
        .foregroundStyle(
            selectedTab == tab
            ? OrderlyTheme.primaryText
            : OrderlyTheme.secondaryText
        )
        .overlay(
            alignment: .bottom
        ) {
            if selectedTab == tab {
                Rectangle()
                    .fill(
                        OrderlyTheme.accent
                    )
                    .frame(height: 2)
            }
        }
    }
}
