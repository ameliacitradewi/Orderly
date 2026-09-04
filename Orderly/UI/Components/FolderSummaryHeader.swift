import SwiftUI

struct FolderSummaryHeader: View {

    let folder: URL
    let files: [FileMetadata]

    private var totalSize: Int64 {
        files.reduce(0) {
            $0 + $1.size
        }
    }

    var body: some View {

        HStack(alignment: .bottom) {

            VStack(
                alignment: .leading,
                spacing: 6
            ) {

                Text("FOLDER ANALYZED")
                    .font(.caption)
                    .foregroundStyle(
                        OrderlyTheme.secondaryText
                    )

                Text(folder.path)
                    .font(.callout.monospaced())
                    .foregroundStyle(
                        OrderlyTheme.primaryText
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 32)

            HStack(spacing: 28) {

                MetricView(
                    title: "Total size",
                    value: ByteCountFormatter.string(
                        fromByteCount: totalSize,
                        countStyle: .file
                    )
                )

                MetricView(
                    title: "Files",
                    value: "\(files.count)"
                )
            }
        }
    }
}

private struct MetricView: View {

    let title: String
    let value: String

    var body: some View {

        VStack(
            alignment: .trailing,
            spacing: 5
        ) {

            Text(title)
                .font(.caption)
                .foregroundStyle(
                    OrderlyTheme.secondaryText
                )

            Text(value)
                .font(.callout.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundStyle(
                    OrderlyTheme.primaryText
                )
        }
    }
}
