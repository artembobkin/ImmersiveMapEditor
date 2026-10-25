/// What an edge of the overlay graph is in each input: not a part of it, a
/// line, the boundary of an area (with its locations on the left and right
/// and whether it is of a hole) or a collapsed boundary, and its location
/// on the line once known: JTS's `OverlayLabel`. One label is shared by the
/// two half-edges of an edge, which read its sides by their direction.
public final class OverlayLabel {
    public static let dimUnknown = -1
    public static let dimNotPart = dimUnknown
    public static let dimLine = 1
    public static let dimBoundary = 2
    public static let dimCollapse = 3
    public static let locUnknown = Location.none

    @exclusivity(unchecked) var aDim = OverlayLabel.dimNotPart
    @exclusivity(unchecked) var aIsHole = false
    @exclusivity(unchecked) var aLocLeft = OverlayLabel.locUnknown
    @exclusivity(unchecked) var aLocRight = OverlayLabel.locUnknown
    @exclusivity(unchecked) var aLocLine = OverlayLabel.locUnknown
    @exclusivity(unchecked) var bDim = OverlayLabel.dimNotPart
    @exclusivity(unchecked) var bIsHole = false
    @exclusivity(unchecked) var bLocLeft = OverlayLabel.locUnknown
    @exclusivity(unchecked) var bLocRight = OverlayLabel.locUnknown
    @exclusivity(unchecked) var bLocLine = OverlayLabel.locUnknown

    public init() {}

    public func dimension(_ index: Int) -> Int { index == 0 ? aDim : bDim }

    public func initBoundary(_ index: Int, _ locLeft: Int, _ locRight: Int, _ isHole: Bool) {
        if index == 0 {
            aDim = OverlayLabel.dimBoundary
            aIsHole = isHole
            aLocLeft = locLeft
            aLocRight = locRight
            aLocLine = Location.interior
        } else {
            bDim = OverlayLabel.dimBoundary
            bIsHole = isHole
            bLocLeft = locLeft
            bLocRight = locRight
            bLocLine = Location.interior
        }
    }

    public func initCollapse(_ index: Int, _ isHole: Bool) {
        if index == 0 {
            aDim = OverlayLabel.dimCollapse
            aIsHole = isHole
        } else {
            bDim = OverlayLabel.dimCollapse
            bIsHole = isHole
        }
    }

    public func initLine(_ index: Int) {
        if index == 0 {
            aDim = OverlayLabel.dimLine
            aLocLine = OverlayLabel.locUnknown
        } else {
            bDim = OverlayLabel.dimLine
            bLocLine = OverlayLabel.locUnknown
        }
    }

    public func initNotPart(_ index: Int) {
        if index == 0 { aDim = OverlayLabel.dimNotPart } else { bDim = OverlayLabel.dimNotPart }
    }

    public func setLocationLine(_ index: Int, _ loc: Int) {
        if index == 0 { aLocLine = loc } else { bLocLine = loc }
    }

    public func setLocationAll(_ index: Int, _ loc: Int) {
        if index == 0 {
            aLocLine = loc
            aLocLeft = loc
            aLocRight = loc
        } else {
            bLocLine = loc
            bLocLeft = loc
            bLocRight = loc
        }
    }

    /// A collapsed edge of a hole is in the interior, of a shell outside.
    public func setLocationCollapse(_ index: Int) {
        let loc = isHole(index) ? Location.interior : Location.exterior
        if index == 0 { aLocLine = loc } else { bLocLine = loc }
    }

    public func isLine() -> Bool { aDim == OverlayLabel.dimLine || bDim == OverlayLabel.dimLine }
    public func isLine(_ index: Int) -> Bool { (index == 0 ? aDim : bDim) == OverlayLabel.dimLine }

    public func isLinear(_ index: Int) -> Bool {
        let d = index == 0 ? aDim : bDim
        return d == OverlayLabel.dimLine || d == OverlayLabel.dimCollapse
    }

    public func isKnown(_ index: Int) -> Bool { (index == 0 ? aDim : bDim) != OverlayLabel.dimUnknown }
    public func isNotPart(_ index: Int) -> Bool { (index == 0 ? aDim : bDim) == OverlayLabel.dimNotPart }
    public func isBoundaryEither() -> Bool { aDim == OverlayLabel.dimBoundary || bDim == OverlayLabel.dimBoundary }
    public func isBoundaryBoth() -> Bool { aDim == OverlayLabel.dimBoundary && bDim == OverlayLabel.dimBoundary }

    /// A boundary of one input that collapsed in the other (or in both).
    public func isBoundaryCollapse() -> Bool {
        if isLine() { return false }
        return !isBoundaryBoth()
    }

    /// Boundaries of both inputs touching, their areas on opposite sides.
    public func isBoundaryTouch() -> Bool {
        isBoundaryBoth() && getLocation(0, Position.right, true) != getLocation(1, Position.right, true)
    }

    public func isBoundary(_ index: Int) -> Bool { (index == 0 ? aDim : bDim) == OverlayLabel.dimBoundary }

    public func isBoundarySingleton() -> Bool {
        if aDim == OverlayLabel.dimBoundary && bDim == OverlayLabel.dimNotPart { return true }
        if bDim == OverlayLabel.dimBoundary && aDim == OverlayLabel.dimNotPart { return true }
        return false
    }

    public func isLineLocationUnknown(_ index: Int) -> Bool { (index == 0 ? aLocLine : bLocLine) == OverlayLabel.locUnknown }
    public func isLineInArea(_ index: Int) -> Bool { (index == 0 ? aLocLine : bLocLine) == Location.interior }
    public func isHole(_ index: Int) -> Bool { index == 0 ? aIsHole : bIsHole }
    public func isCollapse(_ index: Int) -> Bool { dimension(index) == OverlayLabel.dimCollapse }

    public func isInteriorCollapse() -> Bool {
        if aDim == OverlayLabel.dimCollapse && aLocLine == Location.interior { return true }
        if bDim == OverlayLabel.dimCollapse && bLocLine == Location.interior { return true }
        return false
    }

    public func isCollapseAndNotPartInterior() -> Bool {
        if aDim == OverlayLabel.dimCollapse && bDim == OverlayLabel.dimNotPart && bLocLine == Location.interior { return true }
        if bDim == OverlayLabel.dimCollapse && aDim == OverlayLabel.dimNotPart && aLocLine == Location.interior { return true }
        return false
    }

    public func getLineLocation(_ index: Int) -> Int { index == 0 ? aLocLine : bLocLine }
    public func isLineInterior(_ index: Int) -> Bool { (index == 0 ? aLocLine : bLocLine) == Location.interior }

    /// The location on a side, or on the line, as seen along or against the edge.
    public func getLocation(_ index: Int, _ position: Int, _ isForward: Bool) -> Int {
        if index == 0 {
            switch position {
            case Position.left: return isForward ? aLocLeft : aLocRight
            case Position.right: return isForward ? aLocRight : aLocLeft
            case Position.on: return aLocLine
            default: break
            }
        }
        switch position {
        case Position.left: return isForward ? bLocLeft : bLocRight
        case Position.right: return isForward ? bLocRight : bLocLeft
        case Position.on: return bLocLine
        default: return OverlayLabel.locUnknown
        }
    }

    public func getLocationBoundaryOrLine(_ index: Int, _ position: Int, _ isForward: Bool) -> Int {
        if isBoundary(index) { return getLocation(index, position, isForward) }
        return getLineLocation(index)
    }

    public func getLocation(_ index: Int) -> Int { index == 0 ? aLocLine : bLocLine }

    public func hasSides(_ index: Int) -> Bool {
        if index == 0 { return aLocLeft != OverlayLabel.locUnknown || aLocRight != OverlayLabel.locUnknown }
        return bLocLeft != OverlayLabel.locUnknown || bLocRight != OverlayLabel.locUnknown
    }

    public func copy() -> OverlayLabel {
        let l = OverlayLabel()
        l.aLocLeft = aLocLeft; l.aLocRight = aLocRight; l.aLocLine = aLocLine; l.aDim = aDim; l.aIsHole = aIsHole
        l.bLocLeft = bLocLeft; l.bLocRight = bLocRight; l.bLocLine = bLocLine; l.bDim = bDim; l.bIsHole = bIsHole
        return l
    }
}
