/// The Rust osm2streets the parity tests compare against: the pipeline's
/// command line build of revision fc119c4, and where the cases live. Every
/// path is a default of the workspace on this machine. A test skips when
/// its files are missing.

import Foundation

enum Oracle {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let binary = home.appendingPathComponent("Desktop/TilePipeline/tools/osm2streets_cli/target/release/osm2streets-cli")
    static let testsDir = home.appendingPathComponent(".cargo/git/checkouts/osm2streets-44d45045ef4b7acf/fc119c4/tests/src")
    static let tilePipelineData = home.appendingPathComponent("Desktop/TilePipeline/data")
    static let scratch = URL(fileURLWithPath: "/private/tmp/claude-501/streets-parity")

    static var available: Bool { FileManager.default.isExecutableFile(atPath: binary.path) }

    static let outputs = ["plain", "lanes", "lane_markings", "intersection_markings"]

    /// Runs the binary: `<input> <clip | -> <out dir>`. Returns its outputs by name.
    static func run(input: URL, clip: URL?, out: URL) throws -> [String: String] {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = binary
        p.arguments = [input.path, clip?.path ?? "-", out.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let log = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw OracleError.failed(String(decoding: log.suffix(2000), as: UTF8.self))
        }
        var result: [String: String] = [:]
        for name in outputs {
            result[name] = try String(contentsOf: out.appendingPathComponent("\(name).geojson"), encoding: .utf8)
        }
        return result
    }
}

enum OracleError: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self {
        case .failed(let log): return "osm2streets-cli failed: \(log)"
        }
    }
}
