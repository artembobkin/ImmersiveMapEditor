/// The lanes the Rust gives each tag set of a case, read from the Rust
/// itself: Muv's lane reading is not ported (see Docs/PortingStreetsProgress.md),
/// so the parity tests feed the Swift port the Rust's lanes. One synthetic
/// OSM file holds a way per tag set, each crossing the whole box of the case
/// so that clipping makes both ends map edges and nothing collapses. The box
/// is the case's, so the country, and with it Muv's defaults, are the same.

import Foundation
import OSMReader
import StreetGeom
import Streets

enum LaneHarvest {
    static func record(input: [UInt8], clip: [LonLat]?, config: MapConfig, work: URL) throws -> RecordedLaneSpecs {
        let ways = try RoadWays.collect(input, clip: clip, config: config)
        let b = ways.gpsBounds
        let n = ways.tagSets.count
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<osm version=\"0.6\">\n"
        let width = b.maxLon - b.minLon
        let height = b.maxLat - b.minLat
        for (k, _) in ways.tagSets.enumerated() {
            let lat = b.minLat + height * Double(k + 1) / Double(n + 1)
            let lons = [b.minLon - width * 0.1, b.minLon + width * 0.5, b.maxLon + width * 0.1]
            for (j, lon) in lons.enumerated() {
                xml += "<node id=\"\(3 * k + j + 1)\" version=\"1\" lat=\"\(serdeJSONNumber(lat))\" lon=\"\(serdeJSONNumber(lon))\"/>\n"
            }
        }
        for (k, tags) in ways.tagSets.enumerated() {
            xml += "<way id=\"\(k + 1)\" version=\"1\">"
            for j in 0..<3 { xml += "<nd ref=\"\(3 * k + j + 1)\"/>" }
            for (key, value) in tags.inner() { xml += "<tag k=\(xmlQuote(key)) v=\(xmlQuote(value))/>" }
            xml += "</way>\n"
        }
        xml += "</osm>\n"
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let osm = work.appendingPathComponent("harvest.osm")
        try xml.write(to: osm, atomically: true, encoding: .utf8)
        let clipURL = work.appendingPathComponent("harvest_clip.geojson")
        let ring = b.getRectangle().map { "[\(serdeJSONNumber($0.x)), \(serdeJSONNumber($0.y))]" }.joined(separator: ", ")
        try "{\"type\": \"Feature\", \"properties\": {}, \"geometry\": {\"type\": \"Polygon\", \"coordinates\": [[\(ring)]]}}"
            .write(to: clipURL, atomically: true, encoding: .utf8)
        let out = try Oracle.run(input: osm, clip: clipURL, out: work.appendingPathComponent("harvest"))

        // Lanes by road, roads by way.
        var wayOfRoad: [UInt64: Int64] = [:]
        for f in try JSONValue.parse(out["plain"]!)["features"]!.arrayValue! {
            let p = f["properties"]!
            guard p["type"]?.stringValue == "road" else { continue }
            wayOfRoad[uint(p["id"]!)] = int(p["osm_way_ids"]!.arrayValue![0])
        }
        var lanesOfWay: [Int64: [(Int, LaneSpec)]] = [:]
        for f in try JSONValue.parse(out["lanes"]!)["features"]!.arrayValue! {
            let p = f["properties"]!
            let way = wayOfRoad[uint(p["road"]!)]!
            var turns = TurnDirections()
            for t in p["allowed_turns"]!.arrayValue! {
                turns.insert(TurnDirection.allCases.first { $0.tagValue() == t.stringValue! }!)
            }
            let spec = LaneSpec(lt: LaneType.fromRustDebug(p["type"]!.stringValue!)!,
                                dir: p["direction"]!.stringValue! == "Forward" ? .forward : .backward,
                                width: Distance(constMeters: p["width"]!.doubleValue!), allowedTurns: turns, muv: p["muv"])
            lanesOfWay[way, default: []].append((Int(uint(p["index"]!)), spec))
        }
        var table: [Tags: [LaneSpec]] = [:]
        for (k, tags) in ways.tagSets.enumerated() {
            guard let lanes = lanesOfWay[Int64(k + 1)] else { continue }
            table[tags] = lanes.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return RecordedLaneSpecs(table)
    }

    private static func uint(_ v: JSONValue) -> UInt64 {
        switch v {
        case .uint(let u): return u
        case .int(let i): return UInt64(i)
        default: fatalError("not an integer: \(v)")
        }
    }

    private static func int(_ v: JSONValue) -> Int64 {
        switch v {
        case .uint(let u): return Int64(u)
        case .int(let i): return i
        default: fatalError("not an integer: \(v)")
        }
    }
}

func xmlQuote(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") + "\""
}
