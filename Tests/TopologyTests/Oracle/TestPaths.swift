import Foundation

/// Where the parity tests find what stays outside git: the JTS 1.20.0
/// sources (their XML test suites) and the recorded calls of `Geometry`.
enum TestPaths {
    /// The package folder, from this file's place in it.
    static let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// The JTS clone: `JTS_ROOT`, else `.build/ports/jts` of this package or
    /// of a folder above it (a worktree inside the main checkout).
    static let jts: URL? = {
        if let root = ProcessInfo.processInfo.environment["JTS_ROOT"] { return URL(fileURLWithPath: root) }
        var dir = package
        for _ in 0..<4 {
            let candidate = dir.appendingPathComponent(".build/ports/jts")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("modules").path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }()

    /// The JTS XML suites the goal names, in this order.
    static let suites = ["general", "validate", "robust", "misc"]

    /// The XML files of a suite, with its subfolders, sorted by path.
    static func xmlFiles(_ suite: String) -> [URL] {
        guard let jts else { return [] }
        let dir = jts.appendingPathComponent("modules/tests/src/test/resources/testxml/\(suite)")
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return files.filter { $0.pathExtension == "xml" }.sorted { $0.path < $1.path }
    }

    /// A file's name relative to the testxml folder (`general/TestBoundary.xml`).
    static func name(_ url: URL) -> String {
        let parts = url.standardizedFileURL.pathComponents
        guard let i = parts.lastIndex(of: "testxml") else { return url.lastPathComponent }
        return parts[(i + 1)...].joined(separator: "/")
    }

    /// The recordings of `Geometry` (its `GEOMETRY_RECORD` mode):
    /// `GEOMETRY_REPLAY`, else `.build/recording` of this package.
    static let recording: URL = {
        if let dir = ProcessInfo.processInfo.environment["GEOMETRY_REPLAY"] { return URL(fileURLWithPath: dir) }
        return package.appendingPathComponent(".build/recording")
    }()
}
