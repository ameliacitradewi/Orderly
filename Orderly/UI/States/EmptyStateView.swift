import SwiftUI

struct EmptyStateView: View {

    let onSelectFolder: () -> Void

    var body: some View {

        VStack(spacing: 18) {

            Image(systemName: "folder")
                .font(.system(size: 24))
                .foregroundStyle(
                    OrderlyTheme.accent
                )
                .frame(
                    width: 60,
                    height: 60
                )
                .background(
                    OrderlyTheme.surface
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                    .stroke(
                        OrderlyTheme.separator,
                        lineWidth: 1
                    )
                }
                .shadow(
                    color: .black.opacity(0.08),
                    radius: 2,
                    y: 1
                )

            VStack(spacing: 8) {

                Text("Choose a folder")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        OrderlyTheme.primaryText
                    )

                Text(
                    """
                    Orderly will scan the folder, analyze its contents, and \
                    generate a personalized declutter plan.
                    """
                )
                .foregroundStyle(
                    OrderlyTheme.secondaryText
                )
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            }

            Button {
                onSelectFolder()
            } label: {
                Label(
                    "Select Folder...",
                    systemImage: "folder"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(OrderlyTheme.accent)

            Text(
                "Works with Downloads, Desktop, Documents, and any custom directory."
            )
            .font(.caption)
            .foregroundStyle(
                OrderlyTheme.tertiaryText
            )
        }
        .padding(40)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }
}
