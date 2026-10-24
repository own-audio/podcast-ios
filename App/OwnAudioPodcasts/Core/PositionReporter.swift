import Foundation
import PodcastLibrary
import SpokenEngine

/// How often a position goes past memory. The player reports every 10 s of listening; the
/// mini player and the lists follow that in memory, and `last-played.json` gets it as one small
/// write, so a kill loses nothing. The show's store (the phone's `state.json`, a server's
/// queue and request) gets it every `interval` while playing, and at once on pause, seek, stop,
/// another episode, the end of the episode and going to the background. Between those the
/// cellular radio can sleep.
struct PositionThrottle {
    static let interval: TimeInterval = 60

    private(set) var lastId: String?
    private(set) var lastAt: Date?

    /// Whether this report is stored and sent now; when it is, the clock starts again. A
    /// chapter change counts as listening on: some shows have a chapter every minute.
    mutating func isDue(_ reason: SpokenEngine.TickReason, id: String, played: Bool, now: Date) -> Bool {
        let throttled = reason == .periodic || reason == .chapter
        let due = played || !throttled || id != lastId || lastAt.map { now.timeIntervalSince($0) >= Self.interval } ?? true
        if due {
            lastId = id
            lastAt = now
        }
        return due
    }
}

/// Holds the position that is not stored yet, and stores it when the throttle says so or when
/// asked to (`flush`, going to the background).
@MainActor
final class PositionReporter {
    private var throttle = PositionThrottle()
    /// The newest position the throttle held back, by episode id.
    private(set) var unflushed: (id: String, value: ListeningProgress)?
    private let persist: (String, ListeningProgress) -> Void

    init(persist: @escaping (String, ListeningProgress) -> Void) {
        self.persist = persist
    }

    func report(_ value: ListeningProgress, for id: String, reason: SpokenEngine.TickReason) {
        if throttle.isDue(reason, id: id, played: value.played, now: value.updatedAt) {
            // Another episode's held-back position first, so it is not lost with the switch.
            if let held = unflushed, held.id != id { persist(held.id, held.value) }
            unflushed = nil
            persist(id, value)
        } else {
            unflushed = (id, value)
        }
    }

    /// Stores what the throttle held back, if anything.
    func flush() {
        guard let held = unflushed else { return }
        unflushed = nil
        persist(held.id, held.value)
    }
}
