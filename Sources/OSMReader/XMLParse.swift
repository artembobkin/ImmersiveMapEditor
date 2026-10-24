/// osm-reader's `parse_xml`: every node, way, relation, bounds and meta
/// element of an OSM XML document, in document order.

import Foundation

func parseXML(_ input: [UInt8], _ callback: (Element) throws -> Void) throws {
    guard String(validating: input, as: UTF8.self) != nil else { throw OSMReaderError.notUTF8 }
    let tree = try XMLTree(input)
    let elements = tree.elements
    for obj in elements {
        switch obj.name {
        case "meta":
            if let timestamp = obj.attribute("osm_base"), let seconds = parseTimestamp(timestamp) {
                try callback(.timestamp(seconds))
            }
        case "bounds":
            try callback(.bounds(minLon: try double(obj, "minlon"), minLat: try double(obj, "minlat"),
                                 maxLon: try double(obj, "maxlon"), maxLat: try double(obj, "maxlat")))
        case "node":
            let id = NodeID(try int64(obj, "id"))
            let lon = try double(obj, "lon")
            let lat = try double(obj, "lat")
            try callback(.node(id: id, lon: lon, lat: lat, tags: try readTags(obj, elements),
                               version: obj.attribute("version").flatMap { Int32($0) }))
        case "way":
            let id = WayID(try int64(obj, "id"))
            let tags = try readTags(obj, elements)
            let version = obj.attribute("version").flatMap { Int32($0) }
            var nodeIDs: [NodeID] = []
            for c in obj.children where elements[c].name == "nd" {
                nodeIDs.append(NodeID(try int64(elements[c], "ref")))
            }
            try callback(.way(id: id, nodeIDs: nodeIDs, tags: tags, version: version))
        case "relation":
            let id = RelationID(try int64(obj, "id"))
            let tags = try readTags(obj, elements)
            let version = obj.attribute("version").flatMap { Int32($0) }
            var members: [(String, OsmID)] = []
            for c in obj.children where elements[c].name == "member" {
                let child = elements[c]
                guard let type = child.attribute("type") else {
                    throw OSMReaderError.missingAttribute(element: "member", attribute: "type")
                }
                let member: OsmID
                switch type {
                case "node": member = .node(NodeID(try int64(child, "ref")))
                case "way": member = .way(WayID(try int64(child, "ref")))
                case "relation": member = .relation(RelationID(try int64(child, "ref")))
                default: continue
                }
                guard let role = child.attribute("role") else {
                    throw OSMReaderError.missingAttribute(element: "member", attribute: "role")
                }
                members.append((role, member))
            }
            try callback(.relation(id: id, tags: tags, members: members, version: version))
        default:
            break
        }
    }
}

/// The `tag` children as a map. A repeated key keeps its last value, as
/// inserting into a Rust `HashMap` does.
private func readTags(_ obj: XMLElement, _ elements: [XMLElement]) throws -> [String: String] {
    var tags: [String: String] = [:]
    for c in obj.children where elements[c].name == "tag" {
        guard let k = elements[c].attribute("k") else {
            throw OSMReaderError.missingAttribute(element: "tag", attribute: "k")
        }
        guard let v = elements[c].attribute("v") else {
            throw OSMReaderError.missingAttribute(element: "tag", attribute: "v")
        }
        tags[k] = v
    }
    return tags
}

private func attribute(_ obj: XMLElement, _ key: String) throws -> String {
    guard let value = obj.attribute(key) else {
        throw OSMReaderError.missingAttribute(element: obj.name, attribute: key)
    }
    return value
}

private func double(_ obj: XMLElement, _ key: String) throws -> Double {
    let text = try attribute(obj, key)
    guard let value = parseRustF64(text) else { throw OSMReaderError.badNumber(text) }
    return value
}

private func int64(_ obj: XMLElement, _ key: String) throws -> Int64 {
    let text = try attribute(obj, key)
    guard let value = Int64(text) else { throw OSMReaderError.badNumber(text) }
    return value
}

/// Rust's `str::parse::<f64>`: decimal digits with an optional sign, point
/// and exponent, or `inf`, `infinity`, `nan` in any case. Hexadecimal floats,
/// which `Double.init` would take, are refused as Rust refuses them.
public func parseRustF64(_ text: String) -> Double? {
    let lower = text.lowercased()
    let unsigned = lower.hasPrefix("+") || lower.hasPrefix("-") ? String(lower.dropFirst()) : lower
    if unsigned == "inf" || unsigned == "infinity" || unsigned == "nan" {
        let sign: Double = lower.hasPrefix("-") ? -1 : 1
        return unsigned == "nan" ? Double.nan : sign * Double.infinity
    }
    var sawDigit = false
    for c in unsigned.utf8 {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): sawDigit = true
        case UInt8(ascii: "."), UInt8(ascii: "e"), UInt8(ascii: "+"), UInt8(ascii: "-"): break
        default: return nil
        }
    }
    guard sawDigit else { return nil }
    return Double(text)
}

/// chrono's `DateTime<Utc>` parse of an RFC 3339 time, as seconds since the epoch.
private func parseTimestamp(_ text: String) -> Int64? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: text) { return Int64(date.timeIntervalSince1970.rounded(.down)) }
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return Int64(date.timeIntervalSince1970.rounded(.down)) }
    return nil
}
