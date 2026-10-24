import Foundation

/// Reading OSM tags, and choices that stay the same on every run.

public typealias Tags = [String: String]

/// A length tag in metres: "12", "12.5 m", "12,5". nil if unreadable.
public func length(_ value: String?) -> Double? {
    guard var text = value?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
    text = text.replacingOccurrences(of: ",", with: ".")
    for unit in ["m", "meters", "metres"] where text.hasSuffix(unit) {
        text = String(text.dropLast(unit.count)).trimmingCharacters(in: .whitespaces)
    }
    guard let n = Double(text), n.isFinite else { return nil }
    return n
}

/// Where a building or part starts above the ground, metres.
public func minHeight(_ tags: Tags) -> Double {
    if let h = length(tags["min_height"]) { return h }
    if let level = length(tags["building:min_level"]) { return level * 3.4 }
    return 0
}

public func underground(_ tags: Tags) -> Bool {
    let layer = length(tags["layer"])
    return tags["location"] == "underground" || tags["indoor"] != nil || (layer.map { $0 < 0 } ?? false)
}

/// A choice that stays the same for the same element on every run: by the
/// CRC-32 of its text, as the Python build chose (zlib.crc32 of str()).
public func stable<T>(_ value: String, _ choices: [T]) -> T {
    choices[Int(crc32(Array(value.utf8)) % UInt32(choices.count))]
}

let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
    var c = UInt32(n)
    for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    return c
}

public func crc32(_ bytes: [UInt8], _ start: UInt32 = 0) -> UInt32 {
    var c = ~start
    for b in bytes { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
    return ~c
}
