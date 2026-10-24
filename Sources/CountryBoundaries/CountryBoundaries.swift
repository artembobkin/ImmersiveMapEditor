/// Which countries and subdivisions a position or a box lies in, from a raster of boundaries.
///
/// Ported from `lib.rs` of the Rust crate country-boundaries 1.2.0 (Apache-2.0). The world is
/// a raster of cells, row by row from the north-west corner. A cell lists the regions covering
/// it whole and, with polygons in the cell's local coordinates, those covering part of it.

import Foundation

/// The boundaries of the countries and their subdivisions of the world.
public struct CountryBoundaries: Equatable, Sendable {
    /// The cells, row by row from the north-west corner.
    let raster: [Cell]
    /// The number of cells in a row.
    let rasterWidth: Int
    /// The size of every region, which orders the results of `ids`.
    let geometrySizes: [String: Double]

    init(raster: [Cell], rasterWidth: Int, geometrySizes: [String: Double]) {
        self.raster = raster
        self.rasterWidth = rasterWidth
        self.geometrySizes = geometrySizes
    }

    /// Reads boundaries from the bytes of a boundaries file, or throws if they are not one.
    public init(data: Data) throws {
        var reader = ByteReader([UInt8](data))
        self = try reader.readBoundaries()
    }

    /// Reads boundaries from the bytes of a boundaries file, as `from_reader` of the crate.
    public static func fromReader(_ data: Data) throws -> CountryBoundaries {
        try CountryBoundaries(data: data)
    }

    /// Returns whether the position is in the region with the given id.
    public func isIn(_ position: LatLon, _ id: String) -> Bool {
        let (cell, point) = cellAndLocalPoint(position)
        return cell.isIn(point, id)
    }

    /// Returns whether the position is in any of the regions with the given ids. It is faster
    /// than calling `isIn` for every id in turn.
    public func isInAny(_ position: LatLon, _ ids: Set<String>) -> Bool {
        let (cell, point) = cellAndLocalPoint(position)
        return cell.isInAny(point, ids)
    }

    /// Returns the ids of the regions the position is in, ordered by the size of the region
    /// ascending. A region with no size counts as 0. Regions of equal size keep the order of
    /// the cell (partly covering regions first), as the crate's stable sort does.
    public func ids(_ position: LatLon) -> [String] {
        let (cell, point) = cellAndLocalPoint(position)
        let result = cell.getIds(point)
        let keys = result.map { totalOrderKey(geometrySizes[$0] ?? 0.0) }
        let order = result.indices.sorted { a, b in
            keys[a] != keys[b] ? keys[a] < keys[b] : a < b
        }
        return order.map { result[$0] }
    }

    /// Returns the ids of the regions that fully contain the box. The box may wrap around the
    /// 180th meridian.
    public func containingIds(_ bounds: BoundingBox) -> Set<String> {
        var ids: Set<String> = []
        var firstCell = true
        for cell in cells(bounds) {
            if firstCell {
                ids.formUnion(cell.containingIds)
                firstCell = false
            } else {
                ids = ids.filter { id in cell.containingIds.contains { $0 == id } }
                if ids.isEmpty {
                    return ids
                }
            }
        }
        return ids
    }

    /// Returns the ids of the regions that contain or at least intersect the box. The box may
    /// wrap around the 180th meridian.
    public func intersectingIds(_ bounds: BoundingBox) -> Set<String> {
        var ids: Set<String> = []
        for cell in cells(bounds) {
            ids.formUnion(cell.getAllIds())
        }
        return ids
    }
}

// MARK: - The raster

extension CountryBoundaries {
    /// The number of rows of the raster.
    private var rasterHeight: Double {
        Double(raster.count / rasterWidth)
    }

    /// Returns the cell the position falls in and the position in the cell's local coordinates.
    func cellAndLocalPoint(_ position: LatLon) -> (Cell, Point) {
        let normalizedLongitude = normalize(position.longitude, startAt: -180.0, base: 360.0)
        let cellX = longitudeToCellX(normalizedLongitude)
        let cellY = latitudeToCellY(position.latitude)
        return (
            cell(cellX, cellY),
            Point(
                x: longitudeToLocalX(cellX, normalizedLongitude),
                y: latitudeToLocalY(cellY, position.latitude)
            )
        )
    }

    func cell(_ x: Int, _ y: Int) -> Cell {
        raster[y * rasterWidth + x]
    }

    func longitudeToCellX(_ longitude: Double) -> Int {
        let width = Double(rasterWidth)
        return min(max(rasterWidth - 1, 0), saturatingInt((width * (180.0 + longitude) / 360.0).rounded(.down)))
    }

    func latitudeToCellY(_ latitude: Double) -> Int {
        max(saturatingInt((rasterHeight * (90.0 - latitude) / 180.0).rounded(.up)) - 1, 0)
    }

    func longitudeToLocalX(_ cellX: Int, _ longitude: Double) -> UInt16 {
        let width = Double(rasterWidth)
        let cellLongitude = -180.0 + 360.0 * Double(cellX) / width
        return saturatingUInt16((longitude - cellLongitude) * width * Double(0xffff) / 360.0)
    }

    func latitudeToLocalY(_ cellY: Int, _ latitude: Double) -> UInt16 {
        let height = rasterHeight
        let cellLatitude = 90.0 - 180.0 * (Double(cellY) + 1.0) / height
        return saturatingUInt16((latitude - cellLatitude) * height * Double(0xffff) / 180.0)
    }

    /// Returns the cells the box covers, column by column from the west and, in a column, from
    /// the north. The columns wrap around the 180th meridian.
    func cells(_ bounds: BoundingBox) -> [Cell] {
        let normalizedMinLongitude = normalize(bounds.minLongitude, startAt: -180.0, base: 360.0)
        let normalizedMaxLongitude = normalize(bounds.maxLongitude, startAt: -180.0, base: 360.0)

        let minX = longitudeToCellX(normalizedMinLongitude)
        let maxY = latitudeToCellY(bounds.minLatitude)
        let maxX = longitudeToCellX(normalizedMaxLongitude)
        let minY = latitudeToCellY(bounds.maxLatitude)

        let stepsY = maxY - minY
        // The box might wrap around the 180th meridian.
        let stepsX = minX > maxX ? rasterWidth - minX + maxX : maxX - minX

        var result: [Cell] = []
        for xStep in 0...stepsX {
            let x = (minX + xStep) % rasterWidth
            for yStep in 0...stepsY {
                result.append(cell(x, minY + yStep))
            }
        }
        return result
    }
}

// MARK: - Numbers as Rust converts them

/// Returns the value moved by whole multiples of `base` into `startAt..<startAt + base`, with
/// the truncating remainder of Rust's `%` on floats.
func normalize(_ value: Double, startAt: Double, base: Double) -> Double {
    var value = value.truncatingRemainder(dividingBy: base)
    if value < startAt {
        value += base
    } else if value >= startAt + base {
        value -= base
    }
    return value
}

/// Converts as Rust's `as usize` does: NaN and negative values give 0, too large values the maximum.
func saturatingInt(_ value: Double) -> Int {
    if value.isNaN || value <= 0 {
        return 0
    }
    if value >= Double(Int.max) {
        return Int.max
    }
    return Int(value)
}

/// Converts as Rust's `as u16` does: truncated toward zero, NaN and negative values give 0, too
/// large values 0xffff.
func saturatingUInt16(_ value: Double) -> UInt16 {
    if value.isNaN || value <= 0 {
        return 0
    }
    if value >= Double(UInt16.max) {
        return UInt16.max
    }
    return UInt16(value)
}

/// Returns a key whose integer order is the IEEE 754 total order of the doubles, as Rust's
/// `f64::total_cmp` compares them.
func totalOrderKey(_ value: Double) -> Int64 {
    var bits = Int64(bitPattern: value.bitPattern)
    bits ^= Int64(bitPattern: UInt64(bitPattern: bits >> 63) >> 1)
    return bits
}
