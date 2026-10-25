/// A ring of a polygon being validated, with the rings of the same polygon
/// it touches: JTS's `PolygonRing`, used to find a disconnected interior
/// (a cycle of touching holes, or a self-touch of an inverted ring).
///
/// The touches are kept by the touched ring's index and visited in the
/// order of the indices, as GEOS 3.13 keeps them (an ordered map; JTS: a
/// `HashMap`, whose order for small integers is the same but for the shell,
/// index -1). The order decides only which disconnection point is reported.
final class PolygonRing {
    static func isShell(_ polyRing: PolygonRing?) -> Bool {
        guard let polyRing else { return true }
        return polyRing.isShell()
    }

    /// Records a touch between two rings at `pt`; true if the rings touch
    /// at another point already (a double touch, which disconnects the
    /// interior).
    static func addTouch(_ ring0: PolygonRing?, _ ring1: PolygonRing?, _ pt: Coordinate) -> Bool {
        //--- skip if either polygon does not have holes
        guard let ring0, let ring1 else { return false }
        //--- only record touches within a polygon
        if !ring0.isSamePolygon(ring1) { return false }
        if !ring0.isOnlyTouch(ring1, pt) { return true }
        if !ring1.isOnlyTouch(ring0, pt) { return true }
        ring0.addTouch(ring1, pt)
        ring1.addTouch(ring0, pt)
        return false
    }

    static func findHoleCycleLocation(_ polyRings: [PolygonRing]) -> Coordinate? {
        for polyRing in polyRings where !polyRing.isInTouchSet() {
            if let holeCycleLoc = polyRing.findHoleCycleLocation() { return holeCycleLoc }
        }
        return nil
    }

    static func findInteriorSelfNode(_ polyRings: [PolygonRing]) -> Coordinate? {
        for polyRing in polyRings {
            if let interiorSelfNode = polyRing.findInteriorSelfNode() { return interiorSelfNode }
        }
        return nil
    }

    let id: Int
    /// The shell of the ring's polygon (itself for a shell); unowned, as
    /// the analyzer keeps every ring.
    @exclusivity(unchecked) unowned(unsafe) var shell: PolygonRing!
    let ring: LinearRing
    @exclusivity(unchecked) var touchSetRoot: PolygonRing?
    @exclusivity(unchecked) var touches: [Int: PolygonRingTouch] = [:]
    @exclusivity(unchecked) var selfNodes: [PolygonRingSelfNode] = []

    /// A shell.
    init(_ ring: LinearRing) {
        self.ring = ring
        id = -1
        shell = nil
        shell = self
    }

    /// A hole of the polygon of `shell`.
    init(_ ring: LinearRing, _ index: Int, _ shell: PolygonRing?) {
        self.ring = ring
        id = index
        self.shell = shell
    }

    func isSamePolygon(_ ring: PolygonRing) -> Bool { shell === ring.shell }
    func isShell() -> Bool { shell === self }
    func isInTouchSet() -> Bool { touchSetRoot != nil }
    func hasTouches() -> Bool { !touches.isEmpty }

    /// The touches in the order of the touched rings' indices.
    func getTouches() -> [PolygonRingTouch] { touches.keys.sorted().map { touches[$0]! } }

    func addTouch(_ ring: PolygonRing, _ pt: Coordinate) {
        if touches[ring.id] == nil { touches[ring.id] = PolygonRingTouch(ring, pt) }
    }

    func addSelfTouch(_ origin: Coordinate, _ e00: Coordinate, _ e01: Coordinate, _ e10: Coordinate, _ e11: Coordinate) {
        selfNodes.append(PolygonRingSelfNode(origin, e00, e01, e10, e11))
    }

    func isOnlyTouch(_ ring: PolygonRing, _ pt: Coordinate) -> Bool {
        //--- no touches for this ring
        if touches.isEmpty { return true }
        //--- no touches for other ring
        guard let touch = touches[ring.id] else { return true }
        //--- the rings touch - check if point is the same
        return touch.isAtLocation(pt)
    }

    func findHoleCycleLocation() -> Coordinate? {
        //--- the touch set including this ring is already processed
        if isInTouchSet() { return nil }
        //--- scan the touch set tree rooted at this ring
        let root = self
        root.touchSetRoot = root
        if !hasTouches() { return nil }
        var touchStack: [PolygonRingTouch] = []
        PolygonRing.initStack(root, &touchStack)
        while let touch = touchStack.popLast() {
            if let holeCyclePt = scanForHoleCycle(touch, root, &touchStack) { return holeCyclePt }
        }
        return nil
    }

    static func initStack(_ root: PolygonRing, _ touchStack: inout [PolygonRingTouch]) {
        for touch in root.getTouches() {
            touch.ring.touchSetRoot = root
            touchStack.append(touch)
        }
    }

    func scanForHoleCycle(_ currentTouch: PolygonRingTouch, _ root: PolygonRing, _ touchStack: inout [PolygonRingTouch]) -> Coordinate? {
        let ring = currentTouch.ring
        let currentPt = currentTouch.coordinate
        // Either the touched rings form a hole cycle, or they are added to
        // the touch set and pushed on the stack for scanning.
        for touch in ring.getTouches() {
            // Touches at the entry point are skipped, to avoid trivial cycles.
            if currentPt.equals2D(touch.coordinate) { continue }
            // A ring reached already by another path closes a hole cycle.
            let touchRing = touch.ring
            if touchRing.touchSetRoot === root { return touch.coordinate }
            touchRing.touchSetRoot = root
            touchStack.append(touch)
        }
        return nil
    }

    func findInteriorSelfNode() -> Coordinate? {
        if selfNodes.isEmpty { return nil }
        // The interior is on the right for a clockwise shell or a
        // counter-clockwise hole.
        let isCCW = Orientation.isCCW(ring.points)
        let isInteriorOnRight = isShell() != isCCW
        for selfNode in selfNodes where !selfNode.isExterior(isInteriorOnRight) { return selfNode.nodePt }
        return nil
    }
}

/// A touch of a ring at a point: JTS's `PolygonRingTouch`.
final class PolygonRingTouch {
    let ring: PolygonRing
    let coordinate: Coordinate

    init(_ ring: PolygonRing, _ pt: Coordinate) {
        self.ring = ring
        coordinate = pt
    }

    func isAtLocation(_ pt: Coordinate) -> Bool { coordinate.equals2D(pt) }
}

/// A point where a ring touches itself, with the edges at it: JTS's
/// `PolygonRingSelfNode`.
struct PolygonRingSelfNode {
    let nodePt: Coordinate
    let e00: Coordinate
    let e01: Coordinate
    let e10: Coordinate

    init(_ nodePt: Coordinate, _ e00: Coordinate, _ e01: Coordinate, _ e10: Coordinate, _ e11: Coordinate) {
        self.nodePt = nodePt
        self.e00 = e00
        self.e01 = e01
        self.e10 = e10
    }

    /// Whether the node is exterior to the ring's interior: the touching
    /// edge does not lie in the interior corner of the other.
    func isExterior(_ isInteriorOnRight: Bool) -> Bool {
        let isInteriorSeg = PolygonNodeTopology.isInteriorSegment(nodePt, e00, e01, e10)
        return isInteriorOnRight ? !isInteriorSeg : isInteriorSeg
    }
}
