import SwiftUI

/// The one panel at the foot of the window, the same in every view: the
/// build's log, the pipeline's output following its end. A build opens it,
/// ⌘L, the toolbar or its close button hide it.
struct BottomPanel: View {
    @Environment(BuildRunner.self) private var runner

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Build", systemImage: "terminal") {
                if runner.running {
                    ProgressView().controlSize(.small)
                    Text("Running").foregroundStyle(.secondary)
                }
                Button("Hide", systemImage: "xmark") { runner.shown = false }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Hide the build log (⌘L)")
            }
            ScrollViewReader { reader in
                ScrollView {
                    Text(runner.log.isEmpty ? "No build yet. Tiles > Fetch and Build (⌘B)." : runner.log)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    Color.clear.frame(height: 1).id("end")
                }
                .onChange(of: runner.log, initial: true) { reader.scrollTo("end", anchor: .bottom) }
            }
        }
    }
}
