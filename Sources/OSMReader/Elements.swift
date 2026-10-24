/// The OSM elements osm-reader hands to its caller: ids and the `Element`
/// enum, as osm-reader's `lib.rs` defines them.

/// The revision of osm-reader this target follows.
public enum OSMReaderPort {
    public static let source = "osm-reader 7892405"
}

/// An OSM node id.
public struct NodeID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var id: Int64
    public init(_ id: Int64) { self.id = id }
    public static func < (a: NodeID, b: NodeID) -> Bool { a.id < b.id }
    public var description: String { "https://www.openstreetmap.org/node/\(id)" }
}

/// An OSM way id.
public struct WayID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var id: Int64
    public init(_ id: Int64) { self.id = id }
    public static func < (a: WayID, b: WayID) -> Bool { a.id < b.id }
    public var description: String { "https://www.openstreetmap.org/way/\(id)" }
}

/// An OSM relation id.
public struct RelationID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var id: Int64
    public init(_ id: Int64) { self.id = id }
    public static func < (a: RelationID, b: RelationID) -> Bool { a.id < b.id }
    public var description: String { "https://www.openstreetmap.org/relation/\(id)" }
}

/// Any OSM id. The order is Rust's derived `Ord`: nodes, then ways, then
/// relations, each by id.
public enum OsmID: Hashable, Comparable, Sendable, CustomStringConvertible {
    case node(NodeID)
    case way(WayID)
    case relation(RelationID)

    public var innerID: Int64 {
        switch self {
        case .node(let n): return n.id
        case .way(let w): return w.id
        case .relation(let r): return r.id
        }
    }

    private var rank: Int {
        switch self {
        case .node: return 0
        case .way: return 1
        case .relation: return 2
        }
    }

    public static func < (a: OsmID, b: OsmID) -> Bool {
        if a.rank != b.rank { return a.rank < b.rank }
        return a.innerID < b.innerID
    }

    public var description: String {
        switch self {
        case .node(let n): return n.description
        case .way(let w): return w.description
        case .relation(let r): return r.description
        }
    }
}

/// One element of an OSM file, in the order of the file.
public enum Element {
    /// The file-wide replication timestamp (seconds since the epoch), if present.
    case timestamp(Int64)
    case bounds(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double)
    case node(id: NodeID, lon: Double, lat: Double, tags: [String: String], version: Int32?)
    case way(id: WayID, nodeIDs: [NodeID], tags: [String: String], version: Int32?)
    /// Members are (role, member id).
    case relation(id: RelationID, tags: [String: String], members: [(String, OsmID)], version: Int32?)
}

/// Why a file could not be read.
public enum OSMReaderError: Error, CustomStringConvertible {
    case notUTF8
    case malformedXML(String)
    case missingAttribute(element: String, attribute: String)
    case badNumber(String)
    /// PBF input: osm-reader reads it, this port does not (the pipeline writes XML).
    case pbfNotSupported

    public var description: String {
        switch self {
        case .notUTF8: return "the input is not UTF-8"
        case .malformedXML(let message): return "malformed XML: \(message)"
        case .missingAttribute(let element, let attribute): return "<\(element)> has no \(attribute)"
        case .badNumber(let text): return "not a number: \(text)"
        case .pbfNotSupported: return "PBF input is not supported by the Swift port"
        }
    }
}

/// Parses an OSM XML file and calls `callback` for every element, in the
/// order of the file (nodes, then ways, then relations, for a well-formed
/// file). PBF is recognised as osm-reader does (no `<?xml` header) and refused.
public func parse(_ input: [UInt8], _ callback: (Element) throws -> Void) throws {
    if isXML(input) {
        try parseXML(input, callback)
    } else {
        throw OSMReaderError.pbfNotSupported
    }
}

/// osm-reader's `is_xml`: the first five bytes are `<?xml`, in any case.
func isXML(_ input: [UInt8]) -> Bool {
    let header = "<?xml"
    if input.count < header.utf8.count { return false }
    guard let text = String(validating: input[0..<header.utf8.count], as: UTF8.self) else { return false }
    return text.lowercased() == header
}
