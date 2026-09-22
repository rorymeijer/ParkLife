import Foundation

public enum ReservationStatus: String, CaseIterable, Codable {
    case enquiry
    case booked
    case paid
    case cancelled
    case arriving
    case checkedIn
    case checkedOut
    case noShow

    public var localizationKey: String { "reservationStatus.\(rawValue)" }

    /// Does this status occupy the unit for its date range?
    public var holdsUnit: Bool {
        switch self {
        case .booked, .paid, .arriving, .checkedIn:
            return true
        case .enquiry, .cancelled, .checkedOut, .noShow:
            return false
        }
    }

    public var isActive: Bool {
        switch self {
        case .cancelled, .checkedOut, .noShow:
            return false
        default:
            return true
        }
    }
}

public struct Reservation: StoredEntity, Codable {

    public typealias Identifier = ReservationID

    public let id: ReservationID
    public var groupID: GroupID
    /// The specific unit held for this booking. `nil` only while still an enquiry.
    public var unitBuildingID: BuildingID?
    /// Accommodation definition requested, used to match an enquiry to stock.
    public var requestedDefinitionID: String
    public var arrival: GameDate
    public var departure: GameDate
    public var adults: Int
    public var children: Int
    public var packageID: String
    /// Total accommodation price for the whole stay, after discount.
    public var price: Money
    public var discount: Money
    public var extras: Money
    public var status: ReservationStatus
    public var bookedAtTick: Tick
    public var paidAtTick: Tick?

    public init(
        id: ReservationID,
        groupID: GroupID,
        unitBuildingID: BuildingID?,
        requestedDefinitionID: String,
        arrival: GameDate,
        departure: GameDate,
        adults: Int,
        children: Int,
        packageID: String,
        price: Money,
        discount: Money,
        extras: Money,
        status: ReservationStatus,
        bookedAtTick: Tick
    ) {
        self.id = id
        self.groupID = groupID
        self.unitBuildingID = unitBuildingID
        self.requestedDefinitionID = requestedDefinitionID
        self.arrival = arrival
        self.departure = departure
        self.adults = adults
        self.children = children
        self.packageID = packageID
        self.price = price
        self.discount = discount
        self.extras = extras
        self.status = status
        self.bookedAtTick = bookedAtTick
        self.paidAtTick = nil
    }

    public var nights: Int { arrival.nights(until: departure) }
    public var partySize: Int { adults + children }
    public var totalPrice: Money { price + extras }

    /// Does this booking occupy its unit on the night starting on `dayIndex`?
    public func occupiesNight(dayIndex: Int) -> Bool {
        dayIndex >= arrival.dayIndex && dayIndex < departure.dayIndex
    }

    /// Do two stays overlap? A same-day changeover is allowed: one party leaves in the morning,
    /// the next arrives in the afternoon.
    public func overlaps(arrival otherArrival: GameDate, departure otherDeparture: GameDate) -> Bool {
        arrival.dayIndex < otherDeparture.dayIndex && otherArrival.dayIndex < departure.dayIndex
    }
}
