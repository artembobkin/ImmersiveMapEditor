/// muv-osm's reading of one direction of a road (`lanes/travel.rs`):
/// `ParseDirectionLanes`, either one lane repeated (with its count, and
/// whether anything was set on it) or each lane on its own. `AllParser`,
/// what applies to every lane of the direction (`maxspeed:forward`), and
/// `IndividualParser`, what is given per lane (`turn:lanes:forward`), which
/// splits the repeated lane into lanes when the counts agree.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

enum ParseDirectionLanes {
    /// One lane, its count, and whether it was changed.
    case all(Lane, UInt8, Bool)
    case individual([Lane])

    /// `ParseDirectionLanes::mut_each`.
    mutating func mutEach(_ f: (inout Lane) -> Void) {
        switch self {
        case .all(var lane, let count, _):
            f(&lane)
            self = .all(lane, count, true)
        case .individual(var lanes):
            for i in lanes.indices { f(&lanes[i]) }
            self = .individual(lanes)
        }
    }

    /// `ParseDirectionLanes::len`.
    var len: UInt8 {
        switch self {
        case .all(_, let count, _): return count
        case .individual(let lanes): return UInt8(lanes.count)
        }
    }

    /// `ParseDirectionLanes::extend_vec`: appended, up to `MAX_LANES` in all, and how many.
    func extendVec(_ vec: inout [Lane]) -> UInt8 {
        let limit = UInt8(max(0, Int(maxLanes) - vec.count))
        switch self {
        case .all(let lane, let count, _):
            let n = min(count, limit)
            for _ in 0..<n { vec.append(lane) }
            return n
        case .individual(let lanes):
            if lanes.count <= Int(limit) {
                vec.append(contentsOf: lanes)
                return UInt8(lanes.count)
            }
            vec.append(contentsOf: lanes.prefix(Int(limit)))
            return limit
        }
    }
}

/// `allowed_on_platform`: neither the children of `psv` nor the rail modes.
func allowedOnPlatform(_ mode: TMode) -> Bool {
    switch mode {
    case .bus, .taxi, .minibus, .shareTaxi, .schoolBus, .truckBus,
         .train, .monorail, .funicular, .lightRail, .subway, .tram:
        return false
    default:
        return true
    }
}

/// `AllParser`: tags that hold for the whole direction.
struct AllParser<Tl: Taglike> {
    var dirty = false
    let direction: (Tl) -> Tl?

    /// `AllParser::mode`.
    mutating func mode<T>(_ tags: Tl, _ value: inout TModes<Conditional<T>>, _ mode: TMode, _ parse: (String) -> T?) {
        guard let t = direction(tags), let val = Conditional.parseWith(t, parse) else { return }
        value.set(mode, val)
        dirty = true
    }

    /// `AllParser::access`: the general access merged into every mode's
    /// default (a `no` default or a general `yes` keeps the default), then
    /// each mode's own access.
    mutating func access(_ tagsAccess: Tl?, _ tags: Tl, _ platform: Bool, _ value: inout TModes<Conditional<AccessLevel>>) {
        if let ta = tagsAccess, let d = direction(ta), let access = Conditional<AccessLevel>.fromOsm(d, AccessLevel.fromOsmStr) {
            value.modifyEach { _, accessDefault in
                accessDefault = accessDefault.merge(access) { def, global in
                    (def == .no || global == .yes) ? def : global
                }
            }
        }
        for (mode, t) in TMode.iterTags(tags) where !platform || allowedOnPlatform(mode) {
            self.mode(t, &value, mode, AccessLevel.fromOsmStr)
        }
    }

    /// `AllParser::with_parse`.
    mutating func withParse<T>(_ tags: Tl?, _ value: inout TModes<Conditional<T>>, _ parse: (String) -> T?) {
        guard let tags else { return }
        for (mode, t) in TMode.iterTagsWithAll(tags) { self.mode(t, &value, mode, parse) }
    }

    /// `AllParser::maxspeed`: the legal speeds of a `maxspeed:type`-like
    /// value such as `RU:urban`.
    mutating func maxspeed(_ tags: Tl?, _ travel: inout TravelLaneDirection) {
        guard let tags, let d = direction(tags), let v = d.value, let (country, cls) = v.rustSplitOnce(":"),
              let (_, legal) = SpeedDefault.lookup(country, cls) else { return }
        maxspeedWithData(legal, &travel)
    }

    /// `AllParser::maxspeed_with_data`: the legal speeds merged into what
    /// the tags give, a mode's own lower base speed winning.
    mutating func maxspeedWithData(_ legal: TModes<Conditional<Quantity<WalkSpeed>>>, _ travel: inout TravelLaneDirection) {
        for (mode, legalValueIn) in legal.entries {
            var legalValue = legalValueIn
            let legalBase = legalValue.base
            var parentBase: Quantity<WalkSpeed>?
            for m in mode.iterHierarchy().dropFirst() {
                if let b = travel.maxspeed.getRaw(m)?.base {
                    parentBase = b
                    break
                }
            }
            let selfValue = travel.maxspeed.getRaw(mode)
            let selfBase = selfValue?.base
            let hasNewBase = selfBase == nil && legalBase.map { lb in
                parentBase.map { pb in Quantity.partialCompare(pb, lb) == 1 } ?? true
            } == true

            if let sv = selfValue {
                let hasSelfConditionals = sv.count != (selfBase != nil ? 1 : 0)
                if hasSelfConditionals {
                    if hasNewBase {
                        travel.maxspeed.modifyRaw(mode) { $0.restrictions.insert(legalValue.restrictions[0], at: 0) }
                        dirty = true
                    }
                    continue
                }
            }

            let newBase = hasNewBase ? legalBase != nil : selfBase != nil
            let base = hasNewBase ? legalBase : (selfBase ?? parentBase)

            if let base {
                legalValue.restrictions.removeAll { legalR in
                    !(legalR.conditions.isEmpty ? newBase : Quantity.partialCompare(base, legalR.value) == 1)
                }
                if let selfBase {
                    if legalBase != nil {
                        legalValue.restrictions[0].value = selfBase
                    } else {
                        legalValue.restrictions.insert(Restriction(value: selfBase, conditions: []), at: 0)
                    }
                }
            }

            if legalValue.isEmpty {
                if selfValue != nil {
                    dirty = true
                    travel.maxspeed.remove(mode)
                }
            } else {
                travel.maxspeed.set(mode, legalValue)
                dirty = true
            }
        }
    }
}

/// `IndividualParser`: tags given per lane of the direction.
struct IndividualParser<Tl: Taglike> {
    var lanes: ParseDirectionLanes
    let lanesReversed: Bool
    let direction: (Tl) -> Tl?

    /// `IndividualParser::with_lanes`: the lanes as a list of `count` (at
    /// most `MAX_DIRECTION_LANES`) to change, or nothing done when they are
    /// already a list of another count.
    mutating func withLanes(_ count: Int?, _ modify: (inout [Lane], Bool) -> Void) {
        let count = count.map { min($0, Int(maxDirectionLanes)) }
        var list: [Lane]
        switch lanes {
        case .all(let lane, let baseCount, _):
            list = Array(repeating: lane, count: count ?? Int(baseCount))
        case .individual(let l):
            guard count == nil || l.count == count else { return }
            list = l
        }
        modify(&list, lanesReversed)
        lanes = .individual(list)
    }

    /// `IndividualParser::mask_outer`: `lanes:psv=2` and the like make the
    /// outer lanes of the direction designated to the mode.
    mutating func maskOuter(_ tags: Tl, _ mode: TMode, _ key: String) {
        guard let lanesTags = tags.get("lanes"), let k = lanesTags.get(key), let d = direction(k), let v = d.value,
              let count = rustParseUsize(v) else { return }
        withLanes(nil) { lanes, reversed in
            let indices: [Int] = reversed ? Array(lanes.indices.prefix(count)) : Array(lanes.indices.reversed().prefix(count))
            for i in indices where lanes[i].travel.access.getRaw(mode) == nil {
                lanes[i].travel.access = TModes([(.all, Conditional(AccessLevel.no)), (mode, Conditional(AccessLevel.designated))])
            }
        }
    }

    /// `IndividualParser::direction_conditional`: a `*:lanes` value with its
    /// conditional, each restriction's `|`-separated values onto the lanes:
    /// `push` adds a restriction to a lane's value, clearing it first for
    /// an unconditional one.
    mutating func directionConditional<T>(_ tags: Tl?, _ parse: (String) -> T?,
                                          _ push: (inout Lane, Restriction<T>, Bool) -> Void) {
        guard let tags, let lanesTags = tags.get("lanes"), let d = direction(lanesTags),
              let conditionalLanes = Conditional<String>.parseWith(d, { $0 }),
              let firstLaneStr = conditionalLanes.first?.value else { return }
        let lanesCount = firstLaneStr.rustSplit("|").count
        withLanes(lanesCount) { list, reversed in
            for restriction in conditionalLanes.restrictions {
                let values = reversed ? restriction.value.rustRSplit("|") : restriction.value.rustSplit("|")
                for (value, i) in zip(values, list.indices) {
                    guard let v = parse(value) else { continue }
                    push(&list[i], Restriction(value: v, conditions: restriction.conditions), restriction.conditions.isEmpty)
                }
            }
        }
    }

    /// `IndividualParser::direction`: a plain `*:lanes` value onto the lanes.
    mutating func direction<T>(_ tags: Tl?, _ parse: (String) -> T?, _ set: (inout Lane, T) -> Void) {
        guard let tags, let lanesTags = tags.get("lanes"), let d = direction(lanesTags), let laneStr = d.value else { return }
        let lanesCount = laneStr.rustSplit("|").count
        withLanes(lanesCount) { list, reversed in
            let values = reversed ? laneStr.rustRSplit("|") : laneStr.rustSplit("|")
            for (value, i) in zip(values, list.indices) {
                if let v = parse(value) { set(&list[i], v) }
            }
        }
    }

    /// `IndividualParser::mode`: into the mode's entry of a per-direction map.
    mutating func mode<T>(_ mode: TMode, _ tags: Tl, _ parse: (String) -> T?,
                          _ getValue: WritableKeyPath<Lane, TModes<Conditional<T>>>) {
        directionConditional(tags, parse) { lane, restriction, clear in
            lane[keyPath: getValue].modifyOrInsert(mode, Conditional<T>([])) { c in
                if clear { c.restrictions.removeAll() }
                c.restrictions.append(restriction)
            }
        }
    }

    /// `IndividualParser::access`.
    mutating func access(_ tagsAccess: Tl?, _ tags: Tl, _ platform: Bool,
                         _ getValue: WritableKeyPath<Lane, TModes<Conditional<AccessLevel>>>) {
        if let tagsAccess { mode(.landBased, tagsAccess, AccessLevel.fromOsmStr, getValue) }
        for (m, t) in TMode.iterTags(tags) where !platform || allowedOnPlatform(m) {
            mode(m, t, AccessLevel.fromOsmStr, getValue)
        }
    }

    /// `IndividualParser::with_parse`.
    mutating func withParse<T>(_ tags: Tl?, _ getValue: WritableKeyPath<Lane, TModes<Conditional<T>>>,
                               _ parse: (String) -> T?) {
        guard let tags else { return }
        for (m, t) in TMode.iterTagsWithAll(tags) { mode(m, t, parse, getValue) }
    }
}
