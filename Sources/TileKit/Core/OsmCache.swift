import Foundation

/// The elements of a tile's OSM as `osm/osm.bin`, the form they are kept
/// in: Overpass's osm.json is parsed once, written as this (`BinaryCache`,
/// stamped by the JSON) and deleted, the binary a sixth of its size and
/// read in a few hundredths of a second where the JSON, with its metadata
/// of every element, took 0.35 s (the user, 2026-11-03: a format of our
/// own instead of JSON, and the JSON gone to save the disk). Only what
/// `Osm` keeps: ids, coordinates, node lists, members and tags, the tags'
/// and members' strings interned in one table. An osm.json found beside
/// it (an older folder, a fetch) is converted the same way at the next
/// read.
enum OsmCache {
    static let name = "osm.bin"
    static let json = "osm.json"
    static let magic = "OSMB"
    static let version: UInt32 = 1

    /// The elements of a tile's folder: its osm.bin, unless an osm.json is
    /// there that it was not made from, which is then converted: parsed,
    /// written as the binary, read back whole and deleted.
    static func elements(in folder: URL) throws -> Osm.Elements {
        let source = folder.appendingPathComponent(json)
        if FileManager.default.fileExists(atPath: source.path) {
            if let cached = read(folder: folder, stamp: BinaryCache.stamp(of: source)) {
                try? FileManager.default.removeItem(at: source)
                return cached
            }
            return try convert(folder: folder)
        }
        guard let cached = read(folder: folder, stamp: nil) else {
            throw PipelineError("\(folder.appendingPathComponent(name).path) is missing: fetch the tile first")
        }
        return cached
    }

    /// The folder's osm.json parsed and written as its osm.bin; the JSON
    /// deleted only once the binary is read back with the same counts.
    @discardableResult
    static func convert(folder: URL) throws -> Osm.Elements {
        let source = folder.appendingPathComponent(json)
        let e = try Osm.parse(try Data(contentsOf: source))
        let stamp = BinaryCache.stamp(of: source)
        write(e, folder: folder, stamp: stamp)
        if let back = read(folder: folder, stamp: stamp), back.nodeOrder == e.nodeOrder, back.wayOrder == e.wayOrder,
           back.relations.count == e.relations.count {
            try? FileManager.default.removeItem(at: source)
        }
        return e
    }

    /// Whether the folder holds a tile's OSM, in either form.
    static func isThere(_ folder: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: folder.appendingPathComponent(name).path) || fm.fileExists(atPath: folder.appendingPathComponent(json).path)
    }

    /// What the folder's OSM is, for a cache derived from it: the JSON's
    /// stamp while it is there, else the binary's.
    static func stamp(of folder: URL) -> String {
        let source = folder.appendingPathComponent(json)
        return BinaryCache.stamp(of: FileManager.default.fileExists(atPath: source.path) ? source : folder.appendingPathComponent(name))
    }

    /// The elements of a tile's folder from its cache, when it is there and
    /// made from a source of this stamp (any when nil).
    static func read(folder: URL, stamp: String?) -> Osm.Elements? {
        guard var r = BinaryCache.read(folder.appendingPathComponent(name), magic: magic, version: version, stamp: stamp) else { return nil }
        do {
            var strings: [String] = []
            for _ in 0..<(try r.count()) { strings.append(try r.string()) }
            func tags() throws -> Tags {
                var out: Tags = [:]
                for _ in 0..<(try r.count()) {
                    let k = Int(try r.uint32()), v = Int(try r.uint32())
                    guard k < strings.count, v < strings.count else { throw BinaryReader.Short() }
                    out[strings[k]] = strings[v]
                }
                return out
            }
            func interned() throws -> String {
                let i = Int(try r.uint32())
                guard i < strings.count else { throw BinaryReader.Short() }
                return strings[i]
            }
            var e = Osm.Elements()
            for _ in 0..<(try r.count()) {
                let id = try r.int64()
                e.nodes[id] = OsmNode(id: id, lat: try r.double(), lon: try r.double(), tags: try tags())
                e.nodeOrder.append(id)
            }
            for _ in 0..<(try r.count()) {
                let id = try r.int64()
                var nodes: [Int64] = []
                for _ in 0..<(try r.count()) { nodes.append(try r.int64()) }
                e.ways[id] = OsmWay(id: id, nodes: nodes, tags: try tags())
                e.wayOrder.append(id)
            }
            for _ in 0..<(try r.count()) {
                let id = try r.int64()
                var members: [OsmMember] = []
                for _ in 0..<(try r.count()) {
                    members.append(OsmMember(type: try interned(), ref: try r.int64(), role: try interned()))
                }
                e.relations.append(OsmRelation(id: id, members: members, tags: try tags()))
            }
            return e
        } catch {
            return nil
        }
    }

    /// The elements written as the folder's cache; a folder that cannot be
    /// written to just has none.
    static func write(_ e: Osm.Elements, folder: URL, stamp: String) {
        var strings: [String: UInt32] = [:]
        var table: [String] = []
        func intern(_ s: String) -> UInt32 {
            if let i = strings[s] { return i }
            let i = UInt32(table.count)
            strings[s] = i
            table.append(s)
            return i
        }
        // The strings first, so they are interned before the body is written.
        var body = BinaryWriter()
        func tags(_ t: Tags) {
            body.count(t.count)
            for (k, v) in t.sorted(by: { $0.key < $1.key }) {
                body.uint32(intern(k))
                body.uint32(intern(v))
            }
        }
        let nodes = e.nodeOrder.compactMap { e.nodes[$0] }, ways = e.wayOrder.compactMap { e.ways[$0] }
        body.count(nodes.count)
        for n in nodes {
            body.int64(n.id)
            body.double(n.lat)
            body.double(n.lon)
            tags(n.tags)
        }
        body.count(ways.count)
        for w in ways {
            body.int64(w.id)
            body.count(w.nodes.count)
            for n in w.nodes { body.int64(n) }
            tags(w.tags)
        }
        body.count(e.relations.count)
        for rel in e.relations {
            body.int64(rel.id)
            body.count(rel.members.count)
            for m in rel.members {
                body.uint32(intern(m.type))
                body.int64(m.ref)
                body.uint32(intern(m.role))
            }
            tags(rel.tags)
        }
        var w = BinaryCache.writer(magic: magic, version: version, stamp: stamp)
        w.count(table.count)
        for s in table { w.string(s) }
        var data = w.data
        data.append(body.data)
        try? data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }
}
