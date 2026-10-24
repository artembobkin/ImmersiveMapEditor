import Foundation
import Geometry

/// A landmark's OSM masses in clay, no windows, until its hand-made model
/// replaces them.
public func placeholder(_ b: Builder, _ id: String, _ tags: Tags, _ poly: Geometry) {
    let shape = tags["roof:shape"] ?? "flat"
    let z0 = minHeight(tags)
    let total = max(totalHeight(tags, poly), z0 + 1.0)
    let roofH = length(tags["roof:height"]) ?? defaultRoofHeight(shape, poly)
    var top = length(tags["height"]) != nil ? total - roofH : total
    top = max(top, z0)
    b.span = (z0, top)
    b.walls(poly, z0, top, "clay", "landmarks")
    b.span = nil
    if (shape == "dome" || shape == "onion") && roofH > 0.2 {
        b.fill(poly, top, "clay_roof", "landmarks")
        lathe(b, poly, top, roofH, shape, "clay_roof")
    } else {
        roofOn(b, poly, top, roofH, shape, "clay", "clay_roof", "clay_roof")
    }
}

import simd
