import SwiftUI

struct StatusBadge: View {

    let actionType: CleanupActionType

    var body: some View {

        Text(title)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(
                color.opacity(0.10)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 4,
                    style: .continuous
                )
            )
    }

    private var title: String {

        switch actionType {
        case .trash:
            return "TRASH"

        case .move:
            return "ORGANIZE"

        case .createFolder:
            return "ORGANIZE"

        case .rename:
            return "RENAME"
        }
    }

    private var color: Color {

        switch actionType {
        case .trash:
            return OrderlyTheme.destructive

        case .move,
             .createFolder:
            return OrderlyTheme.success

        case .rename:
            return OrderlyTheme.warning
        }
    }
}
