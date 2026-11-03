import SwiftUI

/// How far a job is, in one line: the command of the run, the stage, a
/// bar when its end is known (a spinner while not), and its detail. The
/// bottom panel's header and the status line show the same.
struct BuildProgress: View {
    @Environment(Console.self) private var console

    var body: some View {
        HStack(spacing: 8) {
            if let fraction = console.stage?.fraction {
                ProgressView(value: fraction).progressViewStyle(.linear).frame(width: 140)
                Text("\(Int((fraction * 100).rounded())) %").monospacedDigit().foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(title).lineLimit(1)
            if let detail = console.stage?.detail {
                Text(detail).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        let name = console.stage?.name ?? "Starting"
        return console.step.count > 1 ? "\(console.step.index) of \(console.step.count): \(name)" : name
    }
}
