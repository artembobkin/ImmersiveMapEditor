import Darwin
import Foundation
import Security

/// The editor signed with the user's Apple Development certificate, by
/// itself: a build (Xcode's, or swift build's) leaves an ad hoc signature
/// that changes with every build, so the keychain (the proxy, the tokens)
/// and the folder permissions asked about the app on every launch. At
/// launch the editor looks at its own signature, and when it is ad hoc,
/// signs its file under one stable identifier with the first Apple
/// Development certificate of the keychain and runs itself again, signed.
/// The pipeline, the agent's tools and the snapshots start from the signed
/// file, so they pass straight through. With no certificate, nothing
/// changes.
enum CodeSigning {
    static let identifier = "com.artembobkin.ImmersiveMapEditor"

    /// Signs and runs again when needed. Returns only when the process is
    /// to go on as it is.
    static func signAndRelaunchIfAdHoc() {
        guard isAdHoc(), ProcessInfo.processInfo.environment["IMMERSIVE_MAP_EDITOR_SIGNED"] == nil,
              let identity = developmentIdentity() else { return }
        let path = Bundle.main.executableURL!.path
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", identity, "--identifier", identifier, path]
        sign.standardOutput = FileHandle.nullDevice
        sign.standardError = FileHandle.nullDevice
        guard (try? sign.run()) != nil else { return }
        sign.waitUntilExit()
        guard sign.terminationStatus == 0 else { return }
        FileHandle.standardError.write(Data("signed \(path) as \(identifier)\n".utf8))
        // The same arguments, the same environment, and a mark against a loop.
        setenv("IMMERSIVE_MAP_EDITOR_SIGNED", "1", 1)
        execv(path, CommandLine.unsafeArgv)
    }

    /// Whether this process's code is only ad hoc signed.
    static func isAdHoc() -> Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return false }
        let flags = (dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let adhoc = flags & SecCodeSignatureFlags.adhoc.rawValue != 0
        let ours = dict[kSecCodeInfoIdentifier as String] as? String == identifier
        return adhoc || !ours
    }

    /// The first Apple Development certificate of the keychain, by name.
    static func developmentIdentity() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-identity", "-v", "-p", "codesigning"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        for line in out.split(separator: "\n") {
            guard let start = line.range(of: "\"Apple Development:"), let end = line[start.upperBound...].firstIndex(of: "\"") else { continue }
            return String(line[start.lowerBound..<end].dropFirst())
        }
        return nil
    }
}
