/// Loading of the earcutr test fixtures: a small parser for JSON arrays of numbers, the fixtures
/// and recorded outputs read from the crate's folder in the cargo registry, and the list of
/// fixture cases with the triangle counts and deviations the crate's tests expect.

import Foundation

/// The earcutr 0.4.3 crate in the local cargo registry, where the large fixtures are read from.
let earcutrCrateDirectory =
    NSHomeDirectory() + "/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/earcutr-0.4.3"

/// Whether the crate's fixtures are on this machine.
let earcutrFixturesAvailable = FileManager.default.fileExists(
    atPath: earcutrCrateDirectory + "/tests/fixtures/building.json"
)

/// A JSON value made only of numbers and arrays, which is all the fixtures hold.
indirect enum NumberTree {
    case number(Double)
    case array([NumberTree])
}

/// Parses a JSON array of numbers and arrays, nested to any depth.
struct NumberTreeParser {
    private let bytes: [UInt8]
    private var position = 0

    init(_ text: String) {
        bytes = Array(text.utf8)
    }

    static func parse(_ text: String) -> NumberTree? {
        var parser = NumberTreeParser(text)
        return parser.value()
    }

    private mutating func skipSpace() {
        while position < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[position]) {
            position += 1
        }
    }

    private mutating func value() -> NumberTree? {
        skipSpace()
        guard position < bytes.count else { return nil }
        if bytes[position] == UInt8(ascii: "[") {
            position += 1
            var items: [NumberTree] = []
            skipSpace()
            if position < bytes.count, bytes[position] == UInt8(ascii: "]") {
                position += 1
                return .array(items)
            }
            while true {
                guard let item = value() else { return nil }
                items.append(item)
                skipSpace()
                guard position < bytes.count else { return nil }
                if bytes[position] == UInt8(ascii: ",") {
                    position += 1
                } else if bytes[position] == UInt8(ascii: "]") {
                    position += 1
                    return .array(items)
                } else {
                    return nil
                }
            }
        }
        let start = position
        while position < bytes.count,
            "+-.0123456789eE".utf8.contains(bytes[position])
        {
            position += 1
        }
        guard position > start,
            let number = Double(String(decoding: bytes[start..<position], as: UTF8.self))
        else { return nil }
        return .number(number)
    }
}

extension NumberTree {
    /// The tree as rings of points of coordinates, or nil when it is not shaped so.
    var polygon: [[[Double]]]? {
        guard case .array(let rings) = self else { return nil }
        var result: [[[Double]]] = []
        for ring in rings {
            guard case .array(let points) = ring else { return nil }
            var resultRing: [[Double]] = []
            for point in points {
                guard case .array(let coordinates) = point else { return nil }
                var resultPoint: [Double] = []
                for coordinate in coordinates {
                    guard case .number(let value) = coordinate else { return nil }
                    resultPoint.append(value)
                }
                resultRing.append(resultPoint)
            }
            result.append(resultRing)
        }
        return result
    }

    /// The tree as a flat array of integers, or nil when it is not shaped so.
    var integers: [Int]? {
        guard case .array(let items) = self else { return nil }
        var result: [Int] = []
        for item in items {
            guard case .number(let value) = item, let integer = Int(exactly: value) else {
                return nil
            }
            result.append(integer)
        }
        return result
    }
}

/// Reads a fixture polygon: the embedded one, else the coordinates the crate's own test run
/// printed in `viz/testoutput/` (see `embeddedFixtures`), else `tests/fixtures/` itself.
func loadFixture(_ name: String) -> [[[Double]]]? {
    if let text = embeddedFixtures[name] {
        return NumberTreeParser.parse(text)?.polygon
    }
    if let text = recordedValue(name, "json") {
        return NumberTreeParser.parse(text)?.polygon
    }
    let path = earcutrCrateDirectory + "/tests/fixtures/\(name).json"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    return NumberTreeParser.parse(text)?.polygon
}

/// Reads the triangles the crate's own test run recorded for a fixture in `viz/testoutput/`.
func loadRecordedTriangles(_ name: String) -> [Int]? {
    recordedValue(name, "triangles").flatMap { NumberTreeParser.parse($0)?.integers }
}

/// The text of one value the crate's test run recorded for a fixture, such as its `json` input or
/// its `triangles`.
private func recordedValue(_ name: String, _ key: String) -> String? {
    let fileName = name.replacingOccurrences(of: "-", with: "_")
    let path = earcutrCrateDirectory + "/viz/testoutput/\(fileName).js"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    let marker = "testOutput[\"\(fileName)\"][\"\(key)\"]="
    for line in text.split(separator: "\n") where line.hasPrefix(marker) {
        return String(line.dropFirst(marker.count).prefix { $0 != ";" })
    }
    return nil
}

/// One fixture test of the crate's `tests/integration_test.rs`.
struct FixtureCase: CustomStringConvertible, Sendable {
    let name: String
    /// The largest number of triangles that passes, or 0 for no limit.
    let triangles: Int
    /// The largest deviation that passes, where 0 stands for 1e-14.
    let deviation: Double

    var description: String { name }

    init(_ name: String, _ triangles: Int, _ deviation: Double) {
        self.name = name
        self.triangles = triangles
        self.deviation = deviation
    }
}

/// Every fixture case of the crate's integration tests, in its order.
let fixtureCases: [FixtureCase] = [
    FixtureCase("building", 13, 0e0),
    FixtureCase("dude", 106, 0e0),
    FixtureCase("water", 2482, 8e-4),
    FixtureCase("water2", 1212, 0e0),
    FixtureCase("water3", 197, 0e0),
    FixtureCase("water3b", 25, 0e0),
    FixtureCase("water4", 705, 0e0),
    FixtureCase("water-huge", 5174, 1.1e-3),
    FixtureCase("water-huge2", 4461, 2.8e-3),
    FixtureCase("degenerate", 0, 0e0),
    FixtureCase("bad-hole", 42, 1.9e-2),
    FixtureCase("empty-square", 0, 0e0),
    FixtureCase("issue16", 12, 0e0),
    FixtureCase("issue17", 11, 0e0),
    FixtureCase("steiner", 9, 0e0),
    FixtureCase("issue29", 40, 0e0),
    FixtureCase("issue34", 139, 0e0),
    FixtureCase("issue35", 844, 0e0),
    FixtureCase("self-touching", 124, 3.4e-14),
    FixtureCase("outside-ring", 64, 0e0),
    FixtureCase("simplified-us-border", 120, 0e0),
    FixtureCase("touching-holes", 57, 0e0),
    FixtureCase("hole-touching-outer", 77, 0e0),
    FixtureCase("hilbert", 1024, 0e0),
    FixtureCase("issue45", 10, 0e0),
    FixtureCase("eberly-3", 73, 0e0),
    FixtureCase("eberly-6", 1429, 0e0),
    FixtureCase("issue52", 109, 0e0),
    FixtureCase("shared-points", 4, 0e0),
    FixtureCase("bad-diagonals", 7, 0e0),
    FixtureCase("issue83", 0, 1e-14),
    FixtureCase("infinite-loop-jhl", 0, 1e-14),
    FixtureCase("filtered-bridge-jhl", 0, 1e-14),
    FixtureCase("issue142", 0, 1e-14),
    FixtureCase("issue149", 0, 1e-14),
]

/// The fixture cases whose polygon is embedded in this test target.
let embeddedFixtureCases = fixtureCases.filter { embeddedFixtures[$0.name] != nil }

/// The fixture cases whose polygon is read from the crate's folder.
let onDiskFixtureCases = fixtureCases.filter { embeddedFixtures[$0.name] == nil }
