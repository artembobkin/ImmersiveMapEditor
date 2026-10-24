/// Lanes recorded per tag set, a `LaneSpecSource` for when the lanes were
/// worked out elsewhere (the parity tests record them from the Rust
/// osm2streets). Also: the tag sets of the ways of an OSM file that become
/// roads, which is what such a record has to cover.

import OSMReader
import StreetGeom

public struct RecordedLaneSpecs: LaneSpecSource {
    public var lanes: [Tags: [LaneSpec]]

    public init(_ lanes: [Tags: [LaneSpec]]) { self.lanes = lanes }

    public func laneSpecsLTR(_ tags: Tags, _ config: MapConfig) -> [LaneSpec] {
        guard let specs = lanes[tags] else { fatalError("No recorded lanes for the tags \(tags.inner())") }
        return specs
    }
}

extension Tags: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(map) }
}

/// The ways of an OSM file that streets_reader turns into roads.
public struct RoadWays {
    /// The frame of the network: the clip's bounds, or the file's.
    public var gpsBounds: GPSBounds
    /// Each distinct tag set once, in the order first met.
    public var tagSets: [Tags]

    /// Reads the file as `StreetNetwork.fromOSM` does, up to the ways it keeps.
    public static func collect(_ input: [UInt8], clip clipPts: [LonLat]?, config: MapConfig) throws -> RoadWays {
        var doc = try Document.read(input, clipPts.map { GPSBounds.from($0) })
        guard let bounds = doc.gpsBounds else { throw StreetsReaderError.noBounds }
        if let pts = clipPts { doc.clip(try Ring.dedupingNew(bounds.convert(pts)).intoPolygon()) }
        var extract = OsmExtract()
        for id in doc.ways.keys { extract.handleWay(id, doc.ways[id]!, config) }
        for (id, way) in doc.clippedCopiedWays { extract.handleWay(id, way, config) }
        var seen = Set<Tags>()
        var tagSets: [Tags] = []
        for (_, _, tags) in extract.roads where seen.insert(tags).inserted { tagSets.append(tags) }
        return RoadWays(gpsBounds: bounds, tagSets: tagSets)
    }
}
