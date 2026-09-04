import SwiftUI

struct ScanningView: View {

    let folder: URL
    let files: [FileMetadata]
    let progress: Double?

    var body: some View {

        VStack(spacing: 0) {

            ScanHeaderView(
                folder: folder,
                progress: progress
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            Table(files) {

                TableColumn("Name") { file in

                    Label(
                        file.name,
                        systemImage: systemImage(
                            for: file.fileType
                        )
                    )
                    .lineLimit(1)
                }

                TableColumn("Size") { file in

                    Text(
                        ByteCountFormatter.string(
                            fromByteCount: file.size,
                            countStyle: .file
                        )
                    )
                    .font(.body.monospacedDigit())
                    .foregroundStyle(
                        OrderlyTheme.secondaryText
                    )
                }
                .width(min: 80, ideal: 100, max: 120)

                TableColumn("Modified") { file in

                    if let modified = file.modifiedAt {
                        Text(
                            modified,
                            format: .dateTime
                                .year()
                                .month()
                                .day()
                        )
                    } else {
                        Text("—")
                    }
                }
                .width(min: 100, ideal: 120, max: 150)
            }
            .overlay {
                if files.isEmpty {
                    Text("Discovering files...")
                        .font(.callout)
                        .foregroundStyle(
                            OrderlyTheme.secondaryText
                        )
                }
            }
        }
        .background(OrderlyTheme.background)
    }

    private func systemImage(
        for fileType: FileType
    ) -> String {

        switch fileType {
        case .image:
            return "photo"

        case .video:
            return "film"

        case .audio:
            return "waveform"

        case .document:
            return "doc"

        case .archive:
            return "archivebox"

        case .application:
            return "shippingbox"

        case .code:
            return "chevron.left.forwardslash.chevron.right"

        case .other:
            return "doc"
        }
    }
}

private struct ScanHeaderView: View {

    let folder: URL
    let progress: Double?

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            HStack(alignment: .bottom) {

                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {

                    Text("SCANNING")
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

                Spacer()

                if let progress {
                    Text(
                        progress,
                        format: .percent.precision(
                            .fractionLength(0)
                        )
                    )
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(
                        OrderlyTheme.accent
                    )
                }
            }

            if let progress {
                ProgressView(value: progress)
                    .tint(OrderlyTheme.accent)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(OrderlyTheme.accent)
            }
        }
    }
}
