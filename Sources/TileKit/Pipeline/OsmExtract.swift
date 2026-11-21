import Foundation

/// An OSM extract the user downloaded (Geofabrik's `.osm.pbf` of a region,
/// or any PBF file), kept in the data folder's `sources/osm/`: the one
/// source of a tile's OSM since the user, 2026-11-21, wanted no public API
/// asked (Overpass, overloaded and down half the time, before). A tile one
/// extract's box holds whole is cut from every extract whose box meets it,
/// their elements put together: a region is no rectangle, so the box of
/// New Jersey holds Lower Manhattan with none of its buildings, and a
/// relation is cut at its region's edge (New York's has none of New
/// Jersey's shore of the bay they share). A tile no extract holds is
/// refused with the way to get one.
///
/// The cut is what the Overpass query asked for (`Fetch`): every node in
/// the box, every way with a node in it, every multipolygon and building
/// relation with a member in it, and down from those every node of the
/// ways and every way and node of the relations, so an outline is never
/// open. It takes three reads: every extract whole once, then only the
/// blocks holding the relations' ways and the ways' nodes still missing,
/// told by the ids each block was seen to hold. What no extract holds is
/// counted. A way that crosses the box with no node in it, which Overpass
/// would give, is left out; the box has a margin of 100 m around the tile.
public struct OsmExtract {
    public let url: URL
    public let south, west, north, east: Double
    /// When the data was taken from OSM, when the file says.
    public let timestamp: Date?

    public var name: String { url.lastPathComponent }

    /// A box in degrees, the tile's with its margin.
    public struct Box {
        public var south, west, north, east: Double
        func contains(lat: Double, lon: Double) -> Bool { lat >= south && lat <= north && lon >= west && lon <= east }
    }

    /// The folder the extracts are kept in.
    public static func folder(_ paths: WorkspacePaths) -> URL {
        paths.root.appendingPathComponent("sources").appendingPathComponent("osm")
    }

    /// Every extract of the data folder with its header read; a file that
    /// is no PBF is skipped and named.
    public static func all(_ paths: WorkspacePaths) -> (extracts: [OsmExtract], unreadable: [String]) {
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder(paths), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.lowercased().hasSuffix(".osm.pbf") || $0.pathExtension.lowercased() == "pbf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var extracts: [OsmExtract] = [], unreadable: [String] = []
        for file in files {
            if let header = try? PbfFile(file).header() {
                extracts.append(OsmExtract(url: file, south: header.south, west: header.west, north: header.north, east: header.east,
                                           timestamp: header.timestamp))
            } else {
                unreadable.append(file.lastPathComponent)
            }
        }
        return (extracts, unreadable)
    }

    /// Whether the extract's box holds the box whole.
    func holds(_ box: Box) -> Bool { south <= box.south && north >= box.north && west <= box.west && east >= box.east }

    /// Whether the extract's box meets the box.
    func meets(_ box: Box) -> Bool { south <= box.north && north >= box.south && west <= box.east && east >= box.west }

    /// The extracts to cut the box from: every one whose box meets it, when
    /// one holds it whole; none otherwise.
    public static func sources(for box: Box, in extracts: [OsmExtract]) -> [OsmExtract] {
        extracts.contains { $0.holds(box) } ? extracts.filter { $0.meets(box) } : []
    }

    /// The elements of each box, in OSM's order (nodes, ways, relations,
    /// each by id), as a fetch from Overpass gave them, cut from `extracts`
    /// together, and what of the relations reaching in none of them holds.
    static func cut(_ boxes: [Box], from extracts: [OsmExtract]) throws -> (elements: [Osm.Elements], missing: (ways: Int, nodes: Int)) {
        // Up to 64 boxes a run, one bit of a mask each.
        var out: [Osm.Elements] = [], missing = (ways: 0, nodes: 0)
        for start in stride(from: 0, to: boxes.count, by: 64) {
            let run = try cutRun(Array(boxes[start..<min(boxes.count, start + 64)]), from: extracts)
            out += run.elements
            missing.ways += run.missing.ways
            missing.nodes += run.missing.nodes
        }
        return (out, missing)
    }

    /// A file being read, with what its first read saw of each block.
    private struct Source {
        let name: String
        let file: PbfFile
        let places: [PbfFile.BlobPlace]
        var summaries: [PbfBlock.Summary] = []

        init(_ extract: OsmExtract) throws {
            name = extract.name
            file = try PbfFile(extract.url)
            places = try file.places().filter(\.isData)
        }
    }

    private static func cutRun(_ boxes: [Box], from extracts: [OsmExtract]) throws
        -> (elements: [Osm.Elements], missing: (ways: Int, nodes: Int)) {
        var sources = try extracts.map(Source.init)
        var nodes: [Int64: OsmNode] = [:], nodeMask: [Int64: UInt64] = [:]
        var ways: [Int64: OsmWay] = [:], wayMask: [Int64: UInt64] = [:]
        var relations: [Int64: OsmRelation] = [:], relationMask: [Int64: UInt64] = [:]
        var neededWays: [Int64: UInt64] = [:]
        func mask(lat: Double, lon: Double) -> UInt64 {
            var m: UInt64 = 0
            for (i, box) in boxes.enumerated() where box.contains(lat: lat, lon: lon) { m |= 1 << UInt64(i) }
            return m
        }

        // The first read, of every extract: the nodes in the boxes, the ways
        // through them and the relations with a member there. An element
        // two extracts hold is the same, kept once.
        for s in sources.indices {
            let source = sources[s]
            var summaries: [PbfBlock.Summary] = []
            for (index, place) in source.places.enumerated() {
                Progress.report("Reading \(source.name)", fraction: Double(index) / Double(source.places.count) / 2,
                                detail: "the nodes, ways and relations in the tile")
                var summary = PbfBlock.Summary()
                var visitor = PbfBlock.Visitor()
                visitor.node = { id, lat, lon, tags in
                    summary.saw(.nodes, id)
                    let m = mask(lat: lat, lon: lon)
                    guard m != 0 else { return }
                    if nodes[id] == nil { nodes[id] = OsmNode(id: id, lat: lat, lon: lon, tags: tags()) }
                    nodeMask[id, default: 0] |= m
                }
                visitor.way = { id, refs, tags in
                    summary.saw(.ways, id)
                    var m: UInt64 = 0
                    for ref in refs { if let n = nodeMask[ref] { m |= n } }
                    guard m != 0 else { return }
                    if ways[id] == nil { ways[id] = OsmWay(id: id, nodes: refs, tags: tags()) }
                    wayMask[id, default: 0] |= m
                }
                visitor.relation = { id, members, refs, tags in
                    summary.saw(.relations, id)
                    var m: UInt64 = 0
                    for member in refs {
                        if member.isNode, let n = nodeMask[member.ref] { m |= n }
                        if member.isWay, let w = wayMask[member.ref] { m |= w }
                    }
                    guard m != 0 else { return }
                    if relations[id] == nil {
                        let t = tags()
                        guard let type = t["type"], type == "multipolygon" || type == "building" else { return }
                        relations[id] = OsmRelation(id: id, members: members(), tags: t)
                    }
                    relationMask[id, default: 0] |= m
                    for member in refs where member.isWay { neededWays[member.ref, default: 0] |= m }
                }
                try PbfBlock.read(try source.file.blob(place), kinds: .all, visitor: visitor)
                summaries.append(summary)
            }
            sources[s].summaries = summaries
        }

        // The relations' ways: those already in hand take the relation's
        // boxes, the rest are read from the blocks that hold them.
        var missingWays: [Int64: UInt64] = [:]
        for (id, m) in neededWays {
            if ways[id] != nil { wayMask[id, default: 0] |= m } else { missingWays[id] = m }
        }
        for source in sources where !missingWays.isEmpty {
            try read(source, kind: .ways, ids: Set(missingWays.keys), share: (0.5, 0.65), what: "the relations' ways") { v in
                v.way = { id, refs, tags in
                    guard let m = missingWays.removeValue(forKey: id) else { return }
                    ways[id] = OsmWay(id: id, nodes: refs, tags: tags())
                    wayMask[id] = m
                }
            }
        }

        // The ways' nodes outside the boxes, and the relations' nodes.
        var neededNodes: [Int64: UInt64] = [:]
        for (id, way) in ways {
            let m = wayMask[id] ?? 0
            for ref in way.nodes { neededNodes[ref, default: 0] |= m }
        }
        for (_, relation) in relations {
            let m = relationMask[relation.id] ?? 0
            for member in relation.members where member.type == "node" { neededNodes[member.ref, default: 0] |= m }
        }
        var missingNodes = Set<Int64>()
        for (id, m) in neededNodes {
            if nodes[id] != nil { nodeMask[id, default: 0] |= m } else { missingNodes.insert(id) }
        }
        for source in sources where !missingNodes.isEmpty {
            try read(source, kind: .nodes, ids: missingNodes, share: (0.65, 1), what: "the nodes of the ways") { v in
                v.node = { id, lat, lon, tags in
                    guard missingNodes.remove(id) != nil else { return }
                    nodes[id] = OsmNode(id: id, lat: lat, lon: lon, tags: tags())
                    nodeMask[id] = neededNodes[id] ?? 0
                }
            }
        }

        let elements = boxes.indices.map { i in
            let bit: UInt64 = 1 << UInt64(i)
            var e = Osm.Elements()
            e.nodeOrder = nodeMask.filter { $0.value & bit != 0 && nodes[$0.key] != nil }.map(\.key).sorted()
            for id in e.nodeOrder { e.nodes[id] = nodes[id] }
            e.wayOrder = wayMask.filter { $0.value & bit != 0 }.map(\.key).sorted()
            for id in e.wayOrder { e.ways[id] = ways[id] }
            e.relations = relationMask.filter { $0.value & bit != 0 }.map(\.key).sorted().compactMap { relations[$0] }
            return e
        }
        return (elements, (missingWays.count, missingNodes.count))
    }

    /// A later read of a source for the elements of `kind` among `ids`: only
    /// the blocks whose ids span one of them.
    private static func read(_ source: Source, kind: PbfBlock.Kinds, ids: Set<Int64>, share: (Double, Double), what: String,
                             visitor make: (inout PbfBlock.Visitor) -> Void) throws {
        let sorted = ids.sorted()
        var visitor = PbfBlock.Visitor()
        make(&visitor)
        let wanted = source.places.indices.filter { i in
            let s = source.summaries[i]
            guard s.kinds.contains(kind) else { return false }
            // The first wanted id at or above the block's lowest.
            var lo = 0, hi = sorted.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if sorted[mid] < s.lowest { lo = mid + 1 } else { hi = mid }
            }
            return lo < sorted.count && sorted[lo] <= s.highest
        }
        for (n, i) in wanted.enumerated() {
            Progress.report("Reading \(source.name)", fraction: share.0 + (share.1 - share.0) * Double(n) / Double(max(1, wanted.count)),
                            detail: what)
            try PbfBlock.read(try source.file.blob(source.places[i]), kinds: kind, visitor: visitor)
        }
    }
}
