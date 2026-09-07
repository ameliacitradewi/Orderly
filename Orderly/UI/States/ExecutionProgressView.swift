import SwiftUI

struct ExecutionProgressView: View {

    let progress: ExecutionProgress

    var body: some View {

        VStack(spacing: 14) {

            Image(
                systemName: "bolt.fill"
            )
            .foregroundStyle(
                OrderlyTheme.accent
            )

            Text("Executing plan...")
                .font(.headline)

            Text(
                "\(progress.completedActions) of \(progress.totalActions) actions complete"
            )
            .foregroundStyle(
                .secondary
            )

            ProgressView(
                value: progress.fraction
            )
            .frame(
                width: 360
            )

            Text(
                progress.currentMessage
            )
            .font(.caption)
            .foregroundStyle(
                .secondary
            )
        }
    }
}
