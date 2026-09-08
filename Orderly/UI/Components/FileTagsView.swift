import SwiftUI

struct FileTagsView: View {
    let file: FileMetadata
    let files: [FileMetadata]

    private var matches: [FileMetadata] {
        guard let group = file.duplicateGroupID else { return [] }
        return files.filter { $0.duplicateGroupID == group }.sorted(by: DuplicateDetector.newestFirst)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(file.fileType.tagName)
                .font(.caption)
                .foregroundStyle(OrderlyTheme.secondaryText)
            if file.duplicateGroupID != nil {
                Menu {
                    Text("\(file.duplicateCopyCount) identical copies")
                    ForEach(matches) { match in
                        let role = match.id == match.duplicateKeeperID ? "Keep" : "Duplicate"
                        let date = match.modifiedAt?.formatted(date: .abbreviated, time: .standard) ?? "Unknown date"
                        Text("\(role): \(match.name) — \(date)\n\(match.url.path)")
                    }
                } label: {
                    Text("SHA256 Duplicate")
                        .font(.caption2)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("View all identical files and their Last Modified dates.")
            }
        }
    }
}
