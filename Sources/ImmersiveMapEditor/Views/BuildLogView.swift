import SwiftUI

/// The build's log at the foot of the window: the pipeline's output,
/// following its end. A build opens it, ⌘L or its close button hides it.
struct BuildLogView: View {
    @Environment(BuildRunner.self) private var runner

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Build").font(.headline)
                if runner.running {
                    ProgressView().controlSize(.small)
                    Text("Running").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Hide", systemImage: "xmark") { runner.shown = false }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Hide the build log (⌘L)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.bar)
            Divider()
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
