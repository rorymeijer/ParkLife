import Foundation

public enum NotificationPriority: Int, CaseIterable, Codable, Comparable {
    case info = 0
    case warning = 1
    case critical = 2

    public static func < (lhs: NotificationPriority, rhs: NotificationPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var localizationKey: String {
        switch self {
        case .info: return "priority.info"
        case .warning: return "priority.warning"
        case .critical: return "priority.critical"
        }
    }
}

public struct ParkNotification: StoredEntity, Codable {

    public typealias Identifier = NotificationID

    public let id: NotificationID
    public var priority: NotificationPriority
    public var text: LocalizedText
    public var tick: Tick
    /// How many identical events have been folded into this one.
    public var occurrences: Int
    public var subject: UInt32?
    public var isRead: Bool
    /// Key used for aggregation and cooldown.
    public var groupingKey: String

    public init(
        id: NotificationID,
        priority: NotificationPriority,
        text: LocalizedText,
        tick: Tick,
        subject: UInt32?,
        groupingKey: String
    ) {
        self.id = id
        self.priority = priority
        self.text = text
        self.tick = tick
        self.occurrences = 1
        self.subject = subject
        self.isRead = false
        self.groupingKey = groupingKey
    }
}

/// Prioritised, aggregated, rate-limited alerts.
///
/// Spam control is the whole point: without it "cottage needs cleaning" would fire hundreds of
/// times an hour (brief §38).
public struct NotificationCentre: Codable {

    public private(set) var items: [ParkNotification]
    private var lastPostedTick: [String: Tick]
    public var limit: Int = 60

    /// How long a grouping key stays suppressed after firing, in simulated minutes.
    public static let defaultCooldownMinutes = 120

    public init() {
        self.items = []
        self.lastPostedTick = [:]
    }

    /// Posts an alert unless an identical one is still in cooldown; in that case the existing
    /// entry's occurrence count is bumped instead of adding a new row.
    @discardableResult
    public mutating func post(
        priority: NotificationPriority,
        text: LocalizedText,
        groupingKey: String,
        tick: Tick,
        subject: UInt32? = nil,
        cooldownMinutes: Int = NotificationCentre.defaultCooldownMinutes,
        allocator: inout IDAllocator
    ) -> Bool {
        // Aggregate onto the existing row for this key whenever one is still in the tray, whatever
        // the cooldown says. A condition that persists for six weeks — "you are short of staff" —
        // is one situation the player should see once with a count, not forty-five separate rows.
        // The cooldown governs only whether it is raised as *unread* again.
        if let index = items.lastIndex(where: { $0.groupingKey == groupingKey }) {
            items[index].occurrences += 1
            items[index].tick = tick
            let last = lastPostedTick[groupingKey] ?? tick
            if tick - last >= cooldownMinutes {
                items[index].isRead = false
                lastPostedTick[groupingKey] = tick
            }
            return false
        }
        if let last = lastPostedTick[groupingKey], tick - last < cooldownMinutes {
            return false
        }
        lastPostedTick[groupingKey] = tick
        let notification = ParkNotification(
            id: allocator.next(NotificationID.self),
            priority: priority,
            text: text,
            tick: tick,
            subject: subject,
            groupingKey: groupingKey
        )
        items.append(notification)
        if items.count > limit {
            items.removeFirst(items.count - limit)
        }
        return true
    }

    public mutating func markAllRead() {
        for index in items.indices {
            items[index].isRead = true
        }
    }

    public mutating func markRead(_ id: NotificationID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].isRead = true
        }
    }

    public mutating func dismiss(_ id: NotificationID) {
        items.removeAll(where: { $0.id == id })
    }

    public mutating func clear() {
        items.removeAll()
    }

    public var unreadCount: Int {
        items.reduce(0) { $0 + ($1.isRead ? 0 : 1) }
    }

    /// Newest first, most severe first.
    public var sortedForDisplay: [ParkNotification] {
        items.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.tick > rhs.tick
        }
    }
}
