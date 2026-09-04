import SwiftUI

struct CleanupActionRow: View {

    @Binding var action: CleanupAction
    let files: [FileMetadata]

    @Binding var decision: ReviewDecision

    @State private var showFiles = false

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            HStack(alignment: .top) {

                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {

                    HStack(spacing: 8) {

                        StatusBadge(
                            actionType: action.type
                        )

                        Text(
                            "\(action.selectedFileIDs.count) of \(action.fileIDs.count) files"
                        )
                            .font(.caption)
                            .foregroundStyle(
                                OrderlyTheme.secondaryText
                            )
                    }

                    Text(action.title)
                        .font(.headline)
                        .foregroundStyle(
                            OrderlyTheme.primaryText
                        )

                    Text(action.explanation)
                        .font(.callout)
                        .foregroundStyle(
                            OrderlyTheme.secondaryText
                        )
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }

                Spacer(minLength: 16)

                ActionDecisionButtons(
                    decision: $decision
                )
            }

            filePreview

            Button("Show Files") {
                showFiles = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                OrderlyTheme.accent
            )
            .font(.caption)
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
            .stroke(
                borderColor,
                lineWidth: 1
            )
        }
        .sheet(
            isPresented: $showFiles
        ) {
            AffectedFilesView(
                action: $action,
                files: files
            )
        }
    }

    @ViewBuilder
    private var filePreview: some View {

        let lookup = FileLookup(
            files: files
        )

        let affectedFiles = lookup.files(
            withIDs: action.selectedFileIDs
        )

        if !affectedFiles.isEmpty {

            HStack(spacing: 6) {

                ForEach(
                    affectedFiles.prefix(3)
                ) { file in

                    Text(file.name)
                        .font(.caption2)
                        .lineLimit(1)
                        .padding(
                            .horizontal,
                            7
                        )
                        .padding(
                            .vertical,
                            4
                        )
                        .background(
                            OrderlyTheme
                                .elevatedSurface
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 4,
                                style: .continuous
                            )
                        )
                }

                if affectedFiles.count > 3 {

                    Text("+\(affectedFiles.count - 3)")
                        .font(.caption2)
                        .foregroundStyle(
                            OrderlyTheme.secondaryText
                        )
                }
            }
        }
    }

    private var cardBackground: Color {

        switch decision {
        case .approved:
            return OrderlyTheme
                .success
                .opacity(0.08)

        case .rejected:
            return OrderlyTheme
                .destructive
                .opacity(0.04)

        case .pending:
            return OrderlyTheme.surface
        }
    }

    private var borderColor: Color {

        switch decision {
        case .approved:
            return OrderlyTheme.success

        case .rejected:
            return OrderlyTheme
                .destructive
                .opacity(0.50)

        case .pending:
            return OrderlyTheme.separator
        }
    }
}
