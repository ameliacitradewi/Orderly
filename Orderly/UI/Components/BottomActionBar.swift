import SwiftUI

struct BottomActionBar: View {

    let approvedCount: Int
    let reclaimableSize: Int64
    let onExecute: () -> Void

    var body: some View {

        HStack {

            if approvedCount == 0 {

                Text("No actions approved yet")
                    .foregroundStyle(
                        OrderlyTheme.secondaryText
                    )

            } else {

                Text("\(approvedCount) actions approved")

                Text("·")
                    .foregroundStyle(
                        OrderlyTheme.tertiaryText
                    )

                Text("saves \(formattedSize)")
                    .foregroundStyle(
                        OrderlyTheme.success
                    )
            }

            Spacer()

            Button {
                onExecute()
            } label: {
                Label(
                    "Execute",
                    systemImage: "bolt.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(OrderlyTheme.accent)
            .disabled(approvedCount == 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            .regularMaterial
        )
        .overlay(
            alignment: .top
        ) {
            Divider()
        }
    }

    private var formattedSize: String {
        ByteCountFormatter.string(
            fromByteCount: reclaimableSize,
            countStyle: .file
        )
    }
}
