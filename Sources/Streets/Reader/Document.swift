/// streets_reader's `Document`: the OSM file's nodes, ways and relations in
/// world space, read through OSMReader, and clipped to the boundary.

import OSMReader
import StreetGeom

struct Node {
    var pt: Pt2D
    var tags: Tags
}

struct Way {
    /// The geometry is duplicated, for convenience.
    var nodes: [NodeID]
    var pts: [Pt2D]
    var tags: Tags
}

struct Relation {
    var tags: Tags
    /// Role, member.
    var members: [(String, OsmID)]
}

enum StreetsReaderError: Error, CustomStringConvertible {
    case noBounds
    case corrupt(String)
    var description: String {
        switch self {
        case .noBounds: return "Failed to extract GPS bounds from the OSM input"
        case .corrupt(let m): return m
        }
    }
}

struct Document {
    var gpsBounds: GPSBounds?
    var nodes = SortedMap<NodeID, Node>()
    var ways = SortedMap<WayID, Way>()
    var relations = SortedMap<RelationID, Relation>()
    /// These share a way id, each with its own points.
    var clippedCopiedWays: [(WayID, Way)] = []

    /// Reads every object. Missing references are filtered out.
    static func read(_ input: [UInt8], _ gpsBounds: GPSBounds?) throws -> Document {
        var doc = Document(gpsBounds: gpsBounds)
        try OSMReader.parse(input) { elem in
            switch elem {
            case .timestamp:
                break
            case .bounds(let minLon, let minLat, let maxLon, let maxLat):
                if doc.gpsBounds == nil {
                    doc.gpsBounds = GPSBounds.from([LonLat(minLon, minLat), LonLat(maxLon, maxLat)])
                }
            case .node(let id, let lon, let lat, let tags, _):
                if doc.gpsBounds == nil { doc.gpsBounds = try scrapeBounds(input) }
                if doc.nodes.contains(id) { throw StreetsReaderError.corrupt("Duplicate \(id), your .osm is corrupt") }
                let pt = LonLat(lon, lat).toPt(doc.gpsBounds!)
                doc.nodes[id] = Node(pt: pt, tags: Tags(tags))
            case .way(let id, let nodeIDs, let tags, _):
                if doc.ways.contains(id) { throw StreetsReaderError.corrupt("Duplicate \(id), your .osm is corrupt") }
                var pts: [Pt2D] = []
                var nodes: [NodeID] = []
                for n in nodeIDs {
                    if let node = doc.nodes[n] {
                        nodes.append(n)
                        pts.append(node.pt)
                    }
                }
                if !nodes.isEmpty { doc.ways[id] = Way(nodes: nodes, pts: pts, tags: Tags(tags)) }
            case .relation(let id, let tags, let members, _):
                if doc.relations.contains(id) {
                    throw StreetsReaderError.corrupt("Duplicate \(id), your .osm is corrupt")
                }
                let kept = members.filter { member in
                    switch member.1 {
                    case .node(let n): return doc.nodes.contains(n)
                    case .way(let w): return doc.ways.contains(w)
                    case .relation(let r): return doc.relations.contains(r)
                    }
                }
                doc.relations[id] = Relation(tags: Tags(tags), members: kept)
            }
        }
        return doc
    }

    private static func scrapeBounds(_ input: [UInt8]) throws -> GPSBounds {
        var b = GPSBounds()
        try OSMReader.parse(input) { elem in
            if case .node(_, let lon, let lat, _, _) = elem { b.update(LonLat(lon, lat)) }
        }
        return b
    }

    /// Keeps the nodes inside the boundary and the ways with a node inside,
    /// and clips the roads to it.
    mutating func clip(_ boundaryPolygon: Polygon) {
        var keptNodes = SortedMap<NodeID, Node>()
        for id in nodes.keys where boundaryPolygon.containsPt(nodes[id]!.pt) { keptNodes[id] = nodes[id]! }
        nodes = keptNodes
        var keptWays = SortedMap<WayID, Way>()
        for id in ways.keys where ways[id]!.nodes.contains(where: { nodes.contains($0) }) { keptWays[id] = ways[id]! }
        ways = keptWays

        for id in ways.keys {
            var way = ways[id]!
            // Only roads. Areas need more work.
            if !way.tags.hasAny(["highway", "railway"]) { continue }
            var wayPts = way.pts
            wayPts.dedup()
            var polylines = clipPolylineToRing(PolyLine.uncheckedNew(wayPts), boundaryPolygon)
            if polylines.count == 1 {
                way.pts = polylines.removeLast().points
                ways[id] = way
                continue
            }
            for pl in polylines {
                var copy = way
                copy.pts = pl.points
                clippedCopiedWays.append((id, copy))
            }
        }
        for (id, _) in clippedCopiedWays { ways.removeValue(forKey: id) }

        for id in relations.keys {
            relations.modify(id) { relation in
                relation.members.removeAll { member in
                    switch member.1 {
                    case .node(let x): return !nodes.contains(x)
                    case .way(let x): return !ways.contains(x)
                    case .relation: return false
                    }
                }
            }
        }
        for id in relations.keys where relations[id]!.members.isEmpty { relations.removeValue(forKey: id) }
    }
}

/// Splits a polyline where it crosses the polygon, keeping the pieces inside.
func clipPolylineToRing(_ pl: PolyLine, _ polygon: Polygon) -> [PolyLine] {
    var hitDistances: [Distance] = []
    for pt in polygon.getOuterRing().allIntersections(pl) {
        guard let (dist, _) = pl.distAlongOfPoint(pt) else { return [pl] }
        hitDistances.append(dist)
    }
    hitDistances.sort()
    var start = Distance.zero
    var slices: [PolyLine] = []
    for dist in hitDistances {
        if let slice = try? pl.maybeExactSlice(start, dist) { slices.append(slice) }
        start = dist
    }
    if let last = try? pl.maybeExactSlice(start, pl.length) { slices.append(last) }
    return slices.filter { polygon.containsPt($0.middle()) }
}
