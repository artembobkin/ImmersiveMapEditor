/// Tests of `drivingSide` against the answers of `muv_osm::lanes::highway::driving_side`
/// (Muv at revision 2404d40), which osm2streets uses, and of the country detection built on it.
///
/// The two lists below are the expected answers, read from Muv's generated table. Every code
/// absent from both is expected to give nil, as Muv gives `None`.

import Testing
@testable import CountryBoundaries

/// The codes Muv answers with `Side::Left`.
private let muvLeft: Set<String> = Set("""
    AC AG AI AU BB BD BM BN BS BT BW CC CK CQ CX CY DM FJ FK GB GD GG GS GY HK ID IE IM IN JE JM JP
    KE KI KN KY LC LK LS MO MS MT MU MV MW MY MZ NA NF NP NR NU NZ PG PK PN SB SC SG SH SR SZ TA TC
    TH TK TL TO TT TV TZ UG VC VG VI WS ZA ZM ZW
    """.split(whereSeparator: \.isWhitespace).map(String.init))

/// The codes Muv answers with `Side::Right`.
private let muvRight: Set<String> = Set("""
    AD AE AF AL AM AO AR AS AT AW AX AZ BA BE BF BG BH BI BJ BL BO BQ BR BY BZ CA CD CF CG CH CI CL
    CM CN CO CR CU CV CW CZ DE DG DJ DK DO DZ EC EE EG EH ER ES ET FI FM FO FR GA GE GF GH GI GL GM
    GN GP GQ GR GT GU GW HN HR HT HU IL IO IQ IR IS IT JO KG KH KM KP KR KW KZ LA LB LI LR LT LU LV
    LY MA MC MD ME MF MG MH MK ML MM MN MP MQ MR MX NC NE NG NI NL NO OM PA PE PF PH PL PM PR PS PT
    PW PY QA RE RO RS RU RW SA SD SE SI SJ SK SL SM SN SO SS ST SV SX SY TD TF TG TJ TM TN TR TW UA UM
    US UY UZ VA VE VN VU WF XK YE YT
    """.split(whereSeparator: \.isWhitespace).map(String.init))

/// Muv's answer for a code.
private func muv(_ code: String) -> CountryDrivingSide? {
    if muvLeft.contains(code) {
        return .left
    }
    if muvRight.contains(code) {
        return .right
    }
    return nil
}

/// Every id of the embedded boundary data.
private let boundaryIds = Set(CountryBoundaries.odbl60x30.geometrySizes.keys)
    .union(CountryBoundaries.odbl60x30.raster.flatMap { $0.getAllIds() })

/// Every two-letter uppercase code, AA to ZZ.
private let allTwoLetterCodes: [String] = {
    let letters = (UInt8(ascii: "A")...UInt8(ascii: "Z")).map { Character(Unicode.Scalar($0)) }
    return letters.flatMap { a in letters.map { b in String([a, b]) } }
}()

@Suite struct DrivingSideTests {
    @Test func muvListsDoNotOverlap() {
        #expect(muvLeft.count == 79)
        #expect(muvRight.count == 172)
        #expect(muvLeft.isDisjoint(with: muvRight))
    }

    @Test func agreesWithMuvOnEveryCodeItAnswers() {
        for code in muvLeft.union(muvRight).sorted() {
            #expect(drivingSide(code) == muv(code), "code \(code)")
        }
    }

    @Test func agreesWithMuvOnEveryBoundaryId() {
        #expect(boundaryIds.count == 516)
        for code in boundaryIds.sorted() {
            #expect(drivingSide(code) == muv(code), "code \(code)")
        }
    }

    @Test func agreesWithMuvOnEveryTwoLetterCode() {
        for code in allTwoLetterCodes {
            #expect(drivingSide(code) == muv(code), "code \(code)")
        }
    }

    @Test func boundaryIdsWithoutAnAnswer() {
        let unanswered = boundaryIds.filter { !$0.contains("-") && drivingSide($0) == nil }
        #expect(unanswered == ["BV", "CP", "EA", "HM", "IC"])
        #expect(boundaryIds.filter { $0.contains("-") }.allSatisfy { drivingSide($0) == nil })
    }

    /// The country detection of `detect_country_code` in osm2streets' `streets_reader`: the
    /// first id, from the smallest region, that has a driving side.
    @Test(arguments: [
        (55.7539, 37.6208, "RU", CountryDrivingSide.right),
        (47.6, -122.3, "US", .right),
        (51.5, -0.12, "GB", .left),
        (52.5, 13.4, "DE", .right),
        (-31.95, 115.86, "AU", .left),
        (25.03, 121.56, "TW", .right),
        (17.71, -64.88, "VI", .left),
        (33.42, -111.94, "US", .right),
    ])
    func detectsCountryAndSide(latitude: Double, longitude: Double, code: String, side: CountryDrivingSide) throws {
        let ids = CountryBoundaries.odbl60x30.ids(try LatLon(latitude: latitude, longitude: longitude))
        let found = ids.lazy.compactMap { id in drivingSide(id).map { (id, $0) } }.first
        #expect(found?.0 == code)
        #expect(found?.1 == side)
    }
}
