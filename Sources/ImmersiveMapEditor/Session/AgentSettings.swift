import Foundation

/// What the landmarks' agent is asked for, set in the landmark's panel and
/// written into the prompt and the modelling tools' environment when the
/// prompt is copied (the agent itself is run by the user in a terminal,
/// since 2026-11-20): the detail, the distinctive details and how much
/// larger than life they are drawn, and Mapillary's token, which the tools
/// read from the keychain.
enum AgentSettings {
    /// How much of a landmark the agent models (the user, 2026-11-05: the
    /// Painted Ladies came out as plain gabled boxes, and the ornament is
    /// the building): "normal", everything that reads from across the
    /// street, or "fine", the ornament too, with five fix builds.
    static let detailKey = "landmark.detail"
    static let details: [(id: String, title: String)] = [("normal", "Normal"), ("fine", "Fine")]
    static var detail: String {
        let v = UserDefaults.standard.string(forKey: detailKey) ?? "normal"
        return details.contains { $0.id == v } ? v : "normal"
    }
    static var fine: Bool { detail == "fine" }

    /// How the agent finds the one or two things that make the building
    /// recognisable, for the generator to draw a size up (the user,
    /// 2026-10-28): "known" from what it knows of the place alone (a
    /// photo only if it wants one), "photos" from what it knows and, for a
    /// building it does not know, the roof and corners of the
    /// whole-building photo, or "off" for a plain building.
    static let emphasisKey = "landmark.emphasis"
    static var emphasis: String {
        let v = UserDefaults.standard.string(forKey: emphasisKey) ?? "photos"
        return ["off", "known", "photos"].contains(v) ? v : "photos"
    }

    /// How much larger than life a distinctive detail is drawn (1 is its
    /// real size); the generator reads it as LANDMARK_EMPHASIS.
    static let exaggerationKey = "landmark.exaggeration"
    static var exaggeration: Double {
        let v = UserDefaults.standard.object(forKey: exaggerationKey) as? Double ?? 3
        return min(5, max(1, v))
    }
    /// The generator's environment for the editor's settings.
    static var generatorEnvironment: [String: String] { ["LANDMARK_EMPHASIS": String(format: "%.2f", exaggeration)] }

    /// Mapillary's access token (its street-level photos, CC BY-SA, are the
    /// landmarks' agent's references), in the keychain.
    static var mapillaryToken: String {
        get { Keychain.read("mapillary.token") ?? "" }
        set { Keychain.write("mapillary.token", newValue) }
    }
}
