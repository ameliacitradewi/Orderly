import SwiftUI

struct CompletionView: View {
    let result: ExecutionResult
    let onChooseAnotherFolder: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: headlineIcon)
                .font(.system(size: 32))
                .foregroundStyle(headlineColor)

            Text(headline)
                .font(.title2)
                .fontWeight(.semibold)

            Text(
                "Moved \(formattedReclaimedSize) to Trash. Space is freed when Trash is emptied."
            )
            .foregroundStyle(.secondary)

            if result.skippedCount > 0 || result.failedCount > 0 {
                Text(issueSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            OrderlyCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("EXECUTION LOG")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(result.records) { record in
                        Label(
                            record.message,
                            systemImage: icon(for: record.status)
                        )
                        .foregroundStyle(color(for: record.status))
                    }
                }
            }
            .frame(maxWidth: 520)

            Button("Declutter another folder") {
                onChooseAnotherFolder()
            }
        }
        .padding(40)
    }

    private var headline: String {
        if result.wasCancelled {
            return "Execution cancelled safely."
        }
        return result.isFullySuccessful
            ? "All done."
            : "Completed with some issues."
    }

    private var headlineIcon: String {
        if result.wasCancelled {
            return "stop.circle"
        }
        return result.isFullySuccessful
            ? "checkmark.circle"
            : "exclamationmark.circle"
    }

    private var headlineColor: Color {
        result.isFullySuccessful
            ? OrderlyTheme.success
            : OrderlyTheme.warning
    }

    private var issueSummary: String {
        var parts: [String] = []
        if result.skippedCount > 0 {
            parts.append("\(result.skippedCount) safely skipped")
        }
        if result.failedCount > 0 {
            parts.append("\(result.failedCount) failed")
        }
        return parts.joined(separator: " · ")
    }

    private func icon(for status: ExecutionRecordStatus) -> String {
        switch status {
        case .succeeded:
            return "checkmark"
        case .skipped:
            return "minus.circle"
        case .failed:
            return "xmark"
        }
    }

    private func color(for status: ExecutionRecordStatus) -> Color {
        switch status {
        case .succeeded:
            return .primary
        case .skipped:
            return OrderlyTheme.warning
        case .failed:
            return OrderlyTheme.destructive
        }
    }

    private var formattedReclaimedSize: String {
        ByteCountFormatter.string(
            fromByteCount: result.reclaimedBytes,
            countStyle: .file
        )
    }
}
