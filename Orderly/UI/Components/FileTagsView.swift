import SwiftUI

struct FileTagsView: View {
    let file: FileMetadata
    let files: [FileMetadata]

    private var matches: [FileMetadata] {
        guard let group = file.duplicateGroupID else { return [] }

        return files
            .filter { $0.duplicateGroupID == group }
            .sorted { left, right in
                let leftIsKeeper = left.id == left.duplicateKeeperID
                let rightIsKeeper = right.id == right.duplicateKeeperID
                if leftIsKeeper != rightIsKeeper {
                    return leftIsKeeper
                }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(file.fileType.tagName)
                .font(.caption)
                .foregroundStyle(OrderlyTheme.secondaryText)

            if file.duplicateGroupID != nil {
                Menu {
                    Text("\(file.duplicateCopyCount) PCC-matched copies")
                    ForEach(matches) { match in
                        let role = match.id == match.duplicateKeeperID
                            ? "Keep"
                            : "Duplicate"
                        Text("\(role): \(match.name)")
                    }
                } label: {
                    Text("PCC Duplicate")
                        .font(.caption2)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("View files Private Cloud Compute grouped as duplicate content.")
            }
        }
    }
}
