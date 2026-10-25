import Foundation
import Observation

/// Where a road document lives on disk and when it is written: a moment
/// after the last change (a drag saves once, when it stops), or at once when
/// asked (before another document opens, when the app goes to the
/// background).
@Observable
@MainActor
final class DocumentStore {
    let url: URL
    private(set) var dirty = false
    private(set) var status = ""
    @ObservationIgnored private var saving: Task<Void, Never>?
    @ObservationIgnored private let delay: Duration

    init(url: URL, delay: Duration = .seconds(1.5)) {
        self.url = url
        self.delay = delay
    }

    /// The document changed: it is written a moment later by `write`.
    func changed(_ write: @escaping @MainActor () throws -> Void) {
        dirty = true
        saving?.cancel()
        saving = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, dirty else { return }
            save(write)
        }
    }

    func save(_ write: @MainActor () throws -> Void) {
        saving?.cancel()
        do {
            try write()
            dirty = false
            status = "Saved \(url.lastPathComponent)"
        } catch {
            status = "Not saved: \(error.localizedDescription)"
        }
    }

    func say(_ s: String) { status = s }
}
