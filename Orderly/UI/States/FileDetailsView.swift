import SwiftUI

struct FileDetailsView: View {

    let files: [FileMetadata]

    var body: some View {

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

            TableColumn("Type") { file in
                Text(file.fileType.rawValue.capitalized)
                    .foregroundStyle(
                        OrderlyTheme.secondaryText
                    )
            }
            .width(min: 80, ideal: 100, max: 130)

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
