/// osm-reader's XML reading: elements in document order, tags, entities and
/// attribute whitespace as an XML parser gives them, missing PBF support.

import OSMReader
import Testing

@Suite struct OSMReaderTests {
    static let sample = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!-- a comment -->
    <osm version="0.6">
      <meta osm_base="2024-01-02T03:04:05Z"/>
      <bounds minlat="1.5" minlon="2.5" maxlat="3.5" maxlon="4.5"/>
      <node id="1" lat="10.25" lon="20.5" version="3"><tag k="name" v="A &amp; B &lt;&#65;&#x42;&gt;"/></node>
      <node id="2" lat="-1e-3" lon="0"/>
      <way id="7" version="x">
        <nd ref="1"/><nd ref="2"/>
        <tag k="highway" v="primary"/>
        <tag k="note" v='line&#10;break	tab
    newline'/>
        <tag k="highway" v="secondary"/>
      </way>
      <relation id="9">
        <member type="way" ref="7" role="from"/>
        <member type="area" ref="1" role="x"/>
        <member type="node" ref="2" role="via"/>
      </relation>
    </osm>
    """

    @Test func readsElementsInOrder() throws {
        var seen: [String] = []
        try parse(Array(Self.sample.utf8)) { elem in
            switch elem {
            case .timestamp(let t): seen.append("t\(t)")
            case .bounds(let a, let b, let c, let d): seen.append("b\(a),\(b),\(c),\(d)")
            case .node(let id, let lon, let lat, let tags, let version):
                seen.append("n\(id.id) \(lon) \(lat) \(tags["name"] ?? "-") \(version.map(String.init) ?? "nil")")
            case .way(let id, let nodes, let tags, let version):
                seen.append("w\(id.id) \(nodes.map(\.id)) \(tags["highway"]!) [\(tags["note"]!)] \(version.map(String.init) ?? "nil")")
            case .relation(let id, _, let members, _):
                seen.append("r\(id.id) \(members.map { "\($0.0):\($0.1.innerID)" })")
            }
        }
        #expect(seen == [
            "t1704164645",
            "b2.5,1.5,4.5,3.5",
            "n1 20.5 10.25 A & B <AB> 3",
            "n2 0.0 -0.001 - nil",
            "w7 [1, 2] secondary [line\nbreak tab newline] nil",
            "r9 [\"from:7\", \"via:2\"]",
        ])
    }

    @Test func refusesPBF() {
        #expect(throws: OSMReaderError.self) { try parse([0, 0, 0, 13, 10]) { _ in } }
    }

    @Test func rustFloatParsing() {
        #expect(parseRustF64("1.5") == 1.5)
        #expect(parseRustF64("+2") == 2)
        #expect(parseRustF64("inf") == .infinity)
        #expect(parseRustF64("0x10") == nil)
        #expect(parseRustF64("abc") == nil)
    }
}
