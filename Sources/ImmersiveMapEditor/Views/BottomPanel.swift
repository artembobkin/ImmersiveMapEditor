import SwiftUI

/// The one panel at the foot of the window, the same in every view: the
/// console of the job of what the window shows (`Session.console`: the
/// landmark open, else the tile), its log following its end. Shown or hidden
/// in the View menu (⌘L).
struct BottomPanel: View {
    @Environment(Session.self) private var session
    @Environment(Console.self) private var console

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: session.consoleTitle, systemImage: "terminal") {
                if console.running { BuildProgress() }
            }
            ScrollViewReader { reader in
                ScrollView {
                    Text(console.log.isEmpty ? "Nothing run on this yet. Tile > Build the Tile (⌘B), or Claude on a landmark." : console.log)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    Color.clear.frame(height: 1).id("end")
                }
                .onChange(of: console.log, initial: true) { reader.scrollTo("end", anchor: .bottom) }
            }
        }
    }
}
