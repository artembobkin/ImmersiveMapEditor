/// A position on the earth in degrees, the input of the point lookups.
///
/// Ported from `latlon.rs` of the Rust crate country-boundaries 1.2.0 (Apache-2.0).

/// A latitude and a longitude in degrees. The latitude is within -90...90, the longitude may
/// be any finite value (it is normalized when looked up).
public struct LatLon: Equatable, Sendable, CustomStringConvertible {
    public let latitude: Double
    public let longitude: Double

    /// Creates a position, or throws if the latitude is not within -90...90 (NaN included) or
    /// the longitude is not finite.
    public init(latitude: Double, longitude: Double) throws {
        if !(-90.0...90.0).contains(latitude) {
            throw CountryBoundariesError.latitudeOutOfBounds(param: "latitude", latitude: latitude)
        }
        if !longitude.isFinite {
            throw CountryBoundariesError.longitudeNotFinite(param: "longitude", longitude: longitude)
        }
        self.latitude = latitude
        self.longitude = longitude
    }

    public var description: String {
        "\(latitude), \(longitude)"
    }
}
