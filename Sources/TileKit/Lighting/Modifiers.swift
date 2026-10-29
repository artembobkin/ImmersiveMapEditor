import Foundation

extension Lighting {
    /// One modifier of the light (the user, 2026-10-29: the light as a
    /// list of modifiers, each added to the preview, tuned there and then
    /// baked). Two families, by what a modifier acts on:
    ///
    /// - The light map, one texel at a time in plan: the sky light with its
    ///   bounces (`sky`), ambient occlusion within a radius (`ao`), the
    ///   creases along concave edges (`creases`), a sun baked in with its
    ///   shadows (`sun`). Their factors multiply into the one light map.
    /// - The faces, flat over each: the face shade by how shut in a face is
    ///   (`faceShade`), the palette's tones by the side a wall faces against
    ///   the sun (`sides`), and a Lambert light from a direction, the lamp of
    ///   the Landmarks view baked into the colours (`lambert`, as many as
    ///   wanted). Their factors multiply into each face's colour, which
    ///   takes a palette cell of its own for the result.
    ///
    /// A modifier is its kind, whether it is on, and its parameters by name.
    public struct Modifier: Equatable {
        public var kind: String
        public var on: Bool
        public var params: [String: Double]

        public init(kind: String, on: Bool = true, params: [String: Double] = [:]) {
            self.kind = kind
            self.on = on
            self.params = params
        }

        public subscript(_ key: String) -> Double {
            get { params[key] ?? Modifier.defaults(of: kind)[key] ?? 0 }
            set { params[key] = newValue }
        }

        /// The kinds, in the order the panel offers them: the name shown,
        /// and whether more than one may be in the stack.
        public static let kinds: [(kind: String, name: String, repeatable: Bool)] = [
            ("faceShade", "Face shade", false), ("creases", "Creases", false), ("sides", "Side tones", false),
            ("lambert", "Lambert light", true), ("sky", "Sky light", false), ("ao", "Ambient occlusion", false),
            ("sun", "Baked sun", false),
        ]

        public static func name(of kind: String) -> String { kinds.first { $0.kind == kind }?.name ?? kind }

        /// Each kind's parameters and their defaults.
        public static func defaults(of kind: String) -> [String: Double] {
            switch kind {
            case "faceShade": return ["reach": 10, "step": 0.10]
            case "creases": return ["width": 1.0, "depth": 0.6]
            case "sides": return [:]
            case "lambert": return ["from": 225, "height": 45, "strength": 0.38]
            case "sky": return ["strength": 0.6, "contrast": 1.6, "sky": 1.0, "bounces": 3]
            case "ao": return ["radius": 3, "depth": 0.5]
            case "sun": return ["from": 225, "height": 45, "strength": 1.0]
            default: return [:]
            }
        }

        public static func make(_ kind: String, on: Bool = true) -> Modifier { Modifier(kind: kind, on: on, params: defaults(of: kind)) }

        /// The stack a fresh tile or editor starts with (the user,
        /// 2026-10-29): the face shade, the creases, the side tones and a
        /// Lambert light on; the sky, ambient occlusion and a sun there but
        /// off, since the engine adds its own sun.
        public static let standard: [Modifier] = [
            make("faceShade"), make("creases"), make("sides"), make("lambert"),
            make("sky", on: false), make("ao", on: false), make("sun", on: false),
        ]

        public func json() -> [String: Any] { ["kind": kind, "on": on, "params": params] }

        public init?(json: [String: Any]) {
            guard let kind = json["kind"] as? String else { return nil }
            self.kind = kind
            on = json["on"] as? Bool ?? true
            params = (json["params"] as? [String: Double]) ?? [:]
            if let p = json["params"] as? [String: Any] {
                for (k, v) in p { if let d = (v as? NSNumber)?.doubleValue { params[k] = d } }
            }
        }

        /// A direction the light comes from, by a compass bearing and a
        /// height in degrees: a unit vector toward it (X east, Y north, Z up).
        public static func direction(from bearing: Double, height: Double) -> (Double, Double, Double) {
            let a = bearing * .pi / 180, e = height * .pi / 180
            return (sin(a) * cos(e), cos(a) * cos(e), sin(e))
        }
    }
}

extension Lighting.Settings {
    public func first(_ kind: String) -> Lighting.Modifier? { modifiers.first { $0.kind == kind } }
    public func isOn(_ kind: String) -> Bool { first(kind)?.on ?? false }
    /// The modifiers of a kind that are on.
    public func all(_ kind: String) -> [Lighting.Modifier] { modifiers.filter { $0.kind == kind && $0.on } }

    /// Sets a parameter of the first modifier of a kind, adding the
    /// modifier if the stack has none, and turns it on or off when asked.
    public mutating func set(_ kind: String, _ key: String? = nil, _ value: Double = 0, on: Bool? = nil) {
        if !modifiers.contains(where: { $0.kind == kind }) { modifiers.append(.make(kind, on: false)) }
        let i = modifiers.firstIndex { $0.kind == kind }!
        if let key { modifiers[i][key] = value }
        if let on { modifiers[i].on = on }
    }

    // The settings as they were before the stack, for the callers and the
    // options that still speak of them: each reads and writes the stack.
    public var depth: Double {
        get { isOn("sky") ? first("sky")!["strength"] : 0 }
        set { set("sky", "strength", newValue, on: newValue > 0) }
    }
    public var gamma: Double {
        get { first("sky")?["contrast"] ?? 1.6 }
        set { set("sky", "contrast", newValue) }
    }
    public var bounces: Int {
        get { Int(first("sky")?["bounces"] ?? 3) }
        set { set("sky", "bounces", Double(newValue)) }
    }
    public var skyStrength: Double {
        get { first("sky")?["sky"] ?? 1 }
        set { set("sky", "sky", newValue) }
    }
    /// "ao" when ambient occlusion is on and the sky is not, "sky" otherwise.
    public var mode: String {
        get { isOn("ao") && !isOn("sky") ? "ao" : "sky" }
        set {
            if newValue == "ao" { set("ao", on: true); set("sky", on: false) } else { set("sky", on: true); set("ao", on: false) }
        }
    }
    public var aoRadius: Double {
        get { first("ao")?["radius"] ?? 3 }
        set { set("ao", "radius", newValue) }
    }
    public var sun: Bool {
        get { isOn("sun") }
        set { set("sun", on: newValue) }
    }
    public var sunAzimuth: Double {
        get { first("sun")?["from"] ?? 225 }
        set { set("sun", "from", newValue) }
    }
    public var sunElevation: Double {
        get { first("sun")?["height"] ?? 45 }
        set { set("sun", "height", newValue) }
    }
    public var sunStrength: Double {
        get { first("sun")?["strength"] ?? 1 }
        set { set("sun", "strength", newValue) }
    }
    public var faceRadius: Double {
        get { isOn("faceShade") ? first("faceShade")!["reach"] : 0 }
        set { set("faceShade", "reach", newValue, on: newValue > 0) }
    }
    public var faceStep: Double {
        get { first("faceShade")?["step"] ?? 0.1 }
        set { set("faceShade", "step", newValue) }
    }
    public var creaseRadius: Double {
        get { isOn("creases") ? first("creases")!["width"] : 0 }
        set { set("creases", "width", newValue, on: newValue > 0) }
    }
    public var creaseDepth: Double {
        get { first("creases")?["depth"] ?? 0.6 }
        set { set("creases", "depth", newValue) }
    }
    public var sidedTones: Bool {
        get { isOn("sides") }
        set { set("sides", on: newValue) }
    }
}
