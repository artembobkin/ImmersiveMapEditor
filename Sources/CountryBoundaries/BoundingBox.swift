/// A latitude and longitude range, the input of the area lookups.
///
/// Ported from `bbox.rs` of the Rust crate country-boundaries 1.2.0 (Apache-2.0).

/// A box between two latitudes and two longitudes in degrees. It may wrap around the 180th
/// meridian: a minimum longitude of 170 with a maximum of -170 is a box 20 degrees wide.
public struct BoundingBox: Equatable, Sendable, CustomStringConvertible {
    public let minLatitude: Double
    public let minLongitude: Double
    public let maxLatitude: Double
    public let maxLongitude: Double

    /// Creates a box, or throws if a latitude is not within -90...90, the minimum latitude is
    /// greater than the maximum one, or a longitude is not finite. The checks run in this order.
    public init(minLatitude: Double, minLongitude: Double, maxLatitude: Double, maxLongitude: Double) throws {
        if !(-90.0...90.0).contains(minLatitude) {
            throw CountryBoundariesError.latitudeOutOfBounds(param: "min_latitude", latitude: minLatitude)
        }
        if !(-90.0...90.0).contains(maxLatitude) {
            throw CountryBoundariesError.latitudeOutOfBounds(param: "max_latitude", latitude: maxLatitude)
        }
        if minLatitude > maxLatitude {
            throw CountryBoundariesError.minLatitudeGreaterThanMaxLatitude(
                minLatitude: minLatitude, maxLatitude: maxLatitude)
        }
        if !minLongitude.isFinite {
            throw CountryBoundariesError.longitudeNotFinite(param: "min_longitude", longitude: minLongitude)
        }
        if !maxLongitude.isFinite {
            throw CountryBoundariesError.longitudeNotFinite(param: "max_longitude", longitude: maxLongitude)
        }
        self.minLatitude = minLatitude
        self.minLongitude = minLongitude
        self.maxLatitude = maxLatitude
        self.maxLongitude = maxLongitude
    }

    public var description: String {
        "min: \(minLatitude), \(minLongitude), max: \(maxLatitude), \(maxLongitude)"
    }
}
