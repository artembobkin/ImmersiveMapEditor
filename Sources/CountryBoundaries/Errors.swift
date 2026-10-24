/// The errors of country-boundaries: invalid coordinates and unreadable boundary data.
///
/// Ported from `error.rs` and the `ReadError` of `deserializer.rs` of the Rust crate
/// country-boundaries 1.2.0 (Apache-2.0).

/// An invalid coordinate given to `LatLon` or `BoundingBox`.
public enum CountryBoundariesError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A longitude that is NaN or infinite.
    case longitudeNotFinite(param: String, longitude: Double)
    /// A latitude that is NaN or infinite. The crate declares it but never returns it, since an
    /// out of bounds check comes first and catches these values too.
    case latitudeNotFinite(param: String, latitude: Double)
    /// A latitude outside -90...90, NaN included.
    case latitudeOutOfBounds(param: String, latitude: Double)
    /// A bounding box whose minimum latitude is greater than its maximum latitude.
    case minLatitudeGreaterThanMaxLatitude(minLatitude: Double, maxLatitude: Double)

    public var description: String {
        switch self {
        case let .longitudeNotFinite(param, longitude):
            return "\(param) \(longitude) must be finite"
        case let .latitudeNotFinite(param, latitude):
            return "\(param) \(latitude) must be finite"
        case let .latitudeOutOfBounds(param, latitude):
            return "\(param) \(latitude) is out of bounds, must be within -90.0 and +90.0"
        case let .minLatitudeGreaterThanMaxLatitude(minLatitude, maxLatitude):
            return "min_latitude \(minLatitude) must not be greater than max_latitude \(maxLatitude)"
        }
    }
}

/// A failure to read a boundaries file.
public enum ReadError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The file starts with a format version other than the one this code reads.
    case wrongVersionNumber(expected: UInt16, actual: UInt16)
    /// A string in the file is not valid UTF-8.
    case unableToDecodeUtf8
    /// The data ended before the file did. The crate reports this as an IO error.
    case unexpectedEndOfData

    public var description: String {
        switch self {
        case let .wrongVersionNumber(expected, actual):
            return "Wrong version number '\(actual)' of the boundaries file (expected: '\(expected)'). "
                + "You may need to get the current version of the data."
        case .unableToDecodeUtf8:
            return "Unable to decode UTF-8 string"
        case .unexpectedEndOfData:
            return "IO error: failed to fill whole buffer"
        }
    }
}
