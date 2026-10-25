import Foundation

/// A JTS XML test file (`modules/tests/src/test/resources/testxml/`), read
/// as JTS's `TestReader` reads it: a run of cases, each with geometries `a`
/// and `b` in WKT and tests, each test an operation on them with its
/// arguments and the expected result as text.
struct JTSTestFile {
    struct Case {
        var index: Int
        var description: String
        var a: String?
        var b: String?
        var tests: [Test]
    }

    struct Test {
        var index: Int
        /// The operation's name as written (`getCentroid`, `relate`).
        var operation: String
        /// `arg1`: the geometry it runs on, `A` or `B`.
        var target: String
        /// `arg2`, `arg3` (and a relate's `pattern`), as written.
        var arguments: [String]
        /// The expected result as text, nil when the test has none.
        var expected: String?
    }

    var name: String
    /// The precision model: nil for floating, else the scale of a fixed one.
    var fixedScale: Double?
    /// The coordinate tolerance of geometry and number results.
    var tolerance: Double
    /// The class of `<resultMatcher>`, `<geometryOperation>`, when given.
    var resultMatcher: String?
    var geometryOperation: String?
    var cases: [Case]

    init(url: URL) throws {
        let root = try XMLTree.parse(url)
        guard root.name.lowercased() == "run" else { throw ParseError("\(url.lastPathComponent): no <run>") }
        name = TestPaths.name(url)
        tolerance = Double(root.child("tolerance")?.text.trimmed ?? "") ?? 0
        resultMatcher = root.child("resultMatcher")?.text.trimmed
        geometryOperation = root.child("geometryOperation")?.text.trimmed
        fixedScale = nil
        if let pm = root.child("precisionModel") {
            let type = pm.attributes["type"]?.trimmed.uppercased()
            if let scale = pm.attributes["scale"].flatMap({ Double($0.trimmed) }), type != "FLOATING" {
                fixedScale = scale
            }
        }
        var cases: [Case] = []
        for (ci, c) in root.children(named: "case").enumerated() {
            var tests: [Test] = []
            for (ti, t) in c.children(named: "test").enumerated() {
                guard let op = t.child("op"), let name = op.attributes["name"]?.trimmed else {
                    throw ParseError("\(url.lastPathComponent) case \(ci + 1): a test without <op name>")
                }
                var arguments = [op.attributes["arg2"], op.attributes["arg3"]].compactMap { $0?.trimmed }
                if op.attributes["arg3"] == nil, name.lowercased() == "relate", let pattern = op.attributes["pattern"] {
                    arguments.append(pattern.trimmed)
                }
                let expected = op.text.trimmed
                tests.append(Test(index: ti + 1, operation: name, target: op.attributes["arg1"]?.trimmed ?? "A",
                                  arguments: arguments, expected: expected.isEmpty ? nil : expected))
            }
            cases.append(Case(index: ci + 1, description: c.child("desc")?.text.trimmed ?? "",
                              a: c.child("a")?.text.trimmed, b: c.child("b")?.text.trimmed, tests: tests))
        }
        self.cases = cases
    }

    struct ParseError: Error, CustomStringConvertible {
        var description: String
        init(_ d: String) { description = d }
    }
}

/// A small DOM over Foundation's `XMLParser`: elements, their attributes,
/// their text and their children.
final class XMLTree: NSObject, XMLParserDelegate {
    final class Element {
        let name: String
        let attributes: [String: String]
        var text = ""
        var children: [Element] = []

        init(name: String, attributes: [String: String]) {
            self.name = name
            self.attributes = attributes
        }

        func child(_ name: String) -> Element? { children.first { $0.name.lowercased() == name.lowercased() } }
        func children(named name: String) -> [Element] { children.filter { $0.name.lowercased() == name.lowercased() } }
    }

    private var stack: [Element] = []
    private var root: Element?

    static func parse(_ url: URL) throws -> Element {
        let tree = XMLTree()
        let parser = XMLParser(data: try Data(contentsOf: url))
        parser.delegate = tree
        guard parser.parse(), let root = tree.root else {
            throw JTSTestFile.ParseError("\(url.lastPathComponent): \(parser.parserError.map { "\($0)" } ?? "no root")")
        }
        return root
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let e = Element(name: name, attributes: attributes)
        stack.last?.children.append(e)
        if stack.isEmpty { root = e }
        stack.append(e)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        stack.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        stack.last?.text += String(decoding: block, as: UTF8.self)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
