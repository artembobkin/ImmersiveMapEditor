/// muv-osm's own unit tests of the parts the lane reading stands on,
/// translated: the order of a tag's subtags (rustc-hash and hashbrown),
/// numbers and their significant figures, quantities, parentheses around
/// conditions, semicolon-separated values, the mode hierarchy, and a few
/// opening-hours expressions.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

@testable import MuvLanes
import Testing

struct MuvUnitTests {
    /// `tmode::tests::iter_tags`: the modes in the `HashMap`'s order.
    @Test func iterTagsOrder() {
        let tags = Tag()
        for (k, v) in [("ski", "15"), ("ski:alpine", "12"), ("motorcar", "23"), ("bus", "49"), ("hazmat:C", "32")] {
            tags.insertRaw(k, v)
        }
        let modes = TMode.iterTags(tags).compactMap { m, t in t.value.map { (m, $0) } }
        #expect(modes.map(\.0) == [.ski, .skiAlpine, .motorcar, .bus, .hazmatC])
        #expect(modes.map(\.1) == ["15", "12", "23", "49", "32"])
    }

    /// `number::tests::parse`.
    @Test func numberParse() {
        func p(_ s: String) -> (Float, UInt8, String)? {
            Number.parseStart(s).map { ($0.0.number, $0.0.significantFigures, $0.1) }
        }
        #expect(p("-123")! == (-123, 3, ""))
        #expect(p("100m")! == (100, 1, "m"))
        #expect(p("-135.42")! == (-135.42, 5, ""))
        #expect(p("-0.013")! == (-0.013, 2, ""))
        #expect(p("64.0 bits")! == (64, 3, " bits"))
        #expect(p("--14") == nil)
        #expect(p("") == nil)
        #expect(p("-0.00s")! == (-0.0, 0, "s"))
        let long = p("01234567890123456789012345678901234567890123456789." + String(repeating: "0123456789", count: 30) + "XYZ")!
        #expect(long.2 == "XYZ")
        #expect(long.1 == 255)
    }

    /// `number::tests::to_string`.
    @Test func numberDisplay() {
        #expect(Number.fromOsmStr("-0.45")!.display == "-0.45")
        #expect(Number.fromOsmStr("1000")!.display == "1000")
        var n = Number.fromOsmStr("24.3")!
        n.significantFigures = 2
        #expect(n.display == "24")
        n = Number.fromOsmStr("156")!
        n.significantFigures = 1
        #expect(n.display == "200")
    }

    /// `number::tests::add`, `div`.
    @Test func numberArithmetic() {
        let a = Number.fromOsmStr("24")! + Number.fromOsmStr("5")!
        #expect(a.number == 29 && a.significantFigures == 1)
        let d = Number.fromOsmStr("87.4")! / Number.fromOsmStr("2")!
        #expect(d.number == Float("43.7")! && d.significantFigures == 1)
    }

    /// `unit::tests::from_osm_str`, `physical::tests::parse_zone`.
    @Test func quantities() {
        #expect(Quantity<Distance>.fromOsmStr("50") == Quantity(Number.fromOsmStr("50")!, .metre))
        #expect(Quantity<Distance>.fromOsmStr("50nmi") == Quantity(Number.fromOsmStr("50")!, .nauticalMile))
        #expect(Quantity<Distance>.fromOsmStr("40 km") == Quantity(Number.fromOsmStr("40")!, .kilometre))
        #expect(Quantity<Distance>.fromOsmStr("-12.3'") == Quantity(Number.fromOsmStr("-12.3")!, .feet))
        let kmh = WalkSpeed.speed(.kilometresPerHour)
        #expect(Quantity<WalkSpeed>.fromOsmStr("FR:zone30") == Quantity(Number.fromOsmStr("30")!, kmh))
        #expect(Quantity<WalkSpeed>.fromOsmStr("DE:zone:30") == Quantity(Number.fromOsmStr("30")!, kmh))
        #expect(Quantity<WalkSpeed>.fromOsmStr("zone20") == Quantity(Number.fromOsmStr("20")!, kmh))
        #expect(Quantity<WalkSpeed>.fromOsmStr("AT:30") == Quantity(Number.fromOsmStr("30")!, kmh))
        #expect(Quantity<WalkSpeed>.fromOsmStr("NL:walk") == Quantity(Number(Float(1)), .walk))
        #expect(Quantity<WalkSpeed>.fromOsmStr("zone30:ends") == nil)
    }

    /// `conditional::tests::parens_removal`.
    @Test func parensRemoval() {
        #expect(removeParens("(ab)") == "ab")
        #expect(removeParens(" (ab) ") == "ab")
        #expect(removeParens("((a)b(c))") == "(a)b(c)")
        #expect(removeParens("((ab))") == "ab")
        #expect(removeParens("ab)c") == "ab)c")
        #expect(removeParens("c)") == "c)")
        #expect(removeParens(")ab") == ")ab")
        #expect(removeParens("a)b") == "a)b")
        #expect(removeParens("a(b") == "a(b")
        #expect(removeParens("a(") == "a(")
    }

    /// `conditional::tests`: the number of restrictions and conditions.
    @Test func conditionals() {
        func parse(_ value: String, _ conditional: String) -> Conditional<String>? {
            let tags = Tag()
            tags.insertRaw("maxspeed", value)
            tags.insertRaw("maxspeed:conditional", conditional)
            return Conditional<String>.parseWith(tags.get("maxspeed")!) { Quantity<WalkSpeed>.fromOsmStr($0) != nil ? $0 : nil }
        }
        let a = parse("100", "60 @ (22:00-05:00 AND weight>7.5)")!
        #expect(a.count == 2 && a.restrictions[1].conditions.count == 2)
        let b = parse("30", "20 @ (Sa,Su \"weekend );\")")!
        #expect(b.count == 2 && b.restrictions[1].conditions.count == 1)
        #expect(parse("90", "80 @ wet)")!.count == 1)
        let c = parse("70 mph", "65 mph @ ((sunset+01:30)-(sunrise-01:30))")!
        #expect(c.count == 2 && c.restrictions[1].conditions.count == 1)
    }

    /// `parse::tests::from_seperated_value`.
    @Test func seperated() {
        #expect(seperatedValues("") == [""])
        #expect(seperatedValues(";abc;def;") == ["", "abc", "def", ""])
        #expect(seperatedValues(";;abc;def;;") == [";abc", "def;"])
        #expect(seperatedValues("abc;;def;;ghi;jkl") == ["abc;def;ghi", "jkl"])
        #expect(seperatedValues("abc;;;def") == ["abc;", "def"])
        #expect(seperatedValues("abc;;;;;;def") == ["abc;;;def"])
    }

    /// `hierarchy` doc tests.
    @Test func hierarchy() {
        #expect(TMode.bicycle.hierarchyParent == .vehicle)
        #expect(TMode.boat.hierarchyParent == .waterBased)
        #expect(TMode.all.hierarchyParent == nil)
        #expect(TMode.hazmatExplosive.iterHierarchy() == [.hazmatExplosive, .hazmat, .motorVehicle, .vehicle, .landBased, .all])
        for m in TMode.allCases {
            var next: TMode? = m
            while let c = next {
                next = c.hierarchyParent
                if let n = next { #expect(n.rawValue < c.rawValue, "\(c) -> \(n)") }
            }
        }
    }

    /// Opening-hours expressions accepted and refused as the crate does.
    @Test func openingHours() {
        for ok in ["Mo-Fr 07:00-19:00", "sunset-sunrise", "Nov-Mar", "(sunset+01:30)-(sunrise-01:30)", "24/7",
                   "Mo-Fr 08:00-12:00 off", "PH", "Su[1,-1]", "week 01-10/2", "Dec 25-26", "2020-2030/2", "10:00+",
                   "10:00-12:00/30", "easter", "Mo-Fr 06:00-09:00,16:00-19:00"] {
            #expect(OpeningHoursSyntax.parses(ok), "\(ok)")
        }
        for bad in ["", "nonsense", "10:00-48:30", "Mo-", "week 1-2/300", "easter-25", "Jan 01-Feb", "25:00-26:00", "Mo +1 day"] {
            #expect(!OpeningHoursSyntax.parses(bad), "\(bad)")
        }
    }
}
