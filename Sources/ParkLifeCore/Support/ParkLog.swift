import Foundation

/// Structured logging categories. There are no bare `print` calls anywhere in ParkLifeCore.
public enum LogCategory: String, CaseIterable, Codable {
    case sim = "SIM"
    case path = "PATH"
    case economy = "ECONOMY"
    case guest = "GUEST"
    case staff = "STAFF"
    case save = "SAVE"
    case render = "RENDER"
    case cloud = "CLOUD"
    case build = "BUILD"
    case content = "CONTENT"
}

public enum LogLevel: Int, Comparable, Codable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

/// Destination for log records. The app binds this to `os.Logger`; tests bind it to a collector;
/// by default nothing is emitted, so the core never spams a host application's console.
public protocol LogSink: AnyObject {
    func write(level: LogLevel, category: LogCategory, message: String)
}

/// Simple sink that keeps records in memory — used by tests and the in-game debug console.
public final class MemoryLogSink: LogSink {

    public struct Record {
        public let level: LogLevel
        public let category: LogCategory
        public let message: String
    }

    private let lock = NSLock()
    private var storage: [Record] = []
    private let limit: Int

    public init(limit: Int = 2_000) {
        self.limit = limit
    }

    public func write(level: LogLevel, category: LogCategory, message: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(Record(level: level, category: category, message: message))
        if storage.count > limit {
            storage.removeFirst(storage.count - limit)
        }
    }

    public var records: [Record] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}

/// Global logging façade.
public final class ParkLog: @unchecked Sendable {

    public static let shared = ParkLog()

    private let lock = NSLock()
    private var sinks: [LogSink] = []
    private var minimumLevel: LogLevel = .info
    private var enabledCategories: Set<LogCategory> = Set(LogCategory.allCases)

    private init() {}

    public func addSink(_ sink: LogSink) {
        lock.lock()
        defer { lock.unlock() }
        sinks.append(sink)
    }

    public func removeAllSinks() {
        lock.lock()
        defer { lock.unlock() }
        sinks.removeAll()
    }

    public func setMinimumLevel(_ level: LogLevel) {
        lock.lock()
        defer { lock.unlock() }
        minimumLevel = level
    }

    public func setEnabledCategories(_ categories: Set<LogCategory>) {
        lock.lock()
        defer { lock.unlock() }
        enabledCategories = categories
    }

    /// `message` is an autoclosure so that building an expensive string costs nothing when the
    /// level or category is disabled — this matters inside the tick loop.
    public func log(_ level: LogLevel, _ category: LogCategory, _ message: @autoclosure () -> String) {
        lock.lock()
        let shouldEmit = level >= minimumLevel && enabledCategories.contains(category) && !sinks.isEmpty
        let targets = shouldEmit ? sinks : []
        lock.unlock()
        guard shouldEmit else { return }
        let text = message()
        for sink in targets {
            sink.write(level: level, category: category, message: text)
        }
    }

    public func debug(_ category: LogCategory, _ message: @autoclosure () -> String) {
        log(.debug, category, message())
    }

    public func info(_ category: LogCategory, _ message: @autoclosure () -> String) {
        log(.info, category, message())
    }

    public func warning(_ category: LogCategory, _ message: @autoclosure () -> String) {
        log(.warning, category, message())
    }

    public func error(_ category: LogCategory, _ message: @autoclosure () -> String) {
        log(.error, category, message())
    }
}
