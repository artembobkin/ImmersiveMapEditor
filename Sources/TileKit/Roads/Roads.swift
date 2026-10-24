import Foundation
import Geometry


/// Seeding the road document from osm2streets, and reading it for a build.
public enum Roads {
    static let roadClasses: [String: Double] = ["primary": 14, "secondary": 11, "tertiary": 8, "unclassified": 6,
                                                 "residential": 6, "living_street": 5, "service": 4]
    static let sett: Set<String> = ["sett", "cobblestone", "unhewn_cobblestone"]
    static let drive: Set<String> = ["Driving", "Bus", "SharedLeftTurn", "Parking(Parallel)", "Parking(Perpendicular)",
                                     "Parking(Diagonal)", "Biking", "Shoulder", "Construction", "LightRail"]
    static let smoothClose = 2.0    // the roadway's closing, filling notches
    static let smoothOpen = 0.6     // and its opening, dropping spikes
    static let taper = 12.0         // how far a road's change of width is spread

    /// Valid, on a 1 cm grid: overlay operations on lane polygons that
    /// touch and nearly overlap stay robust.
    public static func clean(_ g: Geometry) -> Geometry { g.makeValid().setPrecision(0.01).makeValid() }
}
