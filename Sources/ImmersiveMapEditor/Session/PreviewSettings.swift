import Foundation
import Observation

/// What the Preview keeps between runs: its camera's lens on a landmark
/// shown alone. Its light has nothing to set (`PreviewLight`).
@Observable
@MainActor
final class PreviewSettings {
    private static let lensKey = "light.lens"
    /// The preview camera's lens on a landmark alone: its vertical field of
    /// view in degrees, the engine's 45 by default. Narrow flattens the
    /// building like a telephoto, wide makes what is near loom.
    var lens: Double = UserDefaults.standard.object(forKey: lensKey) as? Double ?? 45 {
        didSet { UserDefaults.standard.set(lens, forKey: Self.lensKey) }
    }
}
