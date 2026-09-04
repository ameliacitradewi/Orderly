import SwiftUI

struct AffectedFilesView: View {

    @Binding var action: CleanupAction

    let files: [FileMetadata]

    @Environment(\.dismiss)
    private var dismiss

    private var affectedFiles: [FileMetadata] {

        let lookup = FileLookup(
            files: files
        )

        return lookup.files(
            withIDs: action.fileIDs
        )
    }

    private var selectedFiles: [FileMetadata] {

        affectedFiles.filter {
            action.selectedFileIDs.contains(
                $0.id
            )
        }
    }

    private var selectedSize: Int64 {

        selectedFiles.reduce(0) {
            $0 + $1.size
        }
    }

    var body: some View {

        VStack(spacing: 0) {

            header

            Divider()

            fileList

            Divider()

            footer
        }
        .frame(
            minWidth: 560,
            minHeight: 460
        )
    }

    private var header: some View {

        VStack(
            alignment: .leading,
            spacing: 6
        ) {

            Text(action.title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(
                """
                Choose exactly which files should be included \
                in this action.
                """
            )
            .foregroundStyle(
                OrderlyTheme.secondaryText
            )

            Text(
                "\(selectedFiles.count) of \(affectedFiles.count) files selected"
            )
            .font(.caption)
            .foregroundStyle(
                OrderlyTheme.secondaryText
            )
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(20)
    }

    private var fileList: some View {

        ScrollView {

            LazyVStack(spacing: 0) {

                ForEach(affectedFiles) { file in

                    fileRow(file)

                    if file.id != affectedFiles.last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func fileRow(
        _ file: FileMetadata
    ) -> some View {

        Toggle(
            isOn: selectionBinding(
                for: file.id
            )
        ) {

            HStack(spacing: 12) {

                Image(
                    systemName: systemImage(
                        for: file.fileType
                    )
                )
                .foregroundStyle(
                    OrderlyTheme.accent
                )
                .frame(width: 20)

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {

                    Text(file.name)
                        .lineLimit(1)

                    Text(
                        file.url
                            .deletingLastPathComponent()
                            .lastPathComponent
                    )
                    .font(.caption)
                    .foregroundStyle(
                        OrderlyTheme.secondaryText
                    )
                }

                Spacer()

                Text(
                    ByteCountFormatter.string(
                        fromByteCount: file.size,
                        countStyle: .file
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    OrderlyTheme.secondaryText
                )
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 10)
    }

    private var footer: some View {

        HStack {

            VStack(
                alignment: .leading,
                spacing: 2
            ) {

                Text(
                    "\(selectedFiles.count) files selected"
                )

                Text(
                    ByteCountFormatter.string(
                        fromByteCount: selectedSize,
                        countStyle: .file
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    OrderlyTheme.secondaryText
                )
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(OrderlyTheme.accent)
        }
        .padding(20)
    }

    private func selectionBinding(
        for fileID: UUID
    ) -> Binding<Bool> {

        Binding(
            get: {
                !action
                    .excludedFileIDs
                    .contains(fileID)
            },
            set: { isIncluded in

                if isIncluded {

                    action.excludedFileIDs
                        .removeAll {
                            $0 == fileID
                        }

                } else {

                    guard !action
                        .excludedFileIDs
                        .contains(fileID)
                    else {
                        return
                    }

                    action
                        .excludedFileIDs
                        .append(fileID)
                }
            }
        )
    }

    private func systemImage(
        for type: FileType
    ) -> String {

        switch type {
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
            return "app"

        case .code:
            return "chevron.left.forwardslash.chevron.right"

        case .other:
            return "doc"
        }
    }
}
