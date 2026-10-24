import CryptoKit
import Foundation
import Geometry
import simd

// Construction sites (`landuse=construction`): their ground is not drawn
// (the vector tile shows it), `ConstructionSite` puts up what makes a site
// read as one from afar, all low-poly toys in the palette's prop colours:
//
// - a fence `fenceHeight` high along the site's edge: green panels, posts
//   standing above them, a light rail on top, broken where a building stands
//   on the edge;
// - a tower crane on every site of `craneArea` or more, one by every house
//   being built: a lattice mast, a jib with its trolley and hook, a
//   counter-jib with its weights, the ties from the mast's top, standing
//   above the houses around it;
// - on a site of `frameArea` or more, the concrete frame of a house being
//   built, one more for every `frameEach` (three at most);
// - site cabins along the fence, two side by side and one on top, and a row
//   of portable toilets by them;
// - then as many as the free ground holds (`mix`): excavators, bulldozers,
//   dump trucks full of earth, concrete mixers, mounds of dug earth, piles
//   of sand and gravel, stacks of concrete slabs, pallets of bricks, steel
//   pipes, concrete well rings.
//
// Things are placed on the whole OSM site, not on the part of it in the
// tile, so the tiles on either side of an edge place them alike and the cut
// joins. Each site takes its frame from its outline's long side. Candidate
// spots lie on a grid, tried from the site's middle out with a jitter fixed
// by the site, so a rebuild puts things in the same places. A thing that
// does not fit clear of the fence, the buildings, the roads and the others
// is left out.

/// The fence along the sites' `earth` (Ground's construction earth) and the
/// things of every site touching `work`.
public func buildSites(_ b: Builder, osm: Osm, work: Geometry, earth: Geometry?, footprint: Geometry,
                       asphalt: Geometry) {
    guard let earth, !earth.isEmpty else { return }
    ConstructionSite.buildFence(b, earth, footprint)
    let taken = footprint.buffer(1.0).union(asphalt.buffer(1.0))
    for area in osm.areas() where area.tags["landuse"] == "construction" && area.shape.intersects(work) {
        for site in area.shape.polygons where site.area >= 300 {
            ConstructionSite.furnish(b, site, site.difference(taken))
        }
    }
}

/// The constants and pieces of a construction site, one file to a part:
/// the fence, placing things on the site, the crane, the machines, the
/// cabins, the materials, the frame of the house being built.
enum ConstructionSite {
    static let fenceHeight = 2.4
    static let fenceThick = 0.2
    static let fenceRail = 0.25
    static let fencePost = 3.0
    static let craneArea = 1500.0
    static let frameArea = 3000.0
    static let frameEach = 10000.0
    static let frameGap = 45.0
    // The things a site is filled with: one of each kind per so many square
    // metres of its free ground, at most `mixMax`, at least one if it is a kind a
    // small site has too. In this order.
    static let mix: [(String, Double)] = [
        ("excavator", 1500), ("soil", 2000), ("sand", 1500), ("gravel", 3000), ("slabs", 1500), ("bricks", 1500),
        ("pipes", 3000), ("rings", 3000), ("dump_truck", 5000), ("mixer", 8000), ("bulldozer", 6000),
    ]
    static let mixMax = 8
    // Machines are fewer than that: at most so many of each kind on a site.
    static let mixCap = ["excavator": 3, "bulldozer": 2, "dump_truck": 3, "mixer": 2]
    static let craneHeight = (36.0, 44.0)
    static let craneJib = 30.0
    static let craneCounter = 9.0
    static let mast = 1.8
    static let kind = "construction"

    static func upright(_ b: Builder, _ c: P2, _ heading: Double, _ lx: Double, _ ly: Double, _ z0: Double,
                         _ h: Double, _ colour: String, bottom: Bool = false, top: Bool = true) {
        TileKit.upright(b, c, heading, lx, ly, z0, h, colour, kind, bottom: bottom, top: top)
    }

    static func bar(_ b: Builder, _ p: V3, _ q: V3, _ t: Double, _ colour: String) {
        TileKit.bar(b, p, q, t, colour, kind)
    }
}
