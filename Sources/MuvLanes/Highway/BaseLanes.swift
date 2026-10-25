/// muv-osm's `BaseLanes` (`lanes/highway/base.rs`): the core lanes of a way
/// (its carriageway, or a sidewalk's or cycleway's own lanes): the default
/// access of its class, the legal speeds, then the lanes of each direction
/// by `lanes`, `lanes:forward`, `lanes:both_ways` and the per-lane keys,
/// glued into one list from left to right with the centre line and the OSM
/// line's placement, a segregated foot lane, and widths shared out.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

struct BaseLanes<T: Taglike> {
    let regions: [String]
    let drivingSide: Side
    let tags: T
    let isSidepath: Bool
    let returnCenter: Bool
    let segregated: Bool?
    let cls: HighwayClassification?
    let oneway: Oneway
    let onewayVehicle: OnewayDirection?
    let platform: Bool
    let hasSidewalk: Bool
    let buswayForward: UInt8
    let buswayBackward: UInt8

    /// `BaseLanes::add`: appends the lanes and returns (centre line, centre) relative to the start.
    func add(_ lanes: inout [Lane]) -> (UInt8, UInt8) {
        var access = cls.map { c in c.defaultAccess(regions, tags, tags.getValue("motorroad") == "yes") }
            ?? HighwayAccess.highway()
        if hasSidewalk { access.set(.foot, Conditional(AccessLevel.useSidepath)) }

        var lane = Lane.travelWrap(.withAccess(access))
        lane.isSidepath = isSidepath || (cls == .footway && tags.getValue("footway") == "sidewalk")
            || tags.getValue("is_sidepath") == "yes"

        var maxspeedDefault: TModes<Conditional<Quantity<WalkSpeed>>>?
        if let (minspeed, maxspeed) = cls.flatMap({ $0.defaultSpeed(regions) }) {
            lane.travel.minspeed = minspeed
            maxspeedDefault = maxspeed
        }

        let lanesStart = lanes.count
        var segregatedIndex: Int?
        if segregated == true && forwardOn(onewayVehicle, drivingSide, .left) {
            segregatedIndex = lanes.count
            lanes.append(Lane(TravelLane.both(.defaultEmpty())))
        }
        let segregatedLen: UInt8 = segregated == true ? 1 : 0

        let lanesTag = tags.get("lanes")
        let lanesCount = lanesTag?.value.flatMap(rustParseU8)

        let oneLanes = parseDirection(lane, lanesCount ?? 0, tags, false, platform, { $0 }) { maxspeedDefault }

        let placementTags = tags.get("placement")

        switch oneLanes {
        case .all(let l, _, _):
            lane = l
        case .individual:
            var one = oneLanes
            let (everForward, everBackward) = everAllowedOneway(oneway)
            one.mutEach { $0.travelWrapBuild(everForward, everBackward) }
            addOnewayDirection(oneway, &one, true)
            addOnewayDirection(oneway, &one, false)
            if let segregated { applySegregated(&lanes, lanesStart, segregatedIndex, segregated) }
            let lanesLen = one.extendVec(&lanes) &+ segregatedLen
            let center = returnCenter ? placementTags?.value.flatMap(Placement.fromOsmStr)?.centerIndex : nil
            return (lanesLen, center ?? lanesLen)
        }

        let bothWaysCount = lanesTag?.getValue("both_ways").flatMap(rustParseU8) ?? 0
        var bothWays = parseDirection(lane, bothWaysCount, tags, false, platform, { $0.get("both_ways") }) {
            maxspeedDefault
        }

        let clonedLane: Lane
        if case .all(var bothWaysLane, _, let dirty) = bothWays {
            if bothWaysCount == 0
                && (tags.getValue("centre_turn_lane") ?? tags.getValue("center_turn_lane")) == "yes" {
                bothWaysLane.travel.turn.set(.all, Conditional(Turn.normal(!drivingSide)))
                bothWays = .all(bothWaysLane, 1, true)
                clonedLane = lane
            } else if !dirty && bothWaysCount == 0 {
                bothWays = .individual([])
                clonedLane = bothWaysLane
            } else {
                bothWays = .all(bothWaysLane, bothWaysCount, dirty)
                clonedLane = lane
            }
        } else {
            clonedLane = lane
        }

        let forwardCount = lanesTag?.getValue("forward").flatMap(rustParseU8)
        let backwardCount = lanesTag?.getValue("backward").flatMap(rustParseU8)

        var merge = !(onewayVehicle == nil || onewayVehicle == .both)

        let fwd: UInt8, bwd: UInt8
        switch (lanesCount, forwardCount, backwardCount) {
        case (_, .some(let f), .some(let b)):
            if onewayVehicle != .reversible { merge = false }
            (fwd, bwd) = (f, b)
        case (.some(let l), .some(let f), nil):
            (fwd, bwd) = (f, l.sub(f).sub(buswayForward).sub(bothWaysCount))
        case (.some(let l), nil, .some(let b)):
            (fwd, bwd) = (l.sub(b).sub(buswayBackward).sub(bothWaysCount), b)
        case (.some(let l), nil, nil) where merge && bothWaysCount == 0:
            let n = l.sub(buswayForward).sub(buswayBackward)
            (fwd, bwd) = (n, n)
        case (let l, nil, nil):
            let n: UInt8
            if let l {
                n = l.sub(buswayForward).sub(buswayBackward).sub(bothWaysCount)
            } else if ["forward", "backward"].contains(tags.getValue("priority") ?? "") {
                n = 1
            } else {
                n = 2
            }
            let direction = n / 2
            if n == 1 { merge = true }
            (fwd, bwd) = (direction &+ (n & 1), max(direction, 1))
        case (nil, let f, let b):
            (fwd, bwd) = (f ?? 1, b ?? 1)
        }

        var forward = parseDirection(clonedLane, fwd, tags, false, platform, { $0.get("forward") }) { maxspeedDefault }
        var defaultTaken = maxspeedDefault
        var backward = parseDirection(lane, bwd, tags, true, platform, { $0.get("backward") }) {
            let d = defaultTaken
            defaultTaken = nil
            return d
        }

        let centreLine: UInt8, centre: UInt8
        if merge && forward.len == backward.len && bothWays.len == 0 {
            var allLanes = glueParseDirectionLanes(forward, backward)
            addOnewayDirection(oneway, &allLanes, true)
            addOnewayDirection(oneway, &allLanes, false)
            let c = allLanes.extendVec(&lanes) &+ segregatedLen
            (centreLine, centre) = (c, c)
        } else {
            forward.mutEach { $0.travelWrapBuild(true, false) }
            bothWays.mutEach { $0.travelWrapBuild(true, true) }
            backward.mutEach { $0.travelWrapBuild(false, true) }
            addOnewayDirection(oneway, &forward, true)
            addOnewayDirection(oneway, &backward, false)
            let (left, right) = drivingSide == .left ? (forward, backward) : (backward, forward)
            let leftLen = left.extendVec(&lanes)
            let bothWaysLen = bothWays.extendVec(&lanes)
            let rightLen = right.extendVec(&lanes)
            centreLine = leftLen &* 2 &+ bothWaysLen
            centre = returnCenter
                ? twoWayPlacement(placementTags, drivingSide, leftLen, bothWaysLen, rightLen)
                : centreLine
        }

        if let segregated { applySegregated(&lanes, lanesStart, segregatedIndex, segregated) }

        if isSidepath, let width = tags.getValue("width").flatMap({ Quantity<Distance>.fromOsmStr($0) }) {
            distributeFullWidth(&lanes, from: lanesStart, width)
        }
        return (centreLine, centre)
    }

    private func applySegregated(_ lanes: inout [Lane], _ start: Int, _ segregatedIndex: Int?, _ segregated: Bool) {
        if segregated {
            addSegregated(&lanes, start, segregatedIndex)
        } else {
            for i in start..<lanes.count {
                guard case .travel(var t) = lanes[i].variant else { continue }
                t.forward.access.set(.foot, Conditional(AccessLevel.yes))
                t.backward.access.set(.foot, Conditional(AccessLevel.yes))
                lanes[i].variant = .travel(t)
            }
        }
    }

    /// `BaseLanes::add_segregated`: foot taken off the lanes onto a lane of its own.
    private func addSegregated(_ lanes: inout [Lane], _ start: Int, _ segregatedIndex: Int?) {
        var forward: Conditional<AccessLevel>?
        var backward: Conditional<AccessLevel>?
        var sidepath = false
        for i in start..<lanes.count {
            guard case .travel(var t) = lanes[i].variant else { continue }
            forward = t.forward.access.set(.foot, Conditional(AccessLevel.no)) ?? forward
            backward = t.backward.access.set(.foot, Conditional(AccessLevel.no)) ?? backward
            lanes[i].variant = .travel(t)
            sidepath = sidepath || lanes[i].isSidepath
        }
        if forward == Conditional(AccessLevel.no) { forward = nil }
        if backward == Conditional(AccessLevel.no) { backward = nil }
        let f = TravelLaneDirection.withAccess(TModes([(.all, Conditional(AccessLevel.no)),
                                                       (.foot, forward ?? Conditional(AccessLevel.yes))]))
        let b = TravelLaneDirection.withAccess(TModes([(.all, Conditional(AccessLevel.no)),
                                                       (.foot, backward ?? Conditional(AccessLevel.yes))]))
        var lane = Lane(TravelLane(forward: f, backward: b))
        lane.isSidepath = sidepath
        if let footway = tags.get("footway") { lane = lane.addParse(footway) }
        if let segregatedIndex {
            lanes[segregatedIndex] = lane
        } else {
            lanes.append(lane)
        }
    }
}

extension UInt8 {
    /// `saturating_sub`.
    func sub(_ o: UInt8) -> UInt8 { self > o ? self - o : 0 }
}

/// `get_two_way_placement`.
private func twoWayPlacement<T: Taglike>(_ tags: T?, _ drivingSide: Side, _ leftLen: UInt8, _ bothWaysLen: UInt8,
                                         _ rightLen: UInt8) -> UInt8 {
    if let center = tags?.getValue("forward").flatMap(Placement.fromOsmStr)?.centerIndex {
        switch drivingSide {
        case .left:
            if (leftLen &+ bothWaysLen &+ rightLen) &* 2 >= center { return center }
        case .right:
            if leftLen &* 2 >= center { return (rightLen &+ bothWaysLen) &* 2 &+ center }
        }
    }
    if let center = tags?.getValue("backward").flatMap(Placement.fromOsmStr)?.centerIndex {
        let middle = drivingSide == .left ? leftLen &+ bothWaysLen &+ rightLen : leftLen
        let (r, overflow) = (middle &* 2).subtractingReportingOverflow(center)
        if !overflow { return r }
    }
    return leftLen &* 2 &+ bothWaysLen
}

/// `glue_parse_direction_lanes`: the forward and backward lanes as lanes of
/// both directions, when they pair up.
private func glueParseDirectionLanes(_ forward: ParseDirectionLanes, _ backward: ParseDirectionLanes) -> ParseDirectionLanes {
    switch (forward, backward) {
    case (.all(var f, let count, _), .all(let b, _, _)):
        f.travelLane.backward = b.travelLane.forward
        return .all(f, count, false)
    case (.individual(var fs), .all(let b, _, _)):
        let back = b.travelLane.forward
        for i in fs.indices { fs[i].travelLane.backward = back }
        return .individual(fs)
    case (.all(let f, _, _), .individual(var bs)):
        let fwd = f.travelLane.forward
        for i in bs.indices {
            var t = bs[i].travelLane
            t.backward = t.forward
            t.forward = fwd
            bs[i].travelLane = t
        }
        return .individual(bs)
    case (.individual(var fs), .individual(let bs)):
        for (i, b) in zip(fs.indices, bs.reversed()) { fs[i].travelLane.backward = b.travelLane.forward }
        return .individual(fs)
    }
}

/// `ever_allowed`: whether the mode is ever allowed either way.
private func everAllowed(_ t: TravelLane, _ mode: TMode) -> Bool {
    (t.forward.access.get(mode)?.restrictions.contains { $0.value != .no } ?? false)
        || (t.backward.access.get(mode)?.restrictions.contains { $0.value != .no } ?? false)
}

/// `distribute_full_width`: the width left over after the lanes with a
/// width shared among the others by weight (a motor lane 2, any other
/// travel lane 1, parallel parking 2, other parking 4).
func distributeFullWidth(_ lanes: inout [Lane], from start: Int, _ fullWidthIn: Quantity<Distance>) {
    var fullWidth = fullWidthIn
    var weights: [UInt16] = []
    for lane in lanes[start...] {
        if let w = lane.width {
            fullWidth = fullWidth - w
            continue
        }
        switch lane.variant {
        case .travel(let t):
            weights.append(everAllowed(t, .motorcar) || everAllowed(t, .bus) || everAllowed(t, .taxi) ? 2 : 1)
        case .parking(let p):
            weights.append(p.orientation == nil || p.orientation == .parallel ? 2 : 4)
        }
    }
    let fullWeights = Number(weights.reduce(UInt16(0), &+))
    var k = 0
    for i in start..<lanes.count where lanes[i].width == nil {
        guard k < weights.count else { break }
        lanes[i].width = fullWidth * Number(weights[k]) / fullWeights
        k += 1
    }
}
