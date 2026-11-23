import Marfa
import Synchronization
@testable import MarfaMac

/// A report sink that keeps what it is given, so a test reaches no network.
final class RecordingSink: ReportSink {
    struct Error: Equatable {
        var type: String
        var sentence: String
        var operation: String
    }

    private let recorded = Mutex<(errors: [Error], logs: [String], attributes: [String: [String: ReportAttribute]])>(([], [], [:]))
    var errors: [Error] { recorded.withLock { $0.errors } }
    var logs: [String] { recorded.withLock { $0.logs } }
    /// The attributes of the last record of each name.
    var attributes: [String: [String: ReportAttribute]] { recorded.withLock { $0.attributes } }

    func report(_ error: MarfaError, during operation: StaticString) {
        recorded.withLock { $0.errors.append(Error(type: error.fixedText.type, sentence: error.fixedText.sentence, operation: "\(operation)")) }
    }

    func report(type: StaticString, sentence: StaticString, during operation: StaticString) {
        recorded.withLock { $0.errors.append(Error(type: "\(type)", sentence: "\(sentence)", operation: "\(operation)")) }
    }

    func log(_ name: StaticString, level: ReportLevel, attributes: KeyValuePairs<StaticString, ReportAttribute>) {
        var stored: [String: ReportAttribute] = [:]
        for (key, value) in attributes { stored["\(key)"] = value }
        recorded.withLock {
            let name = "\(name)"
            $0.logs.append(name)
            $0.attributes[name] = stored
        }
    }
}
