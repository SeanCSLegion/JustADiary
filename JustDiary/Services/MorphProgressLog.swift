import Foundation

#if DEBUG
nonisolated final class MorphProgressLog {
    static let shared = MorphProgressLog()

    private let lock = NSLock()
    private var entries: [(Double, String)] = []
    private let start = ProcessInfo.processInfo.systemUptime
    private var flushCounter = 0

    func append(_ progress: Double) {
        append(String(format: "%.5f", progress))
    }

    func append(_ value: String) {
        let isMarker = value.range(of: "^[-0-9.]+$", options: .regularExpression) == nil
        lock.lock()
        entries.append((ProcessInfo.processInfo.systemUptime - start, value))
        flushCounter += 1
        let shouldFlush = isMarker || flushCounter >= 25
        var lines: String?
        if shouldFlush {
            lines = entries.map { "\($0.0)\t\($0.1)" }.joined(separator: "\n")
            flushCounter = 0
        }
        lock.unlock()
        if let lines {
            try? lines.write(toFile: NSHomeDirectory() + "/Documents/morph.log", atomically: true, encoding: .utf8)
        }
    }
}
#endif
