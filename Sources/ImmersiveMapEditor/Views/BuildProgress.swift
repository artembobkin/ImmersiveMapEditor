import SwiftUI

/// How far the build is, in one line: the command of the run, the stage, a
/// bar when its end is known (a spinner while not), and its detail. The
/// bottom panel's header and the status line show the same.
struct BuildProgress: View {
    @Environment(BuildRunner.self) private var runner

    var body: some View {
        HStack(spacing: 8) {
            if let fraction = runner.stage?.fraction {
                ProgressView(value: fraction).progressViewStyle(.linear).frame(width: 140)
                Text("\(Int((fraction * 100).rounded())) %").monospacedDigit().foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(title).lineLimit(1)
            if let detail = runner.stage?.detail {
                Text(detail).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        let name = runner.stage?.name ?? "Starting"
        return runner.step.count > 1 ? "\(runner.step.index) of \(runner.step.count): \(name)" : name
    }
}
