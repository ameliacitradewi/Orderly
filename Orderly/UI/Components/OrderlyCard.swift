import SwiftUI

struct OrderlyCard<Content: View>: View {

    let content: Content

    init(
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                OrderlyTheme.surface
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
                .stroke(
                    OrderlyTheme.separator,
                    lineWidth: 1
                )
            }
    }
}
