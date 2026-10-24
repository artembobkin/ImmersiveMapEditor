/// geo's `Centroid` (identical in geo 0.27 and 0.28) for lines, line strings, polygons,
/// multi-polygons and rectangles: centroids weighted by area, length or count, where the highest
/// dimension present wins.

/// geo's `Dimensions`, in its order.
enum GeoDimensions: Int, Comparable {
    case empty
    case zeroDimensional
    case oneDimensional
    case twoDimensional

    static func < (lhs: GeoDimensions, rhs: GeoDimensions) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension GeoLine {
    var dimensions: GeoDimensions { start == end ? .zeroDimensional : .oneDimensional }

    public var centroid: GeoPoint { (startPoint + endPoint) / (1.0 + 1.0) }
}

extension GeoLineString {
    var dimensions: GeoDimensions {
        if coords.isEmpty {
            return .empty
        }
        let first = coords[0]
        return coords.contains { $0 != first } ? .oneDimensional : .zeroDimensional
    }

    /// The mean of the segment midpoints weighted by length, `nil` if empty.
    public var centroid: GeoPoint? {
        var operation = CentroidOperation()
        operation.addLineString(self)
        return operation.centroid
    }
}

extension GeoMultiLineString {
    public var centroid: GeoPoint? {
        var operation = CentroidOperation()
        if operation.centroidDimensions <= .oneDimensional {
            for lineString in lineStrings {
                operation.addLineString(lineString)
            }
        }
        return operation.centroid
    }
}

extension GeoPolygon {
    public var centroid: GeoPoint? {
        var operation = CentroidOperation()
        operation.addPolygon(self)
        return operation.centroid
    }
}

extension GeoMultiPolygon {
    public var centroid: GeoPoint? {
        var operation = CentroidOperation()
        for polygon in polygons {
            operation.addPolygon(polygon)
        }
        return operation.centroid
    }
}

extension GeoRect {
    public var centroid: GeoPoint { GeoPoint(center) }
}

/// geo's `WeightedCentroid`.
struct WeightedCentroid {
    var weight: Double
    var accumulated: GeoCoord
    var dimensions: GeoDimensions

    mutating func addAssign(_ b: WeightedCentroid) {
        if dimensions < b.dimensions {
            self = b
        } else if dimensions == b.dimensions {
            accumulated = accumulated + b.accumulated
            weight = weight + b.weight
        }
    }

    mutating func subAssign(_ b: WeightedCentroid) {
        if dimensions < b.dimensions {
            self = b
        } else if dimensions == b.dimensions {
            accumulated = accumulated - b.accumulated
            weight = weight - b.weight
        }
    }
}

/// geo's `CentroidOperation`.
struct CentroidOperation {
    var weighted: WeightedCentroid?

    var centroid: GeoPoint? {
        weighted.map { GeoPoint($0.accumulated / $0.weight) }
    }

    var centroidDimensions: GeoDimensions {
        weighted?.dimensions ?? .empty
    }

    mutating func addCoord(_ coord: GeoCoord) {
        addCentroid(.zeroDimensional, coord, 1.0)
    }

    mutating func addLine(_ line: GeoLine) {
        switch line.dimensions {
        case .zeroDimensional:
            addCoord(line.start)
        case .oneDimensional:
            addCentroid(.oneDimensional, line.centroid.coord, line.euclideanLength)
        default:
            preconditionFailure("Line must be zero or one dimensional")
        }
    }

    mutating func addLineString(_ lineString: GeoLineString) {
        if centroidDimensions > .oneDimensional {
            return
        }
        if lineString.coords.count == 1 {
            addCoord(lineString.coords[0])
            return
        }
        for line in lineString.lines {
            addLine(line)
        }
    }

    mutating func addPolygon(_ polygon: GeoPolygon) {
        // A polygon whose holes cover it has no area and degenerates to a line string, so the
        // rings are accumulated apart and only then merged.
        var exteriorOperation = CentroidOperation()
        exteriorOperation.addRing(polygon.exterior)
        var interiorOperation = CentroidOperation()
        for interior in polygon.interiors {
            interiorOperation.addRing(interior)
        }
        if var polyWeightedCentroid = exteriorOperation.weighted {
            if let interiorWeightedCentroid = interiorOperation.weighted {
                polyWeightedCentroid.subAssign(interiorWeightedCentroid)
                if polyWeightedCentroid.weight == 0 {
                    addLineString(polygon.exterior)
                    return
                }
            }
            addWeightedCentroid(polyWeightedCentroid)
        }
    }

    mutating func addRing(_ ring: GeoLineString) {
        let area = getLineStringArea(ring)
        if area == 0 {
            switch ring.dimensions {
            case .empty:
                // An empty ring does not contribute.
                break
            case .zeroDimensional:
                // A degenerate ring is a point.
                addCoord(ring.coords[0])
            default:
                // A ring without area is a line string.
                addLineString(ring)
            }
            return
        }
        // The area is not zero, so the ring has a coordinate.
        let shift = ring.coords[0]
        var accumulatedCoord = GeoCoord.zero
        for line in ring.lines {
            let shifted = GeoLine(line.start - shift, line.end - shift)
            let tmp = shifted.determinant
            accumulatedCoord = accumulatedCoord + (shifted.end + shifted.start) * tmp
        }
        let six = 6.0
        let centroid = accumulatedCoord / (six * area) + shift
        let weight = abs(area)
        addCentroid(.twoDimensional, centroid, weight)
    }

    mutating func addCentroid(_ dimensions: GeoDimensions, _ centroid: GeoCoord, _ weight: Double) {
        addWeightedCentroid(WeightedCentroid(weight: weight, accumulated: centroid * weight, dimensions: dimensions))
    }

    mutating func addWeightedCentroid(_ other: WeightedCentroid) {
        if weighted != nil {
            weighted!.addAssign(other)
        } else {
            weighted = other
        }
    }
}
