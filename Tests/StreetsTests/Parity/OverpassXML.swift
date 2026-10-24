/// Overpass JSON as OSM XML, as TileKit's `Seed.osmXML` writes it for the
/// Rust binary (copied, the test target does not depend on TileKit). Both
/// sides of a parity test read the same written file.

import Foundation

enum OverpassXML {
    static func convert(_ data: Data) throws -> String {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let elements = (root["elements"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        func q(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") + "\""
        }
        let order = ["node": 0, "way": 1, "relation": 2]
        let sorted = elements.sorted {
            let a = (order[$0["type"] as? String ?? ""] ?? 3, ($0["id"] as? NSNumber)?.int64Value ?? 0)
            let b = (order[$1["type"] as? String ?? ""] ?? 3, ($1["id"] as? NSNumber)?.int64Value ?? 0)
            return a < b
        }
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<osm version=\"0.6\" generator=\"TilePipeline\">\n"
        for e in sorted {
            let meta = "id=\"\(e["id"] ?? 0)\" version=\"\(e["version"] ?? 1)\""
            let tags = (e["tags"] as? [String: Any] ?? [:]).map { "<tag k=\(q($0.key)) v=\(q("\($0.value)"))/>" }.joined()
            switch e["type"] as? String {
            case "node":
                out += "<node \(meta) lat=\"\(e["lat"] ?? 0)\" lon=\"\(e["lon"] ?? 0)\">\(tags)</node>\n"
            case "way":
                let refs = (e["nodes"] as? [Any] ?? []).map { "<nd ref=\"\($0)\"/>" }.joined()
                out += "<way \(meta)>\(refs)\(tags)</way>\n"
            default:
                let members = (e["members"] as? [[String: Any]] ?? []).map {
                    "<member type=\"\($0["type"] ?? "")\" ref=\"\($0["ref"] ?? 0)\" role=\(q($0["role"] as? String ?? ""))/>"
                }.joined()
                out += "<relation \(meta)>\(members)\(tags)</relation>\n"
            }
        }
        return out + "</osm>\n"
    }
}
