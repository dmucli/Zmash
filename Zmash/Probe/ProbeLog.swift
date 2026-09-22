import Foundation
import Observation
import ZmashKit

struct LogEntry: Identifiable, Sendable {
    enum Direction: String, Sendable {
        case rx = "←"
        case tx = "→"
        case event = "·"
    }

    let id = UUID()
    let date: Date
    let device: String
    let direction: Direction
    let characteristic: String?
    let bytes: [UInt8]
    let decoded: String?

    var line: String {
        var parts = [Self.timeFormat.string(from: date), device, direction.rawValue]
        if let characteristic { parts.append(GATT.name(of: characteristic) ?? characteristic) }
        if !bytes.isEmpty { parts.append(bytes.hex) }
        if let decoded { parts.append("| \(decoded)") }
        return parts.joined(separator: " ")
    }

    static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

@MainActor @Observable
final class ProbeLog {
    private(set) var entries: [LogEntry] = []
    var paused = false
    /// Hide the high-rate data frames (bike data, keep-alives) from the list; they are still exported.
    var hideStreaming = true

    private var all: [LogEntry] = []
    private let capacity = 20_000

    func add(_ entry: LogEntry, streaming: Bool = false) {
        all.append(entry)
        if all.count > capacity { all.removeFirst(all.count - capacity) }
        guard !paused, !(streaming && hideStreaming) else { return }
        entries.append(entry)
        if entries.count > 1_000 { entries.removeFirst(entries.count - 1_000) }
    }

    func clear() {
        all.removeAll()
        entries.removeAll()
    }

    var exportText: String { all.map(\.line).joined(separator: "\n") }
}
