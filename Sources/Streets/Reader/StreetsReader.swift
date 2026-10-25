/// streets_reader's entry point: an OSM XML file to a street network, with
/// the country code and driving side found from the map's position.

import CountryBoundaries
import OSMReader
import StreetGeom

extension StreetNetwork {
    /// streets_reader's `osm_to_street_network`. `clipPts` is the boundary
    /// polygon in longitude and latitude, or nil to use the file's bounds.
    public static func fromOSM(_ input: [UInt8], clip clipPts: [LonLat]?, config: MapConfig,
                               laneSpecs: LaneSpecSource = MuvLaneSpecs()) throws -> StreetNetwork {
        try fromOSM(input, clip: clipPts, config: config, laneSpecs: laneSpecs, hashMapOrder: nil)
    }

    /// `fromOSM` with the signals and crossings applied in the order a
    /// `HashMapOrder` gives, recording where the order matters (parity tests).
    static func fromOSM(_ input: [UInt8], clip clipPts: [LonLat]?, config: MapConfig,
                        laneSpecs: LaneSpecSource = MuvLaneSpecs(), hashMapOrder: HashMapOrder?) throws -> StreetNetwork {
        var streets = StreetNetwork.blank(laneSpecs: laneSpecs)
        streets.config = config
        streets.hashMapOrder = hashMapOrder
        let extract = try streets.extractOSM(input, clipPts)
        streets.splitUpRoads(extract)
        streets.hashMapOrder = nil
        // Cul-de-sacs aren't supported yet.
        streets.retainRoads { $0.srcI != $0.dstI }
        return streets
    }

    /// Sets the country code and driving side from an arbitrary point (the
    /// first corner of the bounds). Needs `gpsBounds`.
    public mutating func detectCountryCode() {
        if let dir = config.overrideDrivingSide {
            config.drivingSide = dir
            return
        }
        let pt = gpsBounds.getRectangle()[0]
        guard let position = try? LatLon(latitude: pt.y, longitude: pt.x) else { return }
        let codes = CountryBoundaries.odbl60x30.ids(position)
        for code in codes {
            if let side = drivingSide(code) {
                config.countryCode = code
                config.drivingSide = side == .left ? .left : .right
                return
            }
        }
    }

    mutating func extractOSM(_ input: [UInt8], _ clipPts: [LonLat]?) throws -> OsmExtract {
        var doc = try Document.read(input, clipPts.map { GPSBounds.from($0) })
        guard let bounds = doc.gpsBounds else { throw StreetsReaderError.noBounds }
        gpsBounds = bounds
        if let pts = clipPts {
            boundaryPolygon = try Ring.dedupingNew(gpsBounds.convert(pts)).intoPolygon()
            doc.clip(boundaryPolygon)
        } else {
            boundaryPolygon = gpsBounds.toBounds().getRectangle()
        }
        detectCountryCode()
        var out = OsmExtract()
        for id in doc.nodes.keys { out.handleNode(id, doc.nodes[id]!) }
        for id in doc.ways.keys { out.handleWay(id, doc.ways[id]!, config) }
        for (id, way) in doc.clippedCopiedWays { out.handleWay(id, way, config) }
        for id in doc.relations.keys { out.handleRelation(id, doc.relations[id]!) }
        return out
    }
}
