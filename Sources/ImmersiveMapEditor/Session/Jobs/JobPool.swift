import Foundation
import Observation

/// Every job of the session, queued, running and ended: builds of several
/// tiles, Claude on several landmarks, at once (the user, 2026-11-02). A
/// job added is started as soon as its own rule allows it beside the jobs
/// running, and the pool starts the next whenever one changes state. One
/// ended job a subject is kept, so its log can be read where its subject
/// is shown, until the subject gets a new job.
@Observable
@MainActor
final class JobPool {
    private(set) var jobs: [any Job] = []

    /// The jobs still queued or going.
    var active: [any Job] { jobs.filter { $0.state.active } }
    var running: [any Job] { jobs.filter { $0.state.running } }
    var anyRunning: Bool { !active.isEmpty }

    /// The last job of a subject: the one going, or the last ended.
    func latest(of subject: JobSubject) -> (any Job)? { jobs.last { $0.subject == subject } }
    /// The last job of the subjects, whichever was added last.
    func latest(of subjects: [JobSubject]) -> (any Job)? { jobs.last { subjects.contains($0.subject) } }
    /// Whether the subject's own job is queued or going.
    func isActive(_ subject: JobSubject) -> Bool { latest(of: subject)?.state.active ?? false }

    /// What the pool is doing, for the status line: nothing when idle.
    var status: String? {
        let going = running.count, queued = active.count - going
        guard going + queued > 0 else { return nil }
        return "\(going) running" + (queued > 0 ? ", \(queued) queued" : "")
    }

    /// Queues a job, in place of its subject's ended one.
    func add(_ job: any Job) {
        jobs.removeAll { $0.subject == job.subject && !$0.state.active }
        job.stateChanged = { [weak self] in self?.pump() }
        jobs.append(job)
        pump()
    }

    func stop(_ subject: JobSubject) {
        if let job = latest(of: subject), job.state.active { job.stop() }
    }

    func stopAll() { for job in active { job.stop() } }

    /// Every job stopped for the editor to quit: each told to stop (its
    /// process terminated), all given 2 s to end, then any process still
    /// there killed outright, so no claude and no build goes on working for
    /// no one (the user, 2026-11-03: the runs went on after a restart).
    /// Synchronous, on the way out of the app.
    func quit() {
        for job in active { job.stop() }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, jobs.contains(where: { $0.process?.isRunning == true }) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        for job in jobs {
            if let p = job.process, p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
    }

    /// Starts the queued jobs their rules allow. A job started here reports
    /// its state at once, which asks for a pump again: the one going keeps
    /// count.
    private var pumping = false
    func pump() {
        guard !pumping else { return }
        pumping = true
        defer { pumping = false }
        for job in jobs where job.state == .queued {
            if job.canStart(alongside: running) { job.start() }
        }
    }
}
