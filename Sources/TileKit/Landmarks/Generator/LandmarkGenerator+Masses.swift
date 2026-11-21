import CoreGraphics
import CoreText
import Foundation
import Geometry
import GLTF
import simd

/// The plan of a recipe's masses: each one's outline cut and straightened,
/// masses on one footprint stacked, corners and walls along a neighbour
/// sunk into it so the union makes one shell, and the refusals of a wall
/// shared by two masses or a mass over a courtyard.
extension LandmarkGenerator {
    /// Masses that touch or nearly touch sunk a little into each other, so
    /// the union makes one shell of them: a corner standing on a
    /// neighbour's wall, or within `near` of it, moves `into` metres inside
    /// that neighbour (where their heights overlap). Two masses built
    /// edge to edge, or with a slot between them, would stay two shells,
    /// with windows cut in walls no one sees.
    static func sink(_ rings: inout [[P2]?], _ masses: [LandmarkRecipe.Mass], near: Double = 0.6, into: Double = 0.3) {
        let polygons = rings.map { $0.map { Geometry.polygon($0 + [$0[0]]) } }
        for i in rings.indices {
            guard var ring = rings[i] else { continue }
            for k in ring.indices {
                let v = ring[k]
                for j in rings.indices where j != i {
                    guard let other = polygons[j], masses[i].base < masses[j].top - 0.05, masses[j].base < masses[i].top - 0.05 else { continue }
                    guard !other.contains(.point(v + (v - other.centroid.xy) * -1e-3)) || other.boundary.distance(.point(v)) < 1e-6 else { continue }
                    let d = other.boundary.distance(.point(v))
                    guard d < near else { continue }
                    // The nearest point of the neighbour's wall, and the way in.
                    let (_, on) = Geometry.point(v).nearestPoints(other.boundary)
                    let inward: P2
                    if d > 1e-6 {
                        inward = (on - v) / d
                    } else {
                        // On the wall itself: in is away from the centroid's far side.
                        let c = other.centroid.xy
                        inward = simd_length(c - v) > 1e-9 ? (c - v) / simd_length(c - v) : .zero
                    }
                    ring[k] = on + inward * into
                    break
                }
            }
            // Only a ring still simple (see sinkEdges).
            if Geometry.polygon(ring + [ring[0]]).isValid { rings[i] = ring }
        }
    }

    /// The footprint of every mass: its outline or polygon, cut by its
    /// `cuts` (the part on the keep side of each), less the footprints of
    /// its `minus` masses; nil for a mass with none.
    static func footprints(_ r: LandmarkRecipe, _ source: LandmarkSource) -> [[P2]?] {
        func base(_ mass: LandmarkRecipe.Mass) -> [P2]? {
            let ring = mass.outline.flatMap { source.ring($0) } ?? (mass.polygon ?? []).filter { $0.count == 2 }.map { P2($0[0], $0[1]) }
            guard ring.count >= 3, mass.top > mass.base else { return nil }
            let first = ccw(ring)
            var shape = Geometry.polygon(first + [first[0]])
            for cut in mass.cuts ?? [] where cut.from.count == 2 && cut.to.count == 2 && cut.keep.count == 2 {
                let a = P2(cut.from[0], cut.from[1]), b = P2(cut.to[0], cut.to[1]), keep = P2(cut.keep[0], cut.keep[1])
                let d = b - a, len = simd_length(d)
                guard len > 1e-6 else { continue }
                // The half-plane on the keep side of the line, large enough.
                var n = P2(-d.y, d.x) / len
                if simd_dot(keep - a, n) < 0 { n = -n }
                let u = d / len, far = 10_000.0
                let half = [a - u * far, a + u * far, a + u * far + n * far, a - u * far + n * far]
                shape = shape.intersection(Geometry.polygon(half + [half[0]]))
            }
            guard let part = shape.polygons.max(by: { $0.area < $1.area }), part.area > 1 else { return nil }
            return straightened(ccw(Array(part.exterior.dropLast())))
        }
        let bases = r.masses.map(base)
        return r.masses.enumerated().map { k, mass in
            guard let ring = bases[k], let minus = mass.minus, !minus.isEmpty else { return bases[k] }
            var shape = Geometry.polygon(ring + [ring[0]])
            for id in minus {
                guard let j = r.masses.firstIndex(where: { $0.id == id }), j != k, let other = bases[j] else { continue }
                shape = shape.difference(Geometry.polygon(other + [other[0]]))
            }
            guard let part = shape.polygons.max(by: { $0.area < $1.area }), part.area > 1 else { return nil }
            return straightened(ccw(Array(part.exterior.dropLast())))
        }
    }

    /// A ring with its slivers gone (a hair-thin spike a cut or a difference
    /// leaves through a vertex on a wall) and its collinear corners merged
    /// (an OSM outline has points along a straight wall, and each would
    /// start a wall of its own with its own row of windows): the ring
    /// buffered out and in by 2 cm with square corners, then every corner
    /// within 8 cm of the line through its neighbours dropped.
    static func straightened(_ ring: [P2]) -> [P2] {
        guard ring.count >= 3 else { return ring }
        // Round joins: a mitre at a spike's tip reaches out and leaves a stub.
        let shape = Geometry.polygon(ring + [ring[0]]).buffer(0.02, quadSegs: 1, join: .round).buffer(-0.02, quadSegs: 1, join: .round)
        guard let part = shape.polygons.max(by: { $0.area < $1.area }), part.area > 1 else { return ring }
        var out = ccw(Array(part.exterior.dropLast()))
        var again = true
        while again, out.count > 3 {
            again = false
            for i in out.indices {
                let p = out[(i + out.count - 1) % out.count], q = out[i], r = out[(i + 1) % out.count]
                let d = r - p, len = simd_length(d)
                guard len > 1e-6 else { continue }
                // On the line through its neighbours, between them (a point
                // along a straight wall) or beyond one of them (a spike).
                let off = abs((q - p).x * d.y - (q - p).y * d.x) / len
                if off < 0.08 {
                    out.remove(at: i)
                    again = true
                    break
                }
            }
        }
        return out
    }

    /// The masses standing in a courtyard of the landmark (the open sky its
    /// OSM parts enclose above a floor, `LandmarkSource.courtyards`): a mass
    /// whose footprint takes a good part of one and rises over its floor, a
    /// line each for the recipe's check (the user, 2026-11-03: the Hotel
    /// Moskva's courtyard roofed over by one mass of its whole outline, the
    /// satellite view ignored). The wings around a courtyard are masses cut
    /// from the outline, and what is under it ends at its floor.
    static func overCourtyards(_ rings: [[P2]?], _ masses: [LandmarkRecipe.Mass], _ source: LandmarkSource) -> [String] {
        let yards = source.courtyards
        guard !yards.isEmpty else { return [] }
        var out: [String] = []
        for (i, m) in masses.enumerated() {
            guard let ring = rings[i] else { continue }
            let shape = Geometry.polygon(ring + [ring[0]])
            for yard in yards where m.top > yard.floor + 1 {
                let open = Geometry.polygon(yard.ring + [yard.ring[0]]), c = yard.centre
                guard shape.intersection(open).area > max(40, open.area * 0.4) else { continue }
                out.append("masses[\(i)]" + (m.id.map { " (\($0))" } ?? "")
                           + String(format: ": stands in the courtyard at (%.0f, %.0f), %.0f m² open to the sky above %.0f m: ", c.x, c.y, open.area, yard.floor)
                           + (yard.floor > 0 ? String(format: "what is under the courtyard ends at %.0f m (the podium its garden lies on), and ", yard.floor) : "")
                           + "the wings around it are masses cut from the outline (cuts, and minus where they overlap), none over the courtyard")
            }
        }
        return out
    }

    /// Two masses running along one wall: a stretch of 3 m or more where
    /// their walls are parallel (within 10°), look the same way and lie
    /// within 2.5 m of each other, their heights overlapping by more than
    /// a metre. The
    /// first such pair, as a line for the recipe's check; nil when none.
    static func sharedWall(_ rings: [[P2]?], _ masses: [LandmarkRecipe.Mass]) -> String? {
        for i in rings.indices {
            guard let ring = rings[i] else { continue }
            for j in rings.indices where j > i {
                // Heights overlapping by more than the half metre that joins
                // a part to the one it stands on (a set-back storey on a roof
                // stands 2 m in from the walls below, and is no second wall).
                guard let other = rings[j], min(masses[i].top, masses[j].top) - max(masses[i].base, masses[j].base) > 1 else { continue }
                for k in ring.indices {
                    let a = ring[k], b = ring[(k + 1) % ring.count], d = b - a, len = simd_length(d)
                    guard len > 3 else { continue }
                    let dir = d / len, n = P2(dir.y, -dir.x)
                    for m in other.indices {
                        let c = other[m], e = other[(m + 1) % other.count], f = e - c, flen = simd_length(f)
                        guard flen > 3, simd_dot(f / flen, dir) > cos(10 * Double.pi / 180) else { continue }   // the same way
                        let tc = simd_dot(c - a, dir), te = simd_dot(e - a, dir)
                        let t0 = max(0, min(tc, te)), t1 = min(len, max(tc, te))
                        guard t1 - t0 > 3 else { continue }
                        let off = (abs(simd_dot(c - a, n)) + abs(simd_dot(e - a, n))) / 2
                        guard off < 2.5 else { continue }
                        func name(_ x: Int) -> String { "masses[\(x)]" + (masses[x].id.map { " (\($0))" } ?? "") }
                        if ProcessInfo.processInfo.environment["LANDMARK_RINGS_DEBUG"] != nil {
                            for (x, r) in rings.enumerated() { FileHandle.standardError.write(Data("ring \(x): \(r?.map { String(format: "(%.1f, %.1f)", $0.x, $0.y) }.joined(separator: " ") ?? "none")\n".utf8)) }
                            FileHandle.standardError.write(Data(String(format: "shared: edge %d of %d (%.1f, %.1f)-(%.1f, %.1f) and edge %d of %d (%.1f, %.1f)-(%.1f, %.1f), t %.1f..%.1f\n", k, i, a.x, a.y, b.x, b.y, m, j, c.x, c.y, e.x, e.y, t0, t1).utf8))
                        }
                        return "\(name(i)) and \(name(j)) run along one wall for \(Int(t1 - t0)) m, \(String(format: "%.1f", off)) m apart: a wall is one wall. Cut the outline into its parts (cuts, and the rest minus them) instead of a polygon beside it."
                    }
                }
            }
        }
        return nil
    }

    /// A wall running along a neighbour's wall within `near` of it (a
    /// slot between two masses, or two walls flush) pushed `into` metres
    /// into the neighbour along the stretch they share: the wall is split
    /// where the stretch begins and ends, and that piece moves. Deeper
    /// than a window's recess, so the windows of both walls end up inside
    /// the other mass and go with the union, instead of staying as sealed
    /// pockets in the wall. Corners far
    /// from the neighbour (a wider block beside a narrower one) leave `sink`
    /// nothing to do; this closes the slot itself.
    static func sinkEdges(_ rings: inout [[P2]?], _ masses: [LandmarkRecipe.Mass], near: Double = 0.6, into: Double = 0.3) {
        let original = rings
        for i in rings.indices {
            guard let ring = original[i] else { continue }
            var out: [P2] = []
            for k in ring.indices {
                let a = ring[k], b = ring[(k + 1) % ring.count]
                let d = b - a, len = simd_length(d)
                guard len > 1e-6 else { out.append(a); continue }
                let dir = d / len, n = P2(dir.y, -dir.x)   // the outside of a counter-clockwise ring
                // The stretches of this wall that face a neighbour's wall closely:
                // (from, to, how far the neighbour is).
                var stretches: [(Double, Double, Double)] = []
                for j in original.indices where j != i {
                    // The lower wall goes into the taller neighbour, where the
                    // whole of it hides; a taller wall pushed into a lower
                    // neighbour would step out above it.
                    guard let other = original[j], masses[i].base < masses[j].top - 0.05, masses[j].base < masses[i].top - 0.05,
                          masses[i].top <= masses[j].top + 0.05 else { continue }
                    for m in other.indices {
                        let c = other[m], e = other[(m + 1) % other.count]
                        let f = e - c, flen = simd_length(f)
                        guard flen > 1e-6, abs(simd_dot(f / flen, dir)) > cos(10 * Double.pi / 180) else { continue }
                        // How far out the neighbour's wall is, and where along ours it runs.
                        let dc = simd_dot(c - a, n), de = simd_dot(e - a, n)
                        guard min(dc, de) > -0.05, max(dc, de) < near else { continue }
                        let t0 = max(0, min(simd_dot(c - a, dir), simd_dot(e - a, dir))), t1 = min(len, max(simd_dot(c - a, dir), simd_dot(e - a, dir)))
                        guard t1 - t0 > 1 else { continue }
                        stretches.append((t0, t1, max(dc, de)))
                    }
                }
                out.append(a)
                guard !stretches.isEmpty else { continue }
                // The wall from a to b, its near stretches pushed out, in order.
                stretches.sort { $0.0 < $1.0 }
                var cursor = 0.0
                for (t0, t1, far) in stretches where t0 >= cursor - 1e-6 {
                    let push = n * (far + into)
                    if t0 > cursor + 0.05 { out.append(a + dir * t0) }
                    out.append(a + dir * max(t0, cursor) + push)
                    out.append(a + dir * t1 + push)
                    if t1 < len - 0.05 { out.append(a + dir * t1) }
                    cursor = t1
                }
            }
            // Points that fell together (a stretch to the corner) once.
            var cleaned: [P2] = []
            for p in out where cleaned.last.map({ simd_length($0 - p) > 1e-6 }) ?? true { cleaned.append(p) }
            if cleaned.count > 1, simd_length(cleaned[0] - cleaned[cleaned.count - 1]) < 1e-6 { cleaned.removeLast() }
            // Only a ring still simple: a stretch pushed across a sharp
            // notch of its own wall crosses itself, and a self-crossing solid
            // in the union gave a vertex half a metre under the ground (the
            // user, 2026-11-04: GUM's tile refused, nothing below the ground).
            if cleaned.count >= 3, Geometry.polygon(cleaned + [cleaned[0]]).isValid { rings[i] = cleaned }
        }
    }
}
