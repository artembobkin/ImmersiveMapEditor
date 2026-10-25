import Foundation
import Observation

/// Which of the window's panels show, the app's setting kept between runs,
/// changed in the View menu: the files on the left, the console at the
/// foot, the inspector on the right.
@Observable
@MainActor
final class PanelLayout {
    var files = PanelLayout.read("panels.files") { didSet { PanelLayout.write("panels.files", files) } }
    var console = PanelLayout.read("panels.console") { didSet { PanelLayout.write("panels.console", console) } }
    var inspector = PanelLayout.read("panels.inspector") { didSet { PanelLayout.write("panels.inspector", inspector) } }

    private static func read(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
    private static func write(_ key: String, _ value: Bool) { UserDefaults.standard.set(value, forKey: key) }
}
