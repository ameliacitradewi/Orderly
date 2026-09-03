import SwiftUI

struct CleanupActionRow: View {

    @Binding var action: CleanupAction
    let files: [FileMetadata]

    @State private var showingFiles = false

    private var selectedCount: Int {
        action.selectedFileIDs.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Toggle(isOn: $action.isSelected) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(action.title)
                            .font(.headline)

                        Text(action.explanation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(action.riskLevel.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }

            HStack {
                Text("\(selectedCount) of \(action.fileIDs.count) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Show Files") {
                    showingFiles = true
                }
                .buttonStyle(.link)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showingFiles) {
            AffectedFilesView(action: $action, files: files)
        }
    }
}
