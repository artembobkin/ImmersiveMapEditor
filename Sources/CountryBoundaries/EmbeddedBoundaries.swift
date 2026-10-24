/// The boundary data shipped with country-boundaries, the 60x30 raster, decoded once on first use.
///
/// The data is (c) OpenStreetMap contributors, licensed under the ODbL 1.0. Its bytes are in
/// `BoundariesData.swift`, generated from the crate's `data/boundaries60x30.ser`.

import Foundation

extension CountryBoundaries {
    /// The ODbL licensed boundaries in a 60x30 raster, (c) OpenStreetMap contributors, the data
    /// `BOUNDARIES_ODBL_60X30` of the crate. It is decoded on first use, once, safely from any
    /// thread (a static constant is initialised lazily and atomically).
    public static let odbl60x30: CountryBoundaries = {
        guard let data = Data(base64Encoded: odbl60x30Base64, options: .ignoreUnknownCharacters) else {
            fatalError("The embedded boundary data is not valid base64.")
        }
        do {
            return try CountryBoundaries(data: data)
        } catch {
            fatalError("The embedded boundary data cannot be read: \(error)")
        }
    }()
}
