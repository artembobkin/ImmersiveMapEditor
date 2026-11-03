import Foundation

/// How much a building of OSM matters, by its tags, so the Buildings view
/// shows at a glance which of a tile's buildings are known (the user,
/// 2026-11-01: which are worth a landmark is not visible from the outlines).
enum BuildingNote: Int, Comparable {
    /// No name.
    case plain
    /// A name alone.
    case named
    /// An article in Wikipedia or Wikidata, a heritage or historic tag, a
    /// sight or a museum, or a kind of building people know by name (a
    /// church, a theatre, a station, a palace). Kept narrow (the user,
    /// 2026-11-01: with hotels and offices in, half the tile was notable).
    case notable

    static func < (a: BuildingNote, b: BuildingNote) -> Bool { a.rawValue < b.rawValue }

    private static let notableBuildings: Set<String> = [
        "cathedral", "church", "chapel", "mosque", "synagogue", "temple", "monastery", "basilica",
        "palace", "castle", "government", "museum", "theatre", "train_station", "stadium", "parliament", "kremlin",
    ]
    private static let notableAmenities: Set<String> = [
        "theatre", "place_of_worship", "townhall", "courthouse", "concert_hall", "arts_centre", "planetarium",
    ]
    private static let notableTourism: Set<String> = ["attraction", "museum", "gallery"]

    init(_ tags: [String: String]) {
        let named = tags["name"] != nil || tags["name:en"] != nil
        self = Self.reason(tags) != nil ? .notable : named ? .named : .plain
    }

    /// Why a building is notable: the tag that says so, as "key = value",
    /// for the status line and the picked list (the user, 2026-11-02: a
    /// building tinted as notable with no name, and no way to see why).
    static func reason(_ tags: [String: String]) -> String? {
        if let v = tags["wikidata"] { return "wikidata = \(v)" }
        if let v = tags["wikipedia"] { return "wikipedia = \(v)" }
        if let v = tags["heritage"] { return "heritage = \(v)" }
        if let v = tags["historic"] { return "historic = \(v)" }
        if let v = tags["tourism"], notableTourism.contains(v) { return "tourism = \(v)" }
        if let v = tags["building"], notableBuildings.contains(v) { return "building = \(v)" }
        if let v = tags["amenity"], notableAmenities.contains(v) { return "amenity = \(v)" }
        return nil
    }
}
