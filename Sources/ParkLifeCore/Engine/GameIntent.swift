import Foundation

/// Everything the player can ask the simulation to do.
///
/// The UI never mutates the world directly; it submits an intent, which is validated and applied
/// inside the engine. That is what makes undo, replay and a testable UI possible at all.
public enum GameIntent {
    case setSpeed(GameSpeed)
    case build(BuildAction)
    case undoBuild
    case redoBuild
    case setAccommodationPrice(definitionID: String, price: Money)
    case setUnitPrice(BuildingID, Money?)
    case setFacilityPrice(definitionID: String, price: Money)
    case setAccommodationMultiplier(Double)
    case setSeasonalPricing(Bool)
    case setLastMinuteDiscount(Double)
    case hireStaff(roleID: String)
    case dismissStaff(StaffID)
    case setStaffShift(StaffID, start: Int, end: Int)
    case openFacility(BuildingID, Bool)
    case startResearch(String)
    case takeLoan(amount: Money, termDays: Int)
    case markNotificationsRead
    case dismissNotification(NotificationID)
}

/// Why an intent was refused, so the UI can say something useful.
public enum IntentRejection: Error, Equatable {
    case buildFailed(BuildFailure)
    case nothingToUndo
    case nothingToRedo
    case unknownEntity
    case notAllowed
}
