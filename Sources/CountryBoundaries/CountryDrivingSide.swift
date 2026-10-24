/// Which side of the road traffic keeps to in a country or territory, by its region code.
///
/// Written for this port from public knowledge of left- and right-hand traffic. It answers the
/// region codes of `CountryBoundaries` the way osm2streets needs: a side for a country or a
/// territory with roads of its own, and nil for everything else, so that a lookup over the ids
/// of a position (ordered from the smallest region) settles on the most specific region that
/// has an answer.

/// The side of the road traffic keeps to.
public enum CountryDrivingSide: Sendable, Equatable {
    case left
    case right
}

/// Returns the side traffic keeps to in the region with the given code, or nil when the code
/// has no answer of its own.
///
/// The code is an uppercase ISO 3166-1 alpha-2 code, or one of the exceptionally reserved codes
/// of a territory with its own traffic (AC Ascension, CQ Sark, DG Diego Garcia, TA Tristan da
/// Cunha). Subdivision codes such as `US-TX` or `GB-ENG` get nil, and so do EA (Ceuta and
/// Melilla) and IC (the Canary Islands), which fall through to ES, and the territories without
/// a road network (AQ, BV, CP, HM).
public func drivingSide(_ code: String) -> CountryDrivingSide? {
    if leftHandTraffic.contains(code) {
        return .left
    }
    if rightHandTraffic.contains(code) {
        return .right
    }
    return nil
}

/// The regions that drive on the left, grouped by part of the world.
private let leftHandTraffic: Set<String> = [
    // Europe: the British Isles, the Crown Dependencies, Cyprus and Malta.
    "GB", "IE", "IM", "JE", "GG", "CQ", "CY", "MT",
    // British territories in the Atlantic.
    "BM", "AC", "SH", "TA", "FK", "GS",
    // The Caribbean.
    "AG", "AI", "BB", "BS", "DM", "GD", "JM", "KN", "KY", "LC", "MS", "TC", "TT", "VC", "VG", "VI",
    // South America.
    "GY", "SR",
    // Southern and eastern Africa, and the islands of the Indian Ocean.
    "BW", "KE", "LS", "MU", "MW", "MZ", "NA", "SC", "SZ", "TZ", "UG", "ZA", "ZM", "ZW",
    // South Asia.
    "BD", "BT", "IN", "LK", "MV", "NP", "PK",
    // East and South-East Asia.
    "BN", "HK", "ID", "JP", "MO", "MY", "SG", "TH", "TL",
    // Australia, New Zealand and the Pacific.
    "AU", "CC", "CX", "NF", "NZ", "CK", "NU", "TK", "FJ", "KI", "NR", "PG", "PN", "SB", "TO", "TV", "WS",
]

/// The regions that drive on the right, grouped by part of the world.
private let rightHandTraffic: Set<String> = [
    // Europe.
    "AD", "AL", "AT", "AX", "BA", "BE", "BG", "BY", "CH", "CZ", "DE", "DK", "EE", "ES", "FI", "FO",
    "FR", "GI", "GR", "HR", "HU", "IS", "IT", "LI", "LT", "LU", "LV", "MC", "MD", "ME", "MK", "NL",
    "NO", "PL", "PT", "RO", "RS", "RU", "SE", "SI", "SJ", "SK", "SM", "UA", "VA", "XK",
    // The Caucasus, Central Asia and the Middle East.
    "AM", "AZ", "GE", "KZ", "KG", "TJ", "TM", "UZ", "AF", "AE", "BH", "IL", "IQ", "IR", "JO", "KW",
    "LB", "OM", "PS", "QA", "SA", "SY", "TR", "YE",
    // East and South-East Asia.
    "CN", "KP", "KR", "MN", "TW", "KH", "LA", "MM", "PH", "VN",
    // Africa and its islands.
    "AO", "BF", "BI", "BJ", "CD", "CF", "CG", "CI", "CM", "CV", "DJ", "DZ", "EG", "EH", "ER", "ET",
    "GA", "GH", "GM", "GN", "GQ", "GW", "KM", "LR", "LY", "MA", "MG", "ML", "MR", "NE", "NG", "RE",
    "RW", "SD", "SL", "SN", "SO", "SS", "ST", "TD", "TG", "TN", "YT",
    // Territories in the Indian and Southern Oceans.
    "IO", "DG", "TF",
    // North and Central America.
    "CA", "US", "MX", "GL", "PM", "BZ", "CR", "GT", "HN", "NI", "PA", "SV",
    // The Caribbean.
    "CU", "DO", "HT", "PR", "AW", "BQ", "CW", "SX", "BL", "MF", "GP", "MQ",
    // South America.
    "AR", "BO", "BR", "CL", "CO", "EC", "PE", "PY", "UY", "VE", "GF",
    // The Pacific.
    "AS", "FM", "GU", "MH", "MP", "NC", "PF", "PW", "UM", "VU", "WF",
]
