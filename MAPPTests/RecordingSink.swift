import Marfa
import Synchronization
@testable import MAPP

/// A report sink that keeps what it is given, so a test reaches no network.
final class RecordingSink: ReportSink {
    struct Error: Equatable {
        var type: String
        var sentence: String
        var operation: String
    }

    private let recorded = Mutex<(errors: [Error], logs: [String])>(([], []))
    var errors: [Error] { recorded.withLock { $0.errors } }
    var logs: [String] { recorded.withLock { $0.logs } }

    func report(_ error: MarfaError, during operation: StaticString) {
        recorded.withLock { $0.errors.append(Error(type: error.fixedText.type, sentence: error.fixedText.sentence, operation: "\(operation)")) }
    }

    func report(type: StaticString, sentence: StaticString, during operation: StaticString) {
        recorded.withLock { $0.errors.append(Error(type: "\(type)", sentence: "\(sentence)", operation: "\(operation)")) }
    }

    func log(_ name: StaticString, level: ReportLevel, attributes: KeyValuePairs<StaticString, ReportAttribute>) {
        recorded.withLock { $0.logs.append("\(name)") }
    }
}
