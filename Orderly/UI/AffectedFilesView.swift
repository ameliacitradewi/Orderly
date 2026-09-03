import SwiftUI

struct AffectedFilesView: View {

    @Binding var action: CleanupAction
    let files: [FileMetadata]

    @Environment(\.dismiss) private var dismiss

    private var affectedFiles: [FileMetadata] {
        FileLookup(files: files).files(withIDs: action.fileIDs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text(action.title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("\(action.selectedFileIDs.count) of \(affectedFiles.count) files selected")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
            }

            List {
                ForEach(affectedFiles) { file in
                    Toggle(
                        isOn: Binding(
                            get: {
                                !action.excludedFileIDs.contains(file.id)
                            },
                            set: { included in
                                if included {
                                    action.excludedFileIDs.removeAll { $0 == file.id }
                                } else if !action.excludedFileIDs.contains(file.id) {
                                    action.excludedFileIDs.append(file.id)
                                }
                            }
                        )
                    ) {
                        VStack(alignment: .leading) {
                            Text(file.name)

                            Text(
                                ByteCountFormatter.string(
                                    fromByteCount: file.size,
                                    countStyle: .file
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
    }
}
