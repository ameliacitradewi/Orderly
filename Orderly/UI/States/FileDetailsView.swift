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

            TableColumn("Tags") { file in
                FileTagsView(file: file, files: files)
            }
            .width(min: 120, ideal: 160, max: 200)

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

            TableColumn("Last Modified") { file in
                if let modified = file.modifiedAt {
                    Text(
                        modified,
                        format: .dateTime
                            .year()
                            .month()
                            .day()
                            .hour()
                            .minute()
                            .second()
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

        case .artifact:
            return "doc.badge.gearshape"

        case .other:
            return "doc"
        }
    }
}
