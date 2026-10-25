/// Whether opening-hours-syntax 1.1.3 parses a string, which is what decides
/// whether Muv reads a condition as a date and time range: its pest grammar
/// (`grammar.pest`, a PEG: ordered choice, greedy repetition) recognised
/// over the bytes, and the errors its builder (`parser.rs`) raises on a
/// successful match: an extended time past 48:00, a day offset beyond
/// `i64`, a week step beyond `u8`, a year step beyond `u16`, and a day
/// number after Easter. Times are not evaluated: osm2lanes only reads them.
///
/// opening-hours-syntax is MIT or Apache-2.0 (see this folder's LICENSE).
/// This translation is part of this MPL-2.0 file.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

enum OpeningHoursSyntax {
    /// `opening_hours_syntax::parse(s).is_ok()`.
    static func parses(_ s: String) -> Bool {
        var p = OHParser(Array(s.utf8))
        return p.input()
    }
}

/// The recogniser. Each rule either matches and moves on, or fails and
/// leaves the position (and the builder's error, which belongs to the
/// matched text only) as it found them.
private struct OHParser {
    let b: [UInt8]
    var pos = 0
    /// A builder error in what has matched so far.
    var failed = false

    init(_ b: [UInt8]) { self.b = b }

    // MARK: Machinery

    private typealias State = (Int, Bool)
    private var state: State { (pos, failed) }
    private mutating func restore(_ s: State) { (pos, failed) = s }

    /// A sequence: all of `body`, or nothing.
    private mutating func seq(_ body: (inout OHParser) -> Bool) -> Bool {
        let s = state
        if body(&self) { return true }
        restore(s)
        return false
    }

    /// `x?`.
    private mutating func opt(_ body: (inout OHParser) -> Bool) -> Bool {
        _ = seq(body)
        return true
    }

    /// `x*`.
    private mutating func many(_ body: (inout OHParser) -> Bool) -> Bool {
        while true {
            let before = pos
            if !seq(body) || pos == before { return true }
        }
    }

    /// `&x` (`ahead`) or `!x`: matches nothing either way.
    private mutating func lookahead(_ body: (inout OHParser) -> Bool) -> Bool {
        let s = state
        let r = body(&self)
        restore(s)
        return r
    }

    private mutating func lit(_ s: StaticString) -> Bool {
        let n = s.utf8CodeUnitCount
        guard pos + n <= b.count else { return false }
        let p = s.utf8Start
        for i in 0..<n where b[pos + i] != p[i] { return false }
        pos += n
        return true
    }

    private mutating func range(_ lo: Character, _ hi: Character) -> Bool {
        guard pos < b.count, b[pos] >= lo.asciiValue!, b[pos] <= hi.asciiValue! else { return false }
        pos += 1
        return true
    }

    private mutating func digit() -> Bool { range("0", "9") }

    private mutating func space() -> Bool { lit(" ") }

    private func text(_ from: Int) -> String { String(decoding: b[from..<pos], as: UTF8.self) }

    // MARK: Time domain

    /// `input_opening_hours = _{ SOI ~ &ANY ~ opening_hours ~ EOI }`.
    mutating func input() -> Bool {
        guard pos < b.count else { return false }
        guard openingHours() else { return false }
        return pos == b.count && !failed
    }

    private mutating func openingHours() -> Bool {
        seq { p in
            guard p.ruleSequence() else { return false }
            return p.many { $0.anyRuleSeparator() && $0.ruleSequence() }
        }
    }

    private mutating func ruleSequence() -> Bool {
        seq { p in
            let blocked = p.lookahead { q in
                q.seq { r in
                    _ = r.opt { $0.space() }
                    return r.anyRuleSeparator() || r.pos == r.b.count
                }
            }
            if blocked { return false }
            guard p.selectorSequence() else { return false }
            _ = p.opt { $0.space() }
            _ = p.opt { $0.rulesModifier() }
            return true
        }
    }

    private mutating func anyRuleSeparator() -> Bool {
        seq { p in
            // normal_rule_separator
            p.seq { q in _ = q.opt { $0.space() }; return q.lit(";") && q.opt { $0.space() } }
                // additional_rule_separator
                || p.seq { q in q.lit(",") && q.space() }
                // fallback_rule_separator
                || p.seq { q in _ = q.opt { $0.space() }; return q.lit("||") && q.space() }
        }
    }

    private mutating func rulesModifier() -> Bool {
        seq { p in
            if p.comment() { return true }
            return p.seq { q in
                guard q.rulesModifierEnum() else { return false }
                return q.opt { r in _ = r.opt { $0.space() }; return r.comment() }
            }
        }
    }

    private mutating func rulesModifierEnum() -> Bool {
        lit("closed") || lit("off") || lit("open") || lit("unknown")
    }

    // MARK: Selectors

    private mutating func selectorSequence() -> Bool {
        seq { p in
            if p.lit("24/7") { return true }
            return p.seq { q in q.wideRangeSelectors() && q.opt { $0.smallRangeSelectors() } }
        }
    }

    private mutating func wideRangeSelectors() -> Bool {
        seq { p in p.comment() && p.lit(":") }
            || seq { p in
                guard p.monthdaySelector() else { return false }
                _ = p.opt { $0.weekSelector() }
                return p.opt { $0.separatorForReadability() }
            }
            || seq { p in
                _ = p.opt { $0.yearSelector() }
                _ = p.opt { $0.monthdaySelector() }
                _ = p.opt { $0.weekSelector() }
                return p.opt { $0.separatorForReadability() }
            }
    }

    private mutating func smallRangeSelectors() -> Bool {
        seq { p in p.weekdaySelector() && p.space() && p.timeSelector() }
            || weekdaySelector()
            || timeSelector()
    }

    private mutating func separatorForReadability() -> Bool { lit(" ") || lit(": ") || lit(":") }

    // MARK: Time selector

    private mutating func timeSelector() -> Bool {
        seq { p in p.timespan() && p.many { $0.lit(",") && $0.timespan() } }
    }

    private mutating func timespan() -> Bool {
        seq { p in
            guard p.time() else { return false }
            _ = p.opt { $0.space() }
            guard p.lit("-"), p.extendedTime() else { return false }
            _ = p.opt { $0.space() }
            guard p.lit("/") else { return false }
            _ = p.opt { $0.space() }
            return p.hourMinutes()
        }
            || seq { p in
                guard p.time() else { return false }
                _ = p.opt { $0.space() }
                guard p.lit("-"), p.extendedTime() else { return false }
                _ = p.opt { $0.space() }
                guard p.lit("/") else { return false }
                _ = p.opt { $0.space() }
                return p.minute()
            }
            || seq { p in
                guard p.time() else { return false }
                _ = p.opt { $0.space() }
                guard p.lit("-") else { return false }
                _ = p.opt { $0.space() }
                return p.extendedTime() && p.lit("+")
            }
            || seq { p in
                guard p.time() else { return false }
                _ = p.opt { $0.space() }
                guard p.lit("-") else { return false }
                _ = p.opt { $0.space() }
                return p.extendedTime()
            }
            || seq { p in p.time() && p.lit("+") }
    }

    private mutating func time() -> Bool { hourMinutes() || variableTime() }

    private mutating func extendedTime() -> Bool { extendedHourMinutes() || variableTime() }

    private mutating func variableTime() -> Bool {
        seq { p in p.lit("(") && p.event() && p.plusOrMinus() && p.hourMinutes() && p.lit(")") }
            || event()
    }

    private mutating func event() -> Bool { lit("dawn") || lit("sunrise") || lit("sunset") || lit("dusk") }

    // MARK: Weekday selector

    private mutating func weekdaySelector() -> Bool {
        seq { p in
            guard p.holidaySequence() else { return false }
            return p.opt { q in (q.lit(",") || q.space()) && q.weekdaySequence() }
        }
            || seq { p in
                guard p.weekdaySequence() else { return false }
                return p.opt { q in (q.lit(",") || q.space()) && q.holidaySequence() }
            }
    }

    private mutating func weekdaySequence() -> Bool {
        seq { p in p.weekdayRange() && p.many { $0.lit(",") && $0.weekdayRange() } }
    }

    private mutating func weekdayRange() -> Bool {
        seq { p in
            guard p.wday(), p.lit("["), p.nthEntry() else { return false }
            guard p.many({ $0.lit(",") && $0.nthEntry() }), p.lit("]") else { return false }
            return p.opt { $0.dayOffset() }
        }
            || seq { p in p.wday() && p.lit("-") && p.wday() }
            || wday()
    }

    private mutating func holidaySequence() -> Bool {
        seq { p in p.holiday() && p.many { $0.lit(",") && $0.holiday() } }
    }

    private mutating func holiday() -> Bool {
        seq { p in p.lit("PH") && p.opt { $0.dayOffset() } } || lit("SH")
    }

    private mutating func nthEntry() -> Bool {
        seq { p in p.nth() && p.lit("-") && p.nth() }
            || seq { p in p.lit("-") && p.nth() }
            || nth()
    }

    private mutating func nth() -> Bool { range("1", "5") }

    /// `day_offset`, its value in `i64`.
    private mutating func dayOffset() -> Bool {
        seq { p in
            guard p.space(), p.plusOrMinus() else { return false }
            guard let value = p.positiveNumber() else { return false }
            guard p.space(), p.lit("day") else { return false }
            _ = p.opt { $0.lit("s") }
            if value.map({ $0 > UInt64(Int64.max) }) ?? true { p.failed = true }
            return true
        }
    }

    // MARK: Week selector

    private mutating func weekSelector() -> Bool {
        seq { p in
            _ = p.opt { $0.separatorForReadability() }
            guard p.lit("week") else { return false }
            _ = p.opt { $0.space() }
            return p.week() && p.many { $0.lit(",") && $0.week() }
        }
    }

    /// `week`, its step in `u8`.
    private mutating func week() -> Bool {
        seq { p in
            guard p.weeknum() else { return false }
            return p.opt { q in
                guard q.lit("-"), q.weeknum() else { return false }
                return q.opt { r in
                    guard r.lit("/"), let step = r.positiveNumber() else { return false }
                    if step.map({ $0 > UInt64(UInt8.max) }) ?? true { r.failed = true }
                    return true
                }
            }
        }
    }

    // MARK: Month selector

    private mutating func monthdaySelector() -> Bool {
        seq { p in p.monthdayRange() && p.many { $0.lit(",") && $0.monthdayRange() } }
    }

    private mutating func monthdayRange() -> Bool {
        seq { p in
            guard let fromEaster = p.dateFrom() else { return false }
            _ = p.opt { $0.dateOffset() }
            _ = p.opt { $0.space() }
            guard p.lit("-") else { return false }
            _ = p.opt { $0.space() }
            guard let toIsDaynum = p.dateTo() else { return false }
            if fromEaster && toIsDaynum { p.failed = true }
            return p.opt { $0.dateOffset() }
        }
            || seq { p in p.dateFrom() != nil && p.dateOffset() && p.opt { $0.lit("+") } }
            || seq { p in p.dateFrom() != nil && p.opt { $0.lit("+") } }
            || seq { p in
                _ = p.opt { $0.year() }
                guard p.month() else { return false }
                return p.opt { $0.lit("-") && $0.month() }
            }
    }

    private mutating func dateOffset() -> Bool {
        seq { p in p.plusOrMinus() && p.wday() && p.dayOffset() }
            || seq { p in p.plusOrMinus() && p.wday() }
            || dayOffset()
    }

    /// `date_from`: whether it is Easter, nil if it does not match.
    private mutating func dateFrom() -> Bool? {
        let fixed = seq { p in
            _ = p.opt { q in q.year() && q.opt { $0.lit(" ") } }
            guard p.month() else { return false }
            _ = p.opt { $0.lit(" ") }
            return p.daynum()
        }
        if fixed { return false }
        let easter = seq { p in
            _ = p.opt { $0.year() }
            _ = p.opt { $0.lit(" ") }
            return p.lit("easter")
        }
        return easter ? true : nil
    }

    /// `date_to`: whether it is a bare day number, nil if it does not match.
    private mutating func dateTo() -> Bool? {
        if dateFrom() != nil { return false }
        return daynum() ? true : nil
    }

    // MARK: Year selector

    private mutating func yearSelector() -> Bool {
        seq { p in p.yearRange() && p.many { $0.lit(",") && $0.yearRange() } }
    }

    /// `year_range`, its step in `u16`.
    private mutating func yearRange() -> Bool {
        seq { p in p.year() && p.lit("+") }
            || seq { p in
                guard p.year() else { return false }
                return p.opt { q in
                    guard q.lit("-"), q.year() else { return false }
                    return q.opt { r in
                        guard r.lit("/"), let step = r.positiveNumber() else { return false }
                        if step.map({ $0 > UInt64(UInt16.max) }) ?? true { r.failed = true }
                        return true
                    }
                }
            }
    }

    // MARK: Basic elements

    private mutating func plusOrMinus() -> Bool { lit("+") || lit("-") }

    private mutating func hour() -> Bool {
        seq { p in p.range("0", "1") && p.digit() }
            || seq { p in p.lit("2") && p.range("0", "3") }
            || seq { p in p.digit() && !p.lookahead { $0.digit() } }
    }

    private mutating func extendedHour() -> Bool {
        seq { p in p.range("0", "3") && p.digit() }
            || seq { p in p.lit("4") && p.range("0", "8") }
            || seq { p in p.digit() && !p.lookahead { $0.digit() } }
    }

    private mutating func minute() -> Bool {
        seq { p in p.range("0", "5") && p.digit() }
    }

    private mutating func hourMinutes() -> Bool {
        seq { p in p.hour() && p.lit(":") && p.minute() } || lit("24:00")
    }

    /// `extended_hour_minutes`, a valid `ExtendedTime` (at most 48:00).
    private mutating func extendedHourMinutes() -> Bool {
        seq { p in
            let start = p.pos
            guard p.extendedHour() else { return false }
            let hour = UInt8(p.text(start))!
            guard p.lit(":") else { return false }
            let m = p.pos
            guard p.minute() else { return false }
            let minute = UInt8(p.text(m))!
            if hour > 48 || minute > 59 || (hour == 48 && minute > 0) { p.failed = true }
            return true
        }
    }

    private mutating func wday() -> Bool {
        lit("Su") || lit("Mo") || lit("Tu") || lit("We") || lit("Th") || lit("Fr") || lit("Sa")
    }

    private mutating func daynum() -> Bool {
        seq { p in
            guard p.daynumDigits() else { return false }
            return !p.lookahead { q in q.lit(":") && q.minute() && !q.lookahead { r in r.lit(":") && r.minute() } }
        }
    }

    private mutating func daynumDigits() -> Bool {
        seq { p in p.range("1", "2") && p.digit() }
            || seq { p in p.lit("3") && p.range("0", "1") }
            || seq { p in _ = p.opt { $0.lit("0") }; return p.range("1", "9") }
    }

    private mutating func weeknum() -> Bool {
        seq { p in p.range("1", "4") && p.digit() }
            || seq { p in p.lit("5") && p.range("0", "3") }
            || seq { p in _ = p.opt { $0.lit("0") }; return p.range("1", "9") }
    }

    private mutating func month() -> Bool {
        lit("Jan") || lit("Feb") || lit("Mar") || lit("Apr") || lit("May") || lit("Jun") || lit("Jul")
            || lit("Aug") || lit("Sep") || lit("Oct") || lit("Nov") || lit("Dec")
    }

    private mutating func year() -> Bool {
        seq { p in p.lit("19") && p.digit() && p.digit() }
            || seq { p in p.range("2", "9") && p.digit() && p.digit() && p.digit() }
    }

    /// `positive_number`: matched, with its value (nil past `u64`), or nil if no match.
    private mutating func positiveNumber() -> UInt64?? {
        let start = pos
        let ok = seq { p in
            _ = p.many { $0.lit("0") }
            guard p.range("1", "9") else { return false }
            return p.many { $0.digit() }
        }
        guard ok else { return nil }
        return .some(rustParseUnsigned(text(start), max: .max))
    }

    private mutating func comment() -> Bool {
        seq { p in
            guard p.lit("\"") else { return false }
            let start = p.pos
            while p.pos < p.b.count, p.b[p.pos] != UInt8(ascii: "\"") { p.pos += 1 }
            return p.pos > start && p.lit("\"")
        }
    }
}
