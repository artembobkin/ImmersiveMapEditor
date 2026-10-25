import SwiftUI

/// The window's one layout, the same in every view: the view's content
/// filling what is left, the console under it at a height of its own, and
/// the inspector on the right (ContentView's `.inspector`). The regions are
/// independent: a view fills them, never moves or sizes them, so an empty
/// view (a placeholder) leaves the console where it is.
struct WindowLayout<Main: View, Console: View>: View {
    let consoleShown: Bool
    @ViewBuilder var main: () -> Main
    @ViewBuilder var console: () -> Console
    /// The console's height, kept between runs, dragged by its top edge.
    @AppStorage("console.height") private var height = 220.0
    @State private var dragFrom: Double?

    var body: some View {
        VStack(spacing: 0) {
            main()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if consoleShown {
                resizer
                console()
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }
        }
    }

    /// The console's top edge: a line, with a band around it to drag.
    private var resizer: some View {
        Divider()
            .overlay {
                Color.clear
                    .frame(height: 9)
                    .contentShape(Rectangle())
                    .pointerStyle(.rowResize)
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global).onChanged { v in
                        if dragFrom == nil { dragFrom = height }
                        height = min(700, max(90, dragFrom! - v.translation.height))
                    }.onEnded { _ in dragFrom = nil })
            }
            .zIndex(1)
    }
}
