import SwiftUI

struct CompletionView: View {

    let result: ExecutionResult

    let onChooseAnotherFolder:
        () -> Void

    var body: some View {

        VStack(spacing: 18) {

            Image(
                systemName:
                    result.isFullySuccessful
                    ? "checkmark.circle"
                    : "exclamationmark.circle"
            )
            .font(.system(size: 32))
            .foregroundStyle(
                result.isFullySuccessful
                ? OrderlyTheme.success
                : OrderlyTheme.warning
            )

            Text(
                result.isFullySuccessful
                ? "All done."
                : "Completed with some issues."
            )
            .font(.title2)
            .fontWeight(.semibold)

            Text(
                "Freed up \(formattedReclaimedSize) of disk space."
            )
            .foregroundStyle(
                .secondary
            )

            OrderlyCard {

                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {

                    Text("EXECUTION LOG")
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )

                    ForEach(
                        result.records
                    ) { record in

                        Label(
                            record.message,
                            systemImage:
                                record.status == .succeeded
                                ? "checkmark"
                                : "xmark"
                        )
                        .foregroundStyle(
                            record.status == .succeeded
                            ? .primary
                            : OrderlyTheme.destructive
                        )
                    }
                }
            }
            .frame(
                maxWidth: 520
            )

            Button(
                "Declutter another folder"
            ) {
                onChooseAnotherFolder()
            }
        }
        .padding(40)
    }

    private var formattedReclaimedSize: String {

        ByteCountFormatter.string(
            fromByteCount: result.reclaimedBytes,
            countStyle: .file
        )
    }
}
