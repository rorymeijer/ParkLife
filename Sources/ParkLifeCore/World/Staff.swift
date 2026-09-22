import Foundation

public enum StaffTaskKind: String, CaseIterable, Codable {
    case cleanUnit
    case cleanFacility
    case emptyBin
    case repairBuilding
    case inspectBuilding
    case staffReception
    case staffFacility
    case landscaping

    public var localizationKey: String { "task.\(rawValue)" }
}

public enum StaffTaskState: String, Codable {
    case pending
    case assigned
    case inProgress
    case completed
    case cancelled
}

public struct StaffTask: StoredEntity, Codable {

    public typealias Identifier = TaskID

    public let id: TaskID
    public var kind: StaffTaskKind
    public var target: BuildingID
    public var createdTick: Tick
    public var assignedTo: StaffID?
    public var state: StaffTaskState
    /// Higher runs first.
    public var priority: Int
    public var durationMinutes: Int
    public var completesAtTick: Tick?

    public init(
        id: TaskID,
        kind: StaffTaskKind,
        target: BuildingID,
        createdTick: Tick,
        priority: Int,
        durationMinutes: Int
    ) {
        self.id = id
        self.kind = kind
        self.target = target
        self.createdTick = createdTick
        self.assignedTo = nil
        self.state = .pending
        self.priority = priority
        self.durationMinutes = durationMinutes
        self.completesAtTick = nil
    }
}

public enum StaffActivity: Codable, Hashable {
    case idle
    case walkingTo(BuildingID)
    case working(BuildingID)
    case onBreak
    case offDuty
}

public struct StaffMember: StoredEntity, Codable {

    public typealias Identifier = StaffID

    public let id: StaffID
    public var name: String
    public var roleID: String
    public var monthlySalary: Money
    /// `0...1`; higher skill works faster and to a better standard.
    public var skill: Double
    public var experience: Double
    public var happiness: Double
    public var energy: Double
    public var position: WorldPoint
    public var path: MovementPath?
    public var activity: StaffActivity
    public var currentTask: TaskID?
    /// Optional zone restriction; `nil` means the whole park.
    public var assignedZone: GridRect?
    public var shiftStartMinute: Int
    public var shiftEndMinute: Int
    public var hiredAtTick: Tick

    public init(
        id: StaffID,
        name: String,
        roleID: String,
        monthlySalary: Money,
        skill: Double,
        position: WorldPoint,
        hiredAtTick: Tick
    ) {
        self.id = id
        self.name = name
        self.roleID = roleID
        self.monthlySalary = monthlySalary
        self.skill = skill
        self.experience = 0
        self.happiness = 0.7
        self.energy = 1.0
        self.position = position
        self.path = nil
        self.activity = .idle
        self.currentTask = nil
        self.assignedZone = nil
        self.shiftStartMinute = 8 * 60
        self.shiftEndMinute = 17 * 60
        self.hiredAtTick = hiredAtTick
    }

    public func isOnShift(minuteOfDay: Int) -> Bool {
        if shiftEndMinute > shiftStartMinute {
            return minuteOfDay >= shiftStartMinute && minuteOfDay < shiftEndMinute
        }
        return minuteOfDay >= shiftStartMinute || minuteOfDay < shiftEndMinute
    }
}
