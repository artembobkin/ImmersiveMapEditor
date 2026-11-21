import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// The landmark itself and its model: its OSM buildings and outlines as
/// get_landmark and get_outlines give them, the recipe read, written and
/// built (set_recipe, a round of the work each), and the facades a recipe
/// changes, for the comparisons after a build.
extension LandmarkMCP.Server {
    /// The landmark in short, a line a building: its outlines whole would
    /// pass what a tool may return, so they come by get_outlines.
    func landmark() throws -> String {
        let source = try LandmarkSource(folder.appendingPathComponent("landmark.json"))
        func f(_ v: Double) -> String { String(format: "%.1f", v) }
        // The building's main axis: the long side of the smallest rectangle
        // around its hull, as a compass bearing.
        var axis = ""
        let all = source.buildings.flatMap { $0.polygons.flatMap { $0.first ?? [] } }
        let rect = Geometry.collection(all.map { Geometry.point($0) }).convexHull.minimumRotatedRectangle.exterior
        if rect.count >= 4, !source.isMonument {
            let u = rect[1] - rect[0], v = rect[2] - rect[1]
            let long = simd_length(u) >= simd_length(v) ? u : v
            let bearing = (atan2(long.x, long.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 180)
            axis = String(format: " Its long axis runs at a bearing of %.0f° (so its walls face %.0f°, %.0f°, %.0f° and %.0f°): give boxes, colonnades and pediments these headings and lines, parallel to the walls, never to north when the building is not.",
                          bearing, bearing, (bearing + 90).truncatingRemainder(dividingBy: 360), (bearing + 180).truncatingRemainder(dividingBy: 360), (bearing + 270).truncatingRemainder(dividingBy: 360))
        }
        var lines = ["Landmark: \(source.name), centre lon/lat \(source.centre.0), \(source.centre.1)." + axis]
        // A monument, not a building (the user, 2026-11-05): a point in OSM
        // with a plot round it, which is no wall.
        if source.isMonument {
            let plot = source.buildings.compactMap(\.plotRadius).first
            let h = source.buildings.compactMap(\.height).max()
            lines.append("THIS LANDMARK IS A MONUMENT, not a building: a statue, a sculpture, a vehicle or a stone on a pedestal, "
                         + (plot.map { "mapped in OSM as a point. The ring below is the plot of \(Int($0)) m round it, not a wall: build nothing of it. " }
                            ?? "mapped in OSM as a small area, its outline the plot, not a wall: build nothing of it. ")
                         + "Model the monument itself at its real size, standing at (0, 0) on the ground: no masses; the pedestal a box, a cylinder, "
                         + "a prism or a loft shape; the figure on it a statue feature where one fits, else shapes assembled (the guide says how). "
                         + (h.map { "OSM gives its height as \(Int($0)) m. " } ?? "")
                         + "Its heading and footprint from the satellite view (its shadow) and the street photos; its colours in the palette's words (bronze lm_dark, stone lm_stone, gilt lm_gold).")
        }
        lines += [
                     "Its OSM buildings (\(source.buildings.count)): id, part or outline, base..height m, plan size and middle (x east, y north, m), area, the tags that shape it.",
                     "The outlines of the largest come below, the rest by get_outlines (ids)."]
        // The largest first, and only so many: St Basil's 514 parts made
        // an answer Claude Code would not pass on, and the run died of it
        // (the user, 2026-11-04). The small ones, drums, finials and
        // steps, are drawn as shapes from the photos anyway.
        let byArea = source.buildings.sorted { $0.polygons.reduce(0.0) { $0 + abs(signedArea($1[0])) } > $1.polygons.reduce(0.0) { $0 + abs(signedArea($1[0])) } }
        let listed = byArea.prefix(Self.listedBuildings)
        for b in listed {
            let pts = b.polygons.flatMap { $0.first ?? [] }
            guard let first = pts.first else { continue }
            let lo = pts.reduce(first) { simd_min($0, $1) }, hi = pts.reduce(first) { simd_max($0, $1) }
            let area = b.polygons.reduce(0.0) { $0 + abs(signedArea($1[0])) }
            let tags = b.tags.filter { Self.shapeTag($0.key) }.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
            lines.append("\(b.osm) \(b.part ? "part" : "outline") \(f(b.base))..\(b.height.map(f) ?? "?") m, "
                         + "\(f(hi.x - lo.x))×\(f(hi.y - lo.y)) at (\(f((lo.x + hi.x) / 2)), \(f((lo.y + hi.y) / 2))), \(Int(area)) m²"
                         + (tags.isEmpty ? "" : ", " + tags.joined(separator: " ")))
        }
        if source.buildings.count > listed.count {
            let smallest = listed.last.map { $0.polygons.reduce(0.0) { $0 + abs(signedArea($1[0])) } } ?? 0
            lines.append("… and \(source.buildings.count - listed.count) smaller parts under \(Int(smallest)) m² each, not listed: drums, finials, porches and steps, "
                         + "which the recipe draws as shapes from the photos; get_outlines gives any of them by id.")
        }
        // The courtyards the parts leave open (the user, 2026-11-03: the
        // Hotel Moskva's roofed over by one mass of its outline, the
        // satellite view ignored): named here, and a mass over one is
        // refused by the recipe's check.
        let yards = source.courtyards
        if !yards.isEmpty {
            lines.append("")
            lines.append("Open to the sky inside it: \(yards.count) courtyard\(yards.count == 1 ? "" : "s") the parts enclose "
                         + "(the outline is one ring around the whole block, courtyard and all). No mass rises over a courtyard's floor (the build refuses it): "
                         + "what is under it ends at the floor (the ground, or the podium its garden lies on), the wings around it are masses cut from the outline "
                         + "(cuts, and minus where they overlap at the corners), and the courtyard stays open. "
                         + "Each as a ring in metres (x east, y north), its area, middle and floor first:")
            for yard in yards {
                let c = yard.centre
                let g = Geometry.lineString(yard.ring + [yard.ring[0]]).simplify(0.3).coords
                lines.append(String(format: "%.0f m² at (%.0f, %.0f), its floor at %.0f m: [", yard.area, c.x, c.y, yard.floor)
                             + g.dropLast().map { String(format: "[%.1f, %.1f]", $0.x, $0.y) }.joined(separator: ", ") + "]")
            }
        }
        // The walls themselves, in metres (the user, 2026-11-01: placed by
        // eye off the satellite view, porticos, panels and signs stood
        // metres before the wall, in the air).
        let largest = source.buildings.sorted { $0.polygons.reduce(0.0) { $0 + abs(signedArea($1[0])) } > $1.polygons.reduce(0.0) { $0 + abs(signedArea($1[0])) } }
        let shown = Array(largest.prefix(12))
        lines.append("")
        lines.append("The walls: the outline rings of \(shown.count == source.buildings.count ? "its buildings" : "its \(shown.count) largest buildings") in metres (x east, y north), each ring's corners in order, simplified to 0.3 m. "
                     + "Whatever stands on a facade, a colonnade or a portico's stylobate, a pediment, a panel, a sign, takes its line and points from these corners (a step out of a metre at most), so it stands on the wall and not in the air before it.")
        lines.append(try outlines(shown.map(\.osm)))
        return lines.joined(separator: "\n") + "\n\n" + LandmarkRecipe.guide
    }

    /// Tags that say how a building looks, not where it is or who mapped it.
    static func shapeTag(_ key: String) -> Bool {
        key.hasPrefix("roof:") || key.hasPrefix("building") || ["name", "height", "min_height", "min_level",
            "architecture", "start_date", "colour", "material", "historic", "amenity", "layer"].contains(key)
    }

    /// Outer rings (and holes) of some of the landmark's buildings, in
    /// metres, simplified.
    func outlines(_ ids: [String]) throws -> String {
        let source = try LandmarkSource(folder.appendingPathComponent("landmark.json"))
        var out: [String] = []
        for id in ids.prefix(40) {
            guard let b = source.buildings.first(where: { $0.osm == id }) else { out.append("\(id): not one of the landmark's"); continue }
            let rings = b.polygons.map { poly -> String in
                poly.map { ring -> String in
                    let g = Geometry.lineString(ring + [ring[0]]).simplify(0.3).coords
                    return "[" + g.dropLast().map { String(format: "[%.1f, %.1f]", $0.x, $0.y) }.joined(separator: ", ") + "]"
                }.joined(separator: " hole ")
            }
            out.append("\(id): " + rings.joined(separator: " | "))
        }
        return out.joined(separator: "\n")
    }

    var recipeURL: URL { folder.appendingPathComponent("recipe.json") }

    func recipeText() throws -> String {
        // Compact, a mass a line, so a recipe of many parts fits.
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        func lines(_ r: LandmarkRecipe) throws -> String {
            let masses = try r.masses.map { String(data: try e.encode($0), encoding: .utf8)! }
            let features = try r.features.map { String(data: try e.encode($0), encoding: .utf8)! }
            let shapes = try r.shapes.map { String(data: try e.encode($0), encoding: .utf8)! }
            return "{\"version\": 1,\n \"masses\": [\n" + masses.joined(separator: ",\n") + "],\n \"features\": [\n"
                + features.joined(separator: ",\n") + "],\n \"shapes\": [\n" + shapes.joined(separator: ",\n") + "]}"
        }
        if let recipe = try? LandmarkRecipe.read(recipeURL) { return try lines(recipe) }
        let starter = try LandmarkSource(folder.appendingPathComponent("landmark.json")).starterRecipe()
        return "(no recipe yet: a starter from OSM's tags)\n" + (try lines(starter))
    }

    func setRecipe(_ value: Any?) throws -> String {
        guard let value else { throw Failure("no recipe given") }
        // Nothing is modelled from nothing (the user, 2026-11-21): a photo of
        // the building first, or the landmark is skipped.
        guard hasPhoto || FileManager.default.fileExists(atPath: recipeURL.path) else {
            return "Not built: no photo of the building is kept yet. " + whatNow()
        }
        let data = try JSONSerialization.data(withJSONObject: value)
        let recipe: LandmarkRecipe
        do {
            recipe = try JSONDecoder().decode(LandmarkRecipe.self, from: data)
        } catch {
            throw Failure("the recipe does not read: \(error)")
        }
        let source = try LandmarkSource(folder.appendingPathComponent("landmark.json"))
        let problems = LandmarkGenerator.check(recipe, source)
        guard problems.isEmpty else { return "Not built, the recipe has problems:\n" + problems.joined(separator: "\n") }
        // The facades this recipe changes against the last round's.
        lastTouched = touchedFacades(previous: currentRound.appendingPathComponent("recipe.json"), now: value, source: source)
        try recipe.write(recipeURL)
        let model = LandmarkGenerator.build(recipe, source)
        try model.write(folder.appendingPathComponent("model.glb"), name: source.name)
        let said = (["Built model.glb: \(model.summary)"] + LandmarkGenerator.advice(recipe, source)).joined(separator: "\n")
        // A model at last: no longer skipped.
        LandmarkSkip.clear(in: folder)
        // A round of the work: this recipe and model, and the pictures made of them after.
        let round = nextRound()
        try FileManager.default.createDirectory(at: round, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: recipeURL, to: round.appendingPathComponent("recipe.json"))
        try? FileManager.default.copyItem(at: folder.appendingPathComponent("model.glb"), to: round.appendingPathComponent("model.glb"))
        try? (said + "\n").write(to: round.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
        return said + " (round \(round.lastPathComponent))"
    }


    /// The facades a recipe changes against the previous one: the
    /// elements (masses, features, shapes) new or changed, each at the
    /// facades within 15 m of any of its points (its outline's ring, at,
    /// from, to, centre, polygon, holes); an element with no point near
    /// any facade (a dome in the middle) touches all. nil for all when
    /// there is no previous recipe to compare with.
    func touchedFacades(previous: URL, now: Any, source: LandmarkSource) -> [Int]? {
        guard let scene = try? StreetScene(folder: folder), !scene.facades.isEmpty,
              let data = try? Data(contentsOf: previous), let old = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let new = now as? [String: Any] else { return nil }
        func canon(_ e: Any) -> String {
            (try? JSONSerialization.data(withJSONObject: e, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
        var was = Set<String>()
        for key in ["masses", "features", "shapes"] { for e in old[key] as? [Any] ?? [] { was.insert(canon(e)) } }
        var touched = Set<Int>()
        for key in ["masses", "features", "shapes"] {
            for e in new[key] as? [Any] ?? [] where !was.contains(canon(e)) {
                guard let d = e as? [String: Any] else { continue }
                var points: [P2] = []
                func pair(_ v: Any?) -> P2? {
                    guard let a = v as? [Any], a.count >= 2, let x = (a[0] as? NSNumber)?.doubleValue, let y = (a[1] as? NSNumber)?.doubleValue else { return nil }
                    return P2(x, y)
                }
                for k in ["at", "from", "to", "centre"] { if let p = pair(d[k]) { points.append(p) } }
                if let around = d["around"] as? [String: Any], let p = pair(around["centre"]) { points.append(p) }
                for p in (d["polygon"] as? [Any] ?? []).compactMap(pair) { points.append(p) }
                for hole in d["holes"] as? [Any] ?? [] { for p in (hole as? [Any] ?? []).compactMap(pair) { points.append(p) } }
                if let outline = d["outline"] as? String, let ring = source.ring(outline) { points += ring }
                var near = Set<Int>()
                for (f, facade) in scene.facades.enumerated() {
                    let a = facade.a, b = facade.b, ab = b - a, len2 = max(1e-9, simd_dot(ab, ab))
                    for p in points {
                        let t = max(0, min(1, simd_dot(p - a, ab) / len2))
                        if simd_length(p - (a + ab * t)) <= 15 { near.insert(f); break }
                    }
                }
                if near.isEmpty { near = Set(scene.facades.indices) }
                touched.formUnion(near)
            }
        }
        return touched.sorted()
    }
}
