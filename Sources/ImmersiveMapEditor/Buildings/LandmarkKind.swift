import Foundation

/// Which of a tile's buildings Make Landmarks… makes landmarks of, at once
/// (the user, 2026-11-21: the notable alone were too few; the teal of the
/// map, notable and named, and the tall and large ones too). A rule on one
/// building, read off its tags and outline.
enum LandmarkKind: String, CaseIterable, Identifiable {
    /// Deep teal: an article, a heritage or historic tag, a kind people know by name.
    case notable
    /// Every teal building: the notable and the merely named.
    case known
    /// Amber: statues, memorials, obelisks.
    case monuments
    /// As tall as a tower block or more.
    case tall
    /// A large footprint.
    case large

    /// The height from which a building is tall, metres (OSM's height, else its levels).
    static let tallFrom = 30.0
    /// The footprint from which a building is large, square metres.
    static let largeFrom = 1500.0

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notable: "Notable (deep teal)"
        case .known: "Notable and named (all teal)"
        case .monuments: "Monuments (amber)"
        case .tall: "Tall: \(Int(Self.tallFrom)) m or more"
        case .large: "Large: \(Int(Self.largeFrom)) m² or more"
        }
    }

    func takes(_ b: OsmBuilding) -> Bool {
        switch self {
        case .notable: b.note == .notable
        case .known: b.note >= .named
        case .monuments: b.monument
        case .tall: (b.height ?? 0) >= Self.tallFrom
        case .large: b.area >= Self.largeFrom
        }
    }
}
