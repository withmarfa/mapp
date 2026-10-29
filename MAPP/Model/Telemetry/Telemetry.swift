import Foundation
import os

/// The app's one place for logs and signposts. A `Logger` and an `OSSignposter` share each category, so
/// `log stream` and Instruments (os_signpost, Points of Interest) show one story. Nothing here ever records a
/// person's text, titles, property values or keys: kinds, durations and counts only, and ids only as counts.
nonisolated enum Telemetry {
    nonisolated enum Category: String, CaseIterable, Sendable {
        case launch, engine, sync, library, navigation, editor, quit
    }

    /// An event the engine takes longer than this logs a notice; longer than `stalled`, an error.
    static let slow = Duration.milliseconds(250)
    static let stalled = Duration.seconds(2)

    static let subsystem = Bundle.main.bundleIdentifier ?? "com.withmarfa.mapp"

    private static let loggers = Dictionary(uniqueKeysWithValues: Category.allCases.map {
        ($0, Logger(subsystem: subsystem, category: $0.rawValue))
    })
    private static let signposters = Dictionary(uniqueKeysWithValues: Category.allCases.map {
        ($0, OSSignposter(subsystem: subsystem, category: $0.rawValue))
    })

    static func logger(_ category: Category) -> Logger {
        loggers[category] ?? Logger(subsystem: subsystem, category: category.rawValue)
    }

    static func signposter(_ category: Category) -> OSSignposter {
        signposters[category] ?? OSSignposter(subsystem: subsystem, category: category.rawValue)
    }

    /// A signpost interval, ended with `end`. Counts go in the signpost's message as `name=count`.
    nonisolated struct Interval: Sendable {
        fileprivate let signposter: OSSignposter
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState
        fileprivate let start: ContinuousClock.Instant

        /// How long the interval has run.
        var elapsed: Duration { ContinuousClock.now - start }

        @discardableResult
        func end(_ counts: (String, Int)...) -> Duration {
            let elapsed = elapsed
            if counts.isEmpty {
                signposter.endInterval(name, state)
            } else if signposter.isEnabled {
                signposter.endInterval(name, state, "\(Telemetry.summary(counts), privacy: .public)")
            } else {
                signposter.endInterval(name, state)
            }
            return elapsed
        }
    }

    static func begin(_ category: Category, _ name: StaticString, _ counts: (String, Int)...) -> Interval {
        let signposter = signposter(category)
        let id = signposter.makeSignpostID()
        let state: OSSignpostIntervalState
        if counts.isEmpty || !signposter.isEnabled {
            state = signposter.beginInterval(name, id: id)
        } else {
            state = signposter.beginInterval(name, id: id, "\(summary(counts), privacy: .public)")
        }
        return Interval(signposter: signposter, name: name, state: state, start: .now)
    }

    /// A point in time with no length, such as a window opening.
    static func event(_ category: Category, _ name: StaticString, _ counts: (String, Int)...) {
        let signposter = signposter(category)
        guard signposter.isEnabled else { return }
        if counts.isEmpty {
            signposter.emitEvent(name)
        } else {
            signposter.emitEvent(name, "\(summary(counts), privacy: .public)")
        }
    }

    @discardableResult
    static func measure<Result>(_ category: Category, _ name: StaticString, _ work: () throws -> Result) rethrows -> Result {
        let interval = begin(category, name)
        defer { interval.end() }
        return try work()
    }

    @discardableResult
    static func measure<Result>(
        _ category: Category, _ name: StaticString, isolation: isolated (any Actor)? = #isolation,
        _ work: () async throws -> Result
    ) async rethrows -> Result {
        let interval = begin(category, name)
        defer { interval.end() }
        return try await work()
    }

    fileprivate static func summary(_ counts: [(String, Int)]) -> String {
        counts.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
    }
}

extension Duration {
    /// Whole milliseconds, for logs.
    nonisolated var inMilliseconds: Int {
        Int(components.seconds) * 1000 + Int(components.attoseconds / 1_000_000_000_000_000)
    }
}
