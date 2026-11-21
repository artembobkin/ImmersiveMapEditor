import CoreGraphics
import CoreText
import Foundation
import Geometry
import ImageIO
import simd
import TileKit

enum StreetPicks {
    /// A look worth a candidate.
    static let worthwhile = 0.05
    /// Looks at each station, each from another track.
    static let perStation = 7

    /// The candidates, a walk around the landmark: facade by facade, station
    /// by station along it (from beyond one end, its thirds, from beyond
    /// the other end), at each the photos standing there that show the
    /// facade best, each from another track (`perStation` at most), none
    /// where no photo stands; within `limit` in all.
    /// Lines for the agent, the picks as they are numbered, and each pick
    /// with the facade and station it was taken for (kept at once).
    static func report(_ views: [StreetView], in scene: StreetScene, limit: Int) -> (text: String, picks: [StreetView], stations: [(facade: Int, station: Int, view: StreetView)]) {
        guard !views.isEmpty else { return ("", [], []) }
        let facades = scene.facades
        var picks: [StreetView] = []
        var taken: [String: Int] = [:]   // photo id to its number
        var atStation: [[[StreetView]]] = facades.map { _ in Array(repeating: [], count: StreetScene.stations) }
        let order = facades.indices.sorted { facades[$0].length > facades[$1].length }
        func take(_ v: StreetView, _ f: Int, _ k: Int) {
            atStation[f][k].append(v)
            if taken[v.photo.id] == nil {
                picks.append(v)
                taken[v.photo.id] = picks.count
            }
        }
        func here(_ f: Int, _ k: Int) -> [StreetView] {
            views.filter { $0.looks[f] >= worthwhile && $0.seen[f] >= StreetView.enough && scene.station(f, of: $0.photo.at) == k }
                .sorted { $0.looks[f] * $0.seen[f] > $1.looks[f] * $1.seen[f] }
        }
        // Round by round, so the limit spreads over every station: first the
        // best look at every station of every facade (the longest facade
        // first, the part seen counting twice), then a look from another
        // track at each, up to `perStation`.
        for round in 0..<perStation {
            for f in order {
                for k in 0..<StreetScene.stations where picks.count < limit {
                    let tracks = Set(atStation[f][k].map(\.photo.sequence))
                    guard atStation[f][k].count == round,
                          let v = here(f, k).first(where: { !tracks.contains($0.photo.sequence) }) else { continue }
                    take(v, f, k)
                }
            }
        }
        var out: [String] = []
        var stations: [(facade: Int, station: Int, view: StreetView)] = []
        for f in order {
            for k in 0..<StreetScene.stations { for v in atStation[f][k] { stations.append((f, k, v)) } }
            let name = facades[f].name.prefix(1).uppercased() + facades[f].name.dropFirst()
            let mine = atStation[f].flatMap { $0 }
            guard !mine.isEmpty else {
                let any = views.filter { $0.seen[f] >= StreetView.enough }.count
                out.append("\(name) (\(Int(facades[f].length)) m): " + (any == 0 ? "no photo shows it." : "no photo gives a good look at it (\(any) glance at it)."))
                continue
            }
            var covered = [Bool](repeating: false, count: facades[f].samples.count)
            for v in mine { for i in covered.indices where v.seenSamples[f][i] { covered[i] = true } }
            let whole = Double(covered.filter { $0 }.count) / Double(max(1, covered.count)) > 0.85
            out.append("\(name) (\(Int(facades[f].length)) m), " + (whole ? "seen whole from these stations:" : "these stations show \(scene.part(f, covered)), no photo the rest:") + "\n"
                       + (0..<StreetScene.stations).map { k -> String in
                           let station = scene.stationName(f, k)
                           guard !atStation[f][k].isEmpty else { return "  \(station): no photo stands there." }
                           return "  \(station):\n" + atStation[f][k].map { v in
                               let frames = views.filter { $0.photo.sequence == v.photo.sequence }.count
                               return "    #\(taken[v.photo.id]!) " + v.line(scene) + " (\(frames) frames of its track show the landmark)"
                           }.joined(separator: "\n")
                       }.joined(separator: "\n"))
        }
        return (out.joined(separator: "\n"), picks, stations)
    }

    /// The best looks at each facade, one to `count` (the user, 2026-10-27:
    /// of ten photos of a side, the agent and the user know the few that
    /// count): the photos taken at its stations ranked by how much of it
    /// they show, how square on, large and near, the photo's own worth
    /// (date, pose, quality, daylight) and how sure the scene classifier is
    /// of a building (`building`, by photo id); the best first, then the
    /// best from another station (another angle: square on, from a corner)
    /// when it is three fifths as good, else the next best from any,
    /// each photo the best of one facade only, the longest facade first.
    static func best(_ stations: [(facade: Int, station: Int, view: StreetView)], in scene: StreetScene,
                     building: [String: Double], count: Int = 3) -> [Int: [StreetView]] {
        var chosen: [Int: [StreetView]] = [:]
        var used = Set<String>()
        for f in scene.facades.indices.sorted(by: { scene.facades[$0].length > scene.facades[$1].length }) {
            func worth(_ v: StreetView) -> Double { v.looks[f] * v.seen[f] * (0.5 + 0.5 * (building[v.photo.id] ?? 1)) }
            let mine = stations.filter { $0.facade == f && !used.contains($0.view.photo.id) }.sorted { worth($0.view) > worth($1.view) }
            var taken: [(station: Int, view: StreetView)] = []
            // Another angle only when it is a good look too: three fifths of
            // the best at least (a station whose best is a sliver under the
            // sky gives way to a second look from a good one).
            let floor = 0.6 * (mine.first.map { worth($0.view) } ?? 0)
            for c in mine where taken.count < count && worth(c.view) >= floor
                && !taken.contains(where: { $0.station == c.station || $0.view.photo.id == c.view.photo.id }) {
                taken.append((c.station, c.view))
            }
            // Short of stations, the next best from any.
            for c in mine where taken.count < count && !taken.contains(where: { $0.view.photo.id == c.view.photo.id }) {
                taken.append((c.station, c.view))
            }
            for t in taken { used.insert(t.view.photo.id) }
            if !taken.isEmpty { chosen[f] = taken.map(\.view) }
        }
        return chosen
    }

    /// A contact sheet of the picks: their thumbnails in a grid, the landmark
    /// framed in red on each, numbered as the report numbers them, so the
    /// agent sees at once which really show it.
    static func sheet(_ picks: [StreetView], in scene: StreetScene, thumbs: [URL?], to file: URL) throws {
        let cells = picks.enumerated().map { k, view -> ContactSheet.Cell in
            ContactSheet.Cell(image: thumbs[k], box: view.box, cut: view.photo.pano,
                              label: "#\(k + 1)  \(view.photo.id)  \(Int(view.distance)) m, \(scene.facades[view.best].name)")
        }
        try ContactSheet.draw(cells, to: file)
    }
}
