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
                    // A row a line, laid out only where in view (one text of
                    // the whole log, selectable, was laid out again at every
                    // change of the panel's height, the window frozen while
                    // it was dragged; the user, 2026-11-03).
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if console.lines.isEmpty {
                            Text("Nothing run on this yet. Tile > Build the Tile (⌘B), or Claude on a landmark.")
                        }
                        ForEach(console.lines.indices, id: \.self) { i in
                            Text(verbatim: console.lines[i].isEmpty ? " " : console.lines[i])
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(10)
                    Color.clear.frame(height: 1).id("end")
                }
                .onChange(of: console.lines.count, initial: true) { reader.scrollTo("end", anchor: .bottom) }
            }
        }
    }
}
