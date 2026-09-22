import Foundation

/// Derived lookup tables over the world.
///
/// Rebuilt whenever buildings change, so the tick loop never scans every building to answer
/// "where is the reception?" or "which units are bookable?".
public struct WorldIndex {

    public private(set) var accommodationIDs: [BuildingID]
    public private(set) var facilityIDs: [BuildingID]
    public private(set) var facilityIDsByKind: [String: [BuildingID]]
    public private(set) var receptionID: BuildingID?
    public private(set) var entranceID: BuildingID?
    /// Reservations touching each unit, so availability is an interval check, not a scan.
    public private(set) var reservationsByUnit: [UInt32: [ReservationID]]
    /// Guests belonging to each group.
    public private(set) var guestsByGroup: [UInt32: [GuestID]]

    public init() {
        self.accommodationIDs = []
        self.facilityIDs = []
        self.facilityIDsByKind = [:]
        self.receptionID = nil
        self.entranceID = nil
        self.reservationsByUnit = [:]
        self.guestsByGroup = [:]
    }

    public mutating func rebuild(buildings: EntityStore<BuildingInstance>, catalog: ContentCatalog) {
        accommodationIDs = []
        facilityIDs = []
        facilityIDsByKind = [:]
        receptionID = nil
        entranceID = nil

        // Sorted for determinism: storage order changes as buildings are added and removed.
        for id in buildings.sortedIDs {
            guard let instance = buildings[id],
                  let definition = catalog.buildings[instance.definitionID] else { continue }
            if definition.isAccommodation {
                accommodationIDs.append(id)
            }
            if let facility = definition.facility {
                facilityIDs.append(id)
                facilityIDsByKind[facility.kind.rawValue, default: []].append(id)
                if facility.kind == .reception, receptionID == nil {
                    receptionID = id
                }
                if facility.kind == .entrance, entranceID == nil {
                    entranceID = id
                }
            }
        }
    }

    public mutating func rebuildReservations(_ reservations: EntityStore<Reservation>) {
        reservationsByUnit = [:]
        for id in reservations.sortedIDs {
            guard let reservation = reservations[id], let unit = reservation.unitBuildingID else { continue }
            reservationsByUnit[unit.raw, default: []].append(id)
        }
    }

    public mutating func rebuildGuests(_ guests: EntityStore<Guest>) {
        guestsByGroup = [:]
        for id in guests.sortedIDs {
            guard let guest = guests[id] else { continue }
            guestsByGroup[guest.groupID.raw, default: []].append(id)
        }
    }

    public mutating func noteReservation(_ reservation: Reservation) {
        guard let unit = reservation.unitBuildingID else { return }
        reservationsByUnit[unit.raw, default: []].append(reservation.id)
    }

    public mutating func noteGuest(_ guest: Guest) {
        guestsByGroup[guest.groupID.raw, default: []].append(guest.id)
    }

    public func facilities(ofKind kind: FacilityKind) -> [BuildingID] {
        facilityIDsByKind[kind.rawValue] ?? []
    }

    public func reservations(forUnit unit: BuildingID) -> [ReservationID] {
        reservationsByUnit[unit.raw] ?? []
    }

    public func guests(inGroup group: GroupID) -> [GuestID] {
        guestsByGroup[group.raw] ?? []
    }
}
