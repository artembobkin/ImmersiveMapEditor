import Foundation
import Geometry
import simd

// Buildings. An ordinary building is made by one procedure from its OSM
// outline and tags (`ordinary`). A landmark is not: it is made by hand, and
// until its model exists the lab stands a clay placeholder of its OSM masses
// in its place (`placeholder`).
//
// Only a typical Moscow house by its OSM tags (`typical`: residential, or an
// anonymous `building=yes`) is drawn as one. Any other building (an office,
// a shop, a public building, anything named) is a plain box of its outline
// and height (`box`).
//
// The typical house, from the ground up:
//
// 1. Height from `height`, else `building:levels`, else the size of the
//    outline: a small or thin outline with no tags is a pavilion, 3.5 m.
//    Floors from `building:levels`, else one per 3.4 m. The wall is shared
//    out evenly between them, so the windows always fit.
// 2. Facades, if the building is one people live or work in floor by floor
//    (`hasWindows`: not a church, a garage, a kiosk, a substation, a small
//    untagged pavilion, which get plain walls): every outline edge long
//    enough for a window is divided into bays about 3.2 m wide. Each floor
//    of each bay has a window: a recess of windowDepth with four reveals in
//    the wall's colour and the glass at its back, one glass colour for the
//    whole tile. Between and around the windows the wall is merged into
//    piers and full-width bands. The lowest band is the plinth.
// 3. A cornice: the outline pushed out by corniceOut, corniceHeight tall,
//    at the top of the wall. The roof stands on it.
// 4. The roof, by `roof:shape`: gabled, hipped and round over a rectangular
//    outline as such, pyramidal low, flat flat. Any other pitched outline,
//    and an untagged building up to 30 m, gets a hip with a flat top: the
//    cornice outline inset by a few metres, sloped up to it.
//
// The tags of the outline a part stands in travel with the part's own,
// each under the prefix `_outline:` (`sortBuildings` puts them there), its
// key as `_key`, and `_plain` marks a building drawn as a box.

private let plasters = ["plaster_a", "plaster_b", "plaster_c"]
private let modernMaterials: Set<String> = ["concrete", "glass", "metal", "panel", "reinforced_concrete"]
private let religious: Set<String> = ["church", "cathedral", "chapel", "monastery", "temple", "mosque", "synagogue"]
// Buildings nobody lives or works in floor by floor: they get plain walls,
// no rows of windows (a church, a garage, a kiosk, a substation).
private let plain: Set<String> = religious.union([
    "shrine", "bell_tower", "garage", "garages", "carport", "parking", "shed", "kiosk", "hut", "cabin", "service",
    "transformer_tower", "industrial", "warehouse", "storage_tank", "greenhouse", "toilets", "bunker", "ruins",
    "barn", "stable", "transportation", "pavilion", "gatehouse", "water_tower", "tower", "boathouse", "roof",
    "container",
])

private let windowDepth = 0.25
private let plinth = 0.7
private let corniceOut = 0.35
private let corniceHeight = 0.45

/// The prefix the tags of a part's outline travel under.
public let outlinePrefix = "_outline:"

/// The tags of the outline a part stands in, empty for an outline itself.
public func outlineTags(_ tags: Tags) -> Tags {
    var out = Tags()
    for (k, v) in tags where k.hasPrefix(outlinePrefix) { out[String(k.dropFirst(outlinePrefix.count))] = v }
    return out
}

/// A tag that is set and not empty, as Python's truthiness reads it.
private func set(_ v: String?) -> String? { (v?.isEmpty ?? true) ? nil : v }

// MARK: Tags

public func totalHeight(_ tags: Tags, _ poly: Geometry) -> Double {
    if let h = length(tags["height"]) { return h }
    if let levels = length(tags["building:levels"]) {
        return levels * Facade.floor + (length(tags["roof:levels"]) ?? 0) * 3.0
    }
    let rect = poly.minimumRotatedRectangle
    let short = rect.kind == .polygon ? rectSides(rect).min()! : 0
    if poly.area < 80 || short < 6 { return 3.5 }
    return 4 * Facade.floor
}

func rectSides(_ rect: Geometry) -> [Double] {
    let c = rect.exterior
    return [simd_distance(c[0], c[1]), simd_distance(c[1], c[2])]
}

func defaultRoofHeight(_ shape: String, _ poly: Geometry) -> Double {
    let rect = poly.minimumRotatedRectangle
    let short = rect.kind == .polygon ? rectSides(rect).min()! : 4
    let radius = (poly.area / .pi).squareRoot()
    let heights: [String: Double] = [
        "gabled": 0.3 * short, "hipped": 0.25 * short, "round": 0.3 * short, "gambrel": 0.3 * short,
        "mansard": 0.25 * short, "pyramidal": 0.3 * short, "dome": radius, "onion": radius * 1.9,
        "skillion": 0.15 * short,
    ]
    return heights[shape] ?? 0
}

// MARK: The ordinary building

/// The wall by what the building is: brick is brick, a building of after
/// 1955 or of concrete and glass is modern, anything else is one of the
/// plasters, the same for every part of one building.
func wallOf(_ key: String, _ tags: Tags) -> String {
    let outline = outlineTags(tags)
    let material = set(tags["building:material"]) ?? set(outline["building:material"]) ?? ""
    if material.hasPrefix("brick") { return "brick" }
    let date = set(tags["start_date"]) ?? set(outline["start_date"]) ?? ""
    let year = length(String(date.prefix(4)))
    if modernMaterials.contains(material) || (year.map { $0 >= 1955 } ?? false) { return "modern" }
    return stable(key, plasters)
}

private let typicalKinds: Set<String> = ["apartments", "residential", "house", "dormitory", "terrace", "detached",
                                         "semidetached_house"]
private let named = ["name", "brand", "shop", "amenity", "office", "tourism", "wikidata", "wikipedia", "government",
                     "healthcare", "leisure", "sport", "craft"]

/// Whether OSM says this is a typical Moscow house, drawn as one (plaster,
/// cornice, rows of windows, hip roof): a residential building by its
/// `building` tag, or an anonymous `building=yes` (no name, shop, office,
/// institution or wiki link: in the centre, an ordinary tenement house).
/// Anything else (an office, a shop, a public building, anything with a
/// name) is a plain box, until it gets a model of its own.
public func typical(_ tags: Tags) -> Bool {
    let outline = outlineTags(tags)
    if set(tags["_plain"]) != nil { return false }
    let kind = set(tags["building"]) ?? set(outline["building"])
    if let kind, typicalKinds.contains(kind) { return true }
    if ["dome", "onion"].contains(tags["roof:shape"] ?? "") || ["dome", "onion"].contains(outline["roof:shape"] ?? "") {
        // A dome or an onion is a church's or a pavilion's, never a house's.
        return false
    }
    if set(tags["building:part"]) != nil && outline.isEmpty {
        // A part with no outline found: nothing says what building it is.
        return false
    }
    if kind == nil || kind == "yes" || set(tags["building:part"]) != nil {
        let anyNamed = named.contains { tags[$0] != nil || outline[$0] != nil }
        let what = set(outline["building"]) ?? kind ?? "yes"
        return !anyNamed && (what == "yes" || typicalKinds.contains(what))
    }
    return false
}

/// A building that is not a typical Moscow house: its outline pushed up to
/// its height, plain walls in the box colour sided by the sun, a flat roof.
/// No windows, no cornice.
func box(_ b: Builder, _ tags: Tags, _ poly: Geometry) {
    let z0 = minHeight(tags)
    let top = max(totalHeight(tags, poly), z0 + 3.0)
    b.span = (z0, top)
    for (a, c) in edges(poly) {
        b.paint([v3(a, z0), v3(c, z0), v3(c, top), v3(a, top)], "box", "building walls")
    }
    b.span = nil
    b.fill(poly, top, "roof_flat", "roofs")
    if z0 > 0.5 { b.fill(poly, z0, "box.shade", "building walls", down: true) }
}

/// Whether a building gets rows of windows: only one people live or work in
/// floor by floor. Not a place of worship, a utility or storage building
/// (`plain`, by its own tags or its outline's), nor a pavilion, small and
/// untagged.
func hasWindows(_ tags: Tags, _ poly: Geometry) -> Bool {
    for t in [tags, outlineTags(tags)] {
        if plain.contains(t["building"] ?? "") || t["amenity"] == "place_of_worship" || set(t["man_made"]) != nil
            || set(t["power"]) != nil {
            return false
        }
    }
    if length(tags["height"]) == nil && length(tags["building:levels"]) == nil {
        let rect = poly.minimumRotatedRectangle
        let short = rect.kind == .polygon ? rectSides(rect).min()! : 0
        if poly.area < 80 || short < 6 { return false }
    }
    return true
}

public func ordinary(_ b: Builder, _ id: String, _ tags: Tags, _ poly: Geometry) {
    if !typical(tags) {
        box(b, tags, poly)
        return
    }
    let key = tags["_key"] ?? id
    let wall = wallOf(key, tags)
    let z0 = minHeight(tags)
    let total = max(totalHeight(tags, poly), z0 + 3.0)
    var shape = tags["roof:shape"]
    if shape == nil && total <= 30 && z0 < 0.5 { shape = "hipped" }
    let roofShape = set(shape) ?? "flat"
    var roofH = length(tags["roof:height"])
    if roofH == nil {
        let levels = length(tags["roof:levels"])
        roofH = (levels ?? 0) != 0 ? levels! * 3.0 : defaultRoofHeight(roofShape, poly)
    }
    var top = length(tags["height"]) != nil ? total - roofH! : total
    top = max(top, z0 + 2.5)

    let levels = length(tags["building:levels"])
    let floors: Int
    if let levels, levels != 0, (top - z0) / levels >= 2.6 {
        floors = Int(levels)
    } else {
        floors = max(1, Int(((top - z0) / Facade.floor).rounded(.toNearestOrEven)))
    }
    let cornice = poly.buffer(corniceOut, join: .mitre, mitreLimit: 2.0)
    let hasCornice = top - z0 > 5 && cornice.isValid && cornice.kind == .polygon
    let wallTop = hasCornice ? top - corniceHeight : top
    b.span = (z0, top)
    let windows = hasWindows(tags, poly)
    for (a, c) in edges(poly) {
        facade(b, a, c, z0, wallTop, windows ? floors : 0, top - z0, wall)
    }
    b.span = nil
    var base = poly
    if hasCornice {
        b.walls(cornice, wallTop, top, "rim", "cornices")
        b.fill(cornice.difference(poly), wallTop, "rim", "cornices", down: true)
        base = cornice
    }
    roofOn(b, base, top, roofH!, roofShape, wall, "roof", "roof_flat")
}

/// One facade: windows in a grid of bays and floors, each a recess with
/// reveals and glass, the wall around them merged into bands and piers. The
/// inside is on the left of a→c.
func facade(_ b: Builder, _ a: P2, _ c: P2, _ z0: Double, _ z1: Double, _ floors: Int, _ storeySpan: Double,
            _ family: String) {
    let a3 = v3(a), along = v3(c) - a3
    let span = along.length
    if z1 - z0 < 0.01 { return }
    let direction = along / span
    let inward = V3(-direction.y, direction.x, 0)
    let fh = floors != 0 ? storeySpan / Double(floors) : 0.0
    let side = Palette.side(-inward.x, -inward.y)
    let colour = "\(family).\(side)"

    func p(_ t: Double, _ z: Double, _ depth: Double = 0) -> V3 {
        a3 + direction * t + inward * depth + V3(0, 0, z)
    }
    func quad(_ t0: Double, _ t1: Double, _ lo: Double, _ hi: Double, _ name: String) {
        if t1 - t0 > 1e-3 && hi - lo > 1e-3 {
            b.flat([p(t0, lo), p(t1, lo), p(t1, hi), p(t0, hi)], name, "building walls")
        }
    }

    let bays = Int(((span - 2 * Facade.corner) / Facade.bay).rounded(.down))
    if fh < 2.4 || bays < 1 {
        quad(0, span, z0, min(z1, z0 + plinth), "plinth")
        quad(0, span, min(z1, z0 + plinth), z1, colour)
        return
    }
    let w = min(Facade.windowWidth, Facade.bay * 0.45)
    let h = min(Facade.windowHeight, fh * 0.56)
    let sill = (fh - h) * 0.55
    let pitch = (span - 2 * Facade.corner) / Double(bays)
    let centres = (0..<bays).map { Facade.corner + pitch * (Double($0) + 0.5) }
    let rows = (0..<floors).map { j in (z0 + Double(j) * fh + sill, z0 + Double(j) * fh + sill + h) }
        .filter { $0.1 <= z1 - 0.2 }
    // Bands: under the first row, between rows, over the last.
    var level = z0
    for (lo, hi) in rows {
        if level < z0 + plinth {
            quad(0, span, level, min(lo, z0 + plinth), "plinth")
            level = min(lo, z0 + plinth)
        }
        quad(0, span, level, lo, colour)
        var edge = 0.0
        for t in centres {
            quad(edge, t - w / 2, lo, hi, colour)
            window(b, p, t - w / 2, t + w / 2, lo, hi, family, side)
            edge = t + w / 2
        }
        quad(edge, span, lo, hi, colour)
        level = hi
    }
    if level < z0 + plinth {
        quad(0, span, level, z0 + plinth, "plinth")
        level = z0 + plinth
    }
    quad(0, span, level, z1, colour)
}

/// A recess: four reveals a tone darker than the wall, the glass a darker
/// tone still, all shaded for the facade's side of the sun.
func window(_ b: Builder, _ p: (Double, Double, Double) -> V3, _ t0: Double, _ t1: Double, _ lo: Double,
            _ hi: Double, _ family: String, _ side: String) {
    let d = windowDepth
    let A = p(t0, lo, 0), B = p(t1, lo, 0), C = p(t1, hi, 0), D = p(t0, hi, 0)
    let A2 = p(t0, lo, d), B2 = p(t1, lo, d), C2 = p(t1, hi, d), D2 = p(t0, hi, d)
    let reveal = "\(family).reveal.\(side)"
    b.flat([A, B, B2, A2], "rim", "windows")        // sill, facing up
    b.flat([D2, C2, C, D], reveal, "windows")       // head, facing down
    b.flat([A2, D2, D, A], reveal, "windows")       // left reveal
    b.flat([B, C, C2, B2], reveal, "windows")       // right reveal
    b.flat([A2, B2, C2, D2], "\(family).glass.\(side)", "windows")
}
