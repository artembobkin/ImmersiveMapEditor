/// osm2lanes's positions within a road's width (`RoadPosition`, `LtrLaneNum`)
/// and the `placement` tag that sets where the OSM way is drawn.

import StreetGeom

/// A lane by its left-to-right position among the lanes of one direction.
public enum LtrLaneNum: Equatable, Sendable {
    case forward(Int)
    case backward(Int)

    public func direction() -> Direction {
        if case .forward = self { return .forward }
        return .backward
    }

    public func number() -> Int {
        switch self {
        case .forward(let n), .backward(let n): return n
        }
    }

    public func reverse() -> LtrLaneNum {
        switch self {
        case .forward(let n): return .backward(n)
        case .backward(let n): return .forward(n)
        }
    }
}

public enum RoadPosition: Equatable, Sendable {
    /// The center of the carriageway. The default placement of OSM ways.
    case center
    /// The center of the full width, verges and footpaths included.
    case fullWidthCenter
    /// The center of the separation between both directions of traffic.
    case separation
    case leftOf(LtrLaneNum)
    case middleOf(LtrLaneNum)
    case rightOf(LtrLaneNum)

    public func reverse() -> RoadPosition {
        switch self {
        case .center, .fullWidthCenter, .separation: return self
        case .leftOf(let n): return .leftOf(n.reverse())
        case .middleOf(let n): return .middleOf(n.reverse())
        case .rightOf(let n): return .rightOf(n.reverse())
        }
    }

    /// A position from a `placement` tag value, read as forward.
    public static func parse(_ value: String) throws -> RoadPosition {
        switch value {
        case "": return .center
        case "separation": return .separation
        default:
            guard let colon = value.firstIndex(of: ":") else { throw GeomError.message("unknown placement value: \(value)") }
            let kind = String(value[..<colon])
            let laneStr = String(value[value.index(after: colon)...])
            guard let lane = parseUsize(laneStr) else { throw GeomError.message("bad lane number: \(laneStr)") }
            switch kind {
            case "left_of": return .leftOf(.forward(lane))
            case "middle_of": return .middleOf(.forward(lane))
            case "right_of": return .rightOf(.forward(lane))
            default: throw GeomError.message("unknown lane position specifier: \(kind)")
            }
        }
    }
}

/// Rust's `str::parse::<usize>`: ASCII digits with an optional `+`.
func parseUsize(_ s: String) -> Int? {
    var t = Substring(s)
    if t.hasPrefix("+") { t = t.dropFirst() }
    guard !t.isEmpty, t.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
    return Int(t)
}

public enum Placement: Equatable, Sendable {
    case consistent(RoadPosition)
    case varying(RoadPosition, RoadPosition)
    case transition

    /// The first interpretation of the `placement` tags found.
    public static func parse(_ tags: Tags) throws -> Placement {
        func pos(_ key: String) throws -> RoadPosition { try RoadPosition.parse(tags.get(key) ?? "") }
        if let v = tags.get("placement") {
            return v == "transition" ? .transition : .consistent(try RoadPosition.parse(v))
        } else if tags.hasAny(["placement:start", "placement:end"]) {
            return .varying(try pos("placement:start"), try pos("placement:end"))
        } else if let v = tags.get("placement:forward") {
            return .consistent(try RoadPosition.parse(v))
        } else if tags.hasAny(["placement:forward:start", "placement:forward:end"]) {
            return .varying(try pos("placement:forward:start"), try pos("placement:forward:end"))
        } else if let v = tags.get("placement:backward") {
            return .consistent(try RoadPosition.parse(v).reverse())
        } else if tags.hasAny(["placement:backward:start", "placement:backward:end"]) {
            return .varying(try pos("placement:backward:start").reverse(), try pos("placement:backward:end").reverse())
        }
        return .consistent(.center)
    }
}
