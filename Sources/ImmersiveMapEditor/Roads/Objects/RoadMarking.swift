import Foundation
import Geometry
import TileKit

/// A road marking, painted on the roadway and kept as parameters: the
/// parent of LineMarking, ZebraMarking, ZigzagMarking and LetterMarking.
/// The file names a marking's kind; `make` is the one place that reads it,
/// `export` the one that writes it.
class RoadMarking: RoadObject {
    /// The file's name of the kind ("zebra").
    class var fileKind: String { "line" }

    /// A marking of the file as its class, in local metres by `m`.
    static func make(_ k: Mark, _ m: (P2) -> Vec2) -> RoadMarking {
        let centre = k.centre.map(m) ?? .zero
        switch k.kind {
        case ZebraMarking.fileKind:
            return ZebraMarking(id: k.id, centre: centre, heading: k.heading, span: k.span, bar: k.bar, length: k.length)
        case ZigzagMarking.fileKind:
            return ZigzagMarking(id: k.id, points: k.points.map(m), side: k.side, step: k.step, depth: k.depth)
        case LetterMarking.fileKind:
            return LetterMarking(id: k.id, text: k.text, centre: centre, heading: k.heading, size: k.size)
        default:
            return LineMarking(id: k.id, style: k.style, colour: k.colour, points: k.points.map(m))
        }
    }

    override func export(into doc: inout RoadDocument, _ ll: (Vec2) -> P2) {
        var k = Mark(kind: type(of: self).fileKind)
        k.id = id
        fill(&k, ll)
        doc.markings.append(k)
    }

    /// Writes its own parameters into the file's marking.
    func fill(_ k: inout Mark, _ ll: (Vec2) -> P2) {}
}
