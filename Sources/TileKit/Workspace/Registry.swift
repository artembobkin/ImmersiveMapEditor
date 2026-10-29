import Foundation
import SQLite3

/// The data folder's registry, an SQLite file (`registry.sqlite`) beside
/// the tiles (the user, 2026-10-29: a database over JSON files for what
/// the tiles share): the last build of every tile, and every landmark
/// with the OSM buildings it is made of, so a building modelled in one
/// tile is never modelled again in a neighbour that holds it too. A tile
/// builds the landmarks whose origin stands in it, and takes a neighbour's
/// within its margin for the light alone.
public final class Registry {
    public struct TileRecord {
        public var z: Int, x: Int, y: Int
        public var state: String
        public var built: String
        public var seconds: Double
        public var triangles: Int
        public var detail: String
    }

    public struct LandmarkRecord {
        public var id: String
        public var name: String
        public var z: Int, x: Int, y: Int
        /// The folder, relative to the data folder.
        public var folder: String
        public var latitude: Double, longitude: Double
        public var hasModel: Bool
        public var buildings: [String]
        public var tile: String { "\(z)/\(x)/\(y)" }
    }

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    private var db: OpaquePointer?
    public let url: URL

    public static func file(_ paths: WorkspacePaths) -> URL { paths.root.appendingPathComponent("registry.sqlite") }

    public init(_ paths: WorkspacePaths) throws {
        url = Self.file(paths)
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw Failure(description: "cannot open \(url.path): \(String(cString: sqlite3_errmsg(db)))")
        }
        try run("""
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS tiles (
            z INTEGER NOT NULL, x INTEGER NOT NULL, y INTEGER NOT NULL,
            state TEXT NOT NULL, built TEXT NOT NULL, seconds REAL NOT NULL DEFAULT 0,
            triangles INTEGER NOT NULL DEFAULT 0, detail TEXT NOT NULL DEFAULT '',
            PRIMARY KEY (z, x, y));
        CREATE TABLE IF NOT EXISTS landmarks (
            z INTEGER NOT NULL, x INTEGER NOT NULL, y INTEGER NOT NULL, id TEXT NOT NULL,
            name TEXT NOT NULL, folder TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL,
            has_model INTEGER NOT NULL DEFAULT 0, updated TEXT NOT NULL,
            PRIMARY KEY (z, x, y, id));
        CREATE TABLE IF NOT EXISTS landmark_buildings (
            osm TEXT PRIMARY KEY NOT NULL,
            z INTEGER NOT NULL, x INTEGER NOT NULL, y INTEGER NOT NULL, id TEXT NOT NULL);
        """)
    }

    deinit { sqlite3_close(db) }

    // MARK: Tiles

    /// Records a tile's build, over the last.
    public func record(tile z: Int, _ x: Int, _ y: Int, state: String, seconds: Double, triangles: Int, detail: String) throws {
        let q = try prepare("INSERT OR REPLACE INTO tiles (z, x, y, state, built, seconds, triangles, detail) VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
        defer { sqlite3_finalize(q) }
        sqlite3_bind_int(q, 1, Int32(z)); sqlite3_bind_int(q, 2, Int32(x)); sqlite3_bind_int(q, 3, Int32(y))
        bind(q, 4, state); bind(q, 5, Self.now()); sqlite3_bind_double(q, 6, seconds)
        sqlite3_bind_int64(q, 7, Int64(triangles)); bind(q, 8, detail)
        try step(q)
    }

    public func tiles(z: Int? = nil) -> [TileRecord] {
        var out: [TileRecord] = []
        guard let q = try? prepare("SELECT z, x, y, state, built, seconds, triangles, detail FROM tiles" + (z == nil ? "" : " WHERE z = ?") + " ORDER BY z, x, y") else { return [] }
        defer { sqlite3_finalize(q) }
        if let z { sqlite3_bind_int(q, 1, Int32(z)) }
        while sqlite3_step(q) == SQLITE_ROW {
            out.append(TileRecord(z: Int(sqlite3_column_int(q, 0)), x: Int(sqlite3_column_int(q, 1)), y: Int(sqlite3_column_int(q, 2)),
                                  state: text(q, 3), built: text(q, 4), seconds: sqlite3_column_double(q, 5),
                                  triangles: Int(sqlite3_column_int64(q, 6)), detail: text(q, 7)))
        }
        return out
    }

    // MARK: Landmarks

    /// Registers a landmark with its buildings. A building held by another
    /// landmark (of any tile) refuses it, naming the holder.
    public func register(_ l: LandmarkRecord) throws {
        for osm in l.buildings {
            if let holder = landmark(holding: osm), !(holder.z == l.z && holder.x == l.x && holder.y == l.y && holder.id == l.id) {
                throw Failure(description: "\(osm) is already part of the landmark \"\(holder.name)\" of tile \(holder.tile)")
            }
        }
        try run("BEGIN")
        do {
            let q = try prepare("INSERT OR REPLACE INTO landmarks (z, x, y, id, name, folder, latitude, longitude, has_model, updated) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
            sqlite3_bind_int(q, 1, Int32(l.z)); sqlite3_bind_int(q, 2, Int32(l.x)); sqlite3_bind_int(q, 3, Int32(l.y))
            bind(q, 4, l.id); bind(q, 5, l.name); bind(q, 6, l.folder)
            sqlite3_bind_double(q, 7, l.latitude); sqlite3_bind_double(q, 8, l.longitude)
            sqlite3_bind_int(q, 9, l.hasModel ? 1 : 0); bind(q, 10, Self.now())
            try step(q)
            sqlite3_finalize(q)
            let clear = try prepare("DELETE FROM landmark_buildings WHERE z = ? AND x = ? AND y = ? AND id = ?")
            sqlite3_bind_int(clear, 1, Int32(l.z)); sqlite3_bind_int(clear, 2, Int32(l.x)); sqlite3_bind_int(clear, 3, Int32(l.y)); bind(clear, 4, l.id)
            try step(clear)
            sqlite3_finalize(clear)
            for osm in l.buildings {
                let b = try prepare("INSERT OR REPLACE INTO landmark_buildings (osm, z, x, y, id) VALUES (?, ?, ?, ?, ?)")
                bind(b, 1, osm); sqlite3_bind_int(b, 2, Int32(l.z)); sqlite3_bind_int(b, 3, Int32(l.x)); sqlite3_bind_int(b, 4, Int32(l.y)); bind(b, 5, l.id)
                try step(b)
                sqlite3_finalize(b)
            }
            try run("COMMIT")
        } catch {
            try? run("ROLLBACK")
            throw error
        }
    }

    public func remove(landmark id: String, z: Int, x: Int, y: Int) throws {
        for sql in ["DELETE FROM landmark_buildings WHERE z = ? AND x = ? AND y = ? AND id = ?", "DELETE FROM landmarks WHERE z = ? AND x = ? AND y = ? AND id = ?"] {
            let q = try prepare(sql)
            sqlite3_bind_int(q, 1, Int32(z)); sqlite3_bind_int(q, 2, Int32(x)); sqlite3_bind_int(q, 3, Int32(y)); bind(q, 4, id)
            try step(q)
            sqlite3_finalize(q)
        }
    }

    /// The landmark an OSM building is part of, if any.
    public func landmark(holding osm: String) -> LandmarkRecord? {
        guard let q = try? prepare("SELECT z, x, y, id FROM landmark_buildings WHERE osm = ?") else { return nil }
        defer { sqlite3_finalize(q) }
        bind(q, 1, osm)
        guard sqlite3_step(q) == SQLITE_ROW else { return nil }
        let (z, x, y, id) = (Int(sqlite3_column_int(q, 0)), Int(sqlite3_column_int(q, 1)), Int(sqlite3_column_int(q, 2)), text(q, 3))
        return landmarks(z: z).first { $0.x == x && $0.y == y && $0.id == id }
    }

    /// Every landmark of a zoom, with its buildings.
    public func landmarks(z: Int) -> [LandmarkRecord] {
        var out: [LandmarkRecord] = []
        guard let q = try? prepare("SELECT z, x, y, id, name, folder, latitude, longitude, has_model FROM landmarks WHERE z = ? ORDER BY x, y, id") else { return [] }
        sqlite3_bind_int(q, 1, Int32(z))
        while sqlite3_step(q) == SQLITE_ROW {
            out.append(LandmarkRecord(id: text(q, 3), name: text(q, 4), z: Int(sqlite3_column_int(q, 0)), x: Int(sqlite3_column_int(q, 1)),
                                      y: Int(sqlite3_column_int(q, 2)), folder: text(q, 5), latitude: sqlite3_column_double(q, 6),
                                      longitude: sqlite3_column_double(q, 7), hasModel: sqlite3_column_int(q, 8) != 0, buildings: []))
        }
        sqlite3_finalize(q)
        for i in out.indices {
            guard let b = try? prepare("SELECT osm FROM landmark_buildings WHERE z = ? AND x = ? AND y = ? AND id = ? ORDER BY osm") else { continue }
            sqlite3_bind_int(b, 1, Int32(out[i].z)); sqlite3_bind_int(b, 2, Int32(out[i].x)); sqlite3_bind_int(b, 3, Int32(out[i].y)); bind(b, 4, out[i].id)
            while sqlite3_step(b) == SQLITE_ROW { out[i].buildings.append(text(b, 0)) }
            sqlite3_finalize(b)
        }
        return out
    }

    /// The registry brought up to date with the landmark folders on disk:
    /// every `landmark.json` under tiles/<z>/<x>/<y>/landmarks/ registered
    /// (a folder whose building another landmark holds is reported, not
    /// registered), and a landmark whose folder is gone dropped. Returns
    /// what it found wrong.
    @discardableResult
    public func sync(_ paths: WorkspacePaths) -> [String] {
        let fm = FileManager.default
        var problems: [String] = []
        var seen = Set<String>()
        for zName in (try? fm.contentsOfDirectory(atPath: paths.tiles.path)) ?? [] {
            guard let z = Int(zName) else { continue }
            let zoom = paths.tiles.appendingPathComponent(zName)
            for xName in (try? fm.contentsOfDirectory(atPath: zoom.path)) ?? [] {
                guard let x = Int(xName) else { continue }
                for yName in (try? fm.contentsOfDirectory(atPath: zoom.appendingPathComponent(xName).path)) ?? [] {
                    guard let y = Int(yName) else { continue }
                    let root = paths.tileLandmarks(z: z, x: x, y: y)
                    for id in ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted() {
                        let folder = root.appendingPathComponent(id)
                        guard let data = fm.contents(atPath: folder.appendingPathComponent("landmark.json").path),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let centre = json["centre"] as? [Double], centre.count == 2 else { continue }
                        seen.insert("\(z)/\(x)/\(y)/\(id)")
                        let hasModel = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).contains { $0.hasSuffix(".glb") }
                        let buildings = (json["buildings"] as? [[String: Any]] ?? []).compactMap { $0["osm"] as? String }
                        let record = LandmarkRecord(id: id, name: json["name"] as? String ?? id, z: z, x: x, y: y,
                                                    folder: "tiles/\(z)/\(x)/\(y)/landmarks/\(id)", latitude: centre[1], longitude: centre[0],
                                                    hasModel: hasModel, buildings: buildings)
                        do { try register(record) } catch { problems.append("\(record.folder): \(error)") }
                    }
                }
            }
        }
        for l in (try? zooms())?.flatMap({ landmarks(z: $0) }) ?? [] where !seen.contains("\(l.z)/\(l.x)/\(l.y)/\(l.id)") {
            try? remove(landmark: l.id, z: l.z, x: l.x, y: l.y)
        }
        return problems
    }

    private func zooms() throws -> [Int] {
        let q = try prepare("SELECT DISTINCT z FROM landmarks")
        defer { sqlite3_finalize(q) }
        var out: [Int] = []
        while sqlite3_step(q) == SQLITE_ROW { out.append(Int(sqlite3_column_int(q, 0))) }
        return out
    }

    // MARK: SQLite

    private func run(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? "?"
            sqlite3_free(message)
            throw Failure(description: "registry: \(text)")
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var q: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &q, nil) == SQLITE_OK, let q else {
            throw Failure(description: "registry: \(String(cString: sqlite3_errmsg(db)))")
        }
        return q
    }

    private func step(_ q: OpaquePointer) throws {
        guard sqlite3_step(q) == SQLITE_DONE else { throw Failure(description: "registry: \(String(cString: sqlite3_errmsg(db)))") }
    }

    private func bind(_ q: OpaquePointer, _ i: Int32, _ s: String) {
        sqlite3_bind_text(q, i, s, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func text(_ q: OpaquePointer, _ i: Int32) -> String {
        sqlite3_column_text(q, i).map { String(cString: $0) } ?? ""
    }

    private static func now() -> String { ISO8601DateFormatter().string(from: Date()) }
}
