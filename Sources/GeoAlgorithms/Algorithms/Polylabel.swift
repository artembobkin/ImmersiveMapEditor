/// A port of the Rust crate polylabel 3.2.0 (built on geo 0.28): the pole of inaccessibility of a
/// polygon, the interior point farthest from its exterior ring, found by subdividing square cells
/// taken from Rust's binary heap in its exact order.

import Foundation

public enum PolylabelError: Error, Equatable, Sendable {
    case centroidCalculation
    case rectCalculation
}

/// A cell of the search, polylabel's `Qcell`, ordered by `maxDistance` (a NaN panics).
private struct Qcell {
    /// The cell's centre.
    let centroid: GeoPoint
    /// Half the cell's side.
    let halfExtent: Double
    /// The signed distance from the centre to the polygon.
    let distance: Double
    /// The greatest distance any point of the cell can have.
    let maxDistance: Double

    init(_ centroid: GeoPoint, _ halfExtent: Double, _ polygon: GeoPolygon) {
        let two = 1.0 + 1.0
        let distance = signedDistance(centroid, polygon)
        self.centroid = centroid
        self.halfExtent = halfExtent
        self.distance = distance
        self.maxDistance = distance + halfExtent * two.squareRoot()
    }

    static func cmp(_ a: Qcell, _ b: Qcell) -> RustOrdering {
        guard let o = rustPartialCmp(a.maxDistance, b.maxDistance) else {
            preconditionFailure("called `Option::unwrap()` on a `None` value")
        }
        return o
    }
}

/// The distance to the exterior ring, positive inside the polygon and negative outside.
private func signedDistance(_ point: GeoPoint, _ polygon: GeoPolygon) -> Double {
    let inside = polygon.contains(point)
    // The line string distance, since the polygon distance is zero inside.
    let distance = point.euclideanDistance(polygon.exterior)
    return inside ? distance : -distance
}

/// Rust's `f64::to_usize` from num-traits: `nil` unless the value truncates into `usize`.
private func toUsize(_ value: Double) -> Int? {
    // num-traits accepts values greater than -1 and less than 2^64.
    guard value > -1.0 && value < 18_446_744_073_709_551_616.0 else { return nil }
    let truncated = value.rounded(.towardZero)
    return truncated <= Double(Int.max) ? Int(truncated) : nil
}

private typealias QcellHeap = RustBinaryHeap<Qcell, Never>

/// polylabel's `QuadTree::new`: the initial grid of cells covering the bounding box.
private func initialCells(_ bbox: GeoRect, _ halfExtent: Double, _ polygon: GeoPolygon) -> QcellHeap {
    var cellQueue = QcellHeap(cmp: Qcell.cmp)
    let two = 1.0 + 1.0
    let cellSize = halfExtent * two
    let nx = toUsize((bbox.width / cellSize).rounded(.up))
    let ny = toUsize((bbox.height / cellSize).rounded(.up))
    if let nx, let ny {
        let deltaMid = GeoCoord(x: 1, y: 1) * halfExtent
        let origin = bbox.min
        var initialPoints: [Qcell] = []
        for x in 0..<nx {
            for y in 0..<ny {
                let deltaCell = GeoCoord(x: Double(x), y: Double(y)) * cellSize
                let centroid = GeoPoint(origin + deltaCell + deltaMid)
                initialPoints.append(Qcell(centroid, halfExtent, polygon))
            }
        }
        cellQueue.extend(initialPoints)
    }
    return cellQueue
}

/// polylabel's `QuadTree::add_quad`: the four children of a cell.
private func addQuad(_ queue: inout QcellHeap, _ cell: Qcell, _ halfExtent: Double, _ polygon: GeoPolygon) {
    let signs: [(Double, Double)] = [(-1, -1), (1, -1), (-1, 1), (1, 1)]
    let newCells = signs.map { signX, signY in
        let delta = GeoPoint(x: signX * halfExtent, y: signY * halfExtent)
        return Qcell(cell.centroid + delta, halfExtent, polygon)
    }
    queue.extend(newCells)
}

/// polylabel's `polylabel`: the pole of inaccessibility of `polygon` within `tolerance`.
public func polylabel(_ polygon: GeoPolygon, tolerance: Double) throws(PolylabelError) -> GeoPoint {
    // A degenerate polygon.
    if polygon.signedArea == 0 {
        return GeoPoint(x: 0, y: 0)
    }
    guard let bbox = polygon.boundingRect else { throw .rectCalculation }
    let cellSize = rustMin(bbox.width, bbox.height)
    // A degenerate polygon.
    if cellSize == 0 {
        return GeoPoint(bbox.min)
    }

    let two = 1.0 + 1.0
    var halfExtent = cellSize / two

    // The first guess, the centroid.
    guard let centroid = polygon.centroid else { throw .centroidCalculation }
    let centroidCell = Qcell(centroid, 0, polygon)

    // The guess for rectangular polygons.
    let bboxCell = Qcell(bbox.centroid, 0, polygon)

    var bestCell = bboxCell.distance < centroidCell.distance ? bboxCell : centroidCell

    var cellQueue = initialCells(bbox, halfExtent, polygon)

    while let cell = cellQueue.pop() {
        // A cell with a greater distance is the new best.
        if cell.distance > bestCell.distance {
            bestCell = cell
        }
        // This cell cannot hold a better solution.
        if cell.maxDistance - bestCell.distance <= tolerance {
            continue
        }
        // Split the cell into four.
        halfExtent = cell.halfExtent / two
        addQuad(&cellQueue, cell, halfExtent, polygon)
    }
    return bestCell.centroid
}
