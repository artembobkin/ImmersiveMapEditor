import SwiftUI

/// The Build window: the pipeline's output, following its end.
struct BuildLogView: View {
    @Environment(BuildRunner.self) private var runner

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                Text(runner.log.isEmpty ? "No build yet. Tiles > Fetch and Build (⌘B)." : runner.log)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                Color.clear.frame(height: 1).id("end")
            }
            .onChange(of: runner.log) { reader.scrollTo("end", anchor: .bottom) }
        }
        .frame(minWidth: 600, minHeight: 300)
        .toolbar {
            if runner.running { ProgressView().controlSize(.small) }
        }
    }
}
