import AppKit
import SwiftUI

// The app's one door to AppKit, for what SwiftUI has no API for. Nothing
// outside this folder imports AppKit (CLAUDE.md, "How we work").

/// A Metal view in SwiftUI: the one kind of AppKit view the app keeps, for
/// what SwiftUI has no API for (its input). It takes the keyboard when shown.
struct MetalHost: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.needsDisplay = true
        Task { @MainActor in nsView.window?.makeFirstResponder(nsView) }
    }
}

/// A scroll wheel for a SwiftUI view: SwiftUI reads none, so a local event
/// monitor does while the cursor is over the view. The action gets the
/// wheel's step (up is positive, a notch about 1/6, a trackpad finer) and
/// where the cursor is in the view.
struct ScrollWheel: ViewModifier {
    let action: (Double, CGPoint) -> Void
    @State private var hover: CGPoint?
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                if case .active(let p) = phase { hover = p } else { hover = nil }
            }
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    guard let p = hover else { return event }
                    action(event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 100 : event.scrollingDeltaY / 6, p)
                    return nil
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

extension View {
    func onScrollWheel(_ action: @escaping (Double, CGPoint) -> Void) -> some View {
        modifier(ScrollWheel(action: action))
    }
}

enum Platform {
    /// Run without its app bundle (from the command line or Xcode), the
    /// executable has no activation policy of its own: it takes the regular
    /// one, a Dock icon and windows.
    @MainActor
    static func activateBareExecutable() {
        if Bundle.main.bundleIdentifier == nil { NSApplication.shared.setActivationPolicy(.regular) }
    }

    /// Runs `body` on the main actor and serves the main queue for good: the
    /// entry point of the executable, which must not be an `async` main. An
    /// async `@main` here emits its entry thunk under the same name as the
    /// test runner's (`async_Main`), and in an optimised build of the tests
    /// (`swift test -c release`) the linker keeps this module's copy, so the
    /// test process started the editor instead of the tests and waited for
    /// window events at no CPU.
    static func runMain(_ body: @escaping @MainActor () async -> Void) -> Never {
        Task { @MainActor in await body() }
        dispatchMain()
    }
}
