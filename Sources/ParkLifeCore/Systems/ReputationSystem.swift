import Foundation

/// Keeps the park's standing in step with measured conditions as well as reviews.
public enum ReputationSystem: SimulationSystem {

    public static let systemName = "Reputation"

    public static func update(world: inout World, context: inout TickContext) {
        guard context.isNewHour else { return }

        // Satisfaction of guests who are here right now.
        let happiness = world.averageGuestHappiness
        world.reputation.guestSatisfaction = movingAverage(
            current: world.reputation.guestSatisfaction, sample: happiness, weight: 0.05
        )

        // Cleanliness across cottages and facilities.
        var cleanlinessSum = 0.0
        var cleanlinessCount = 0
        for building in world.buildings.items {
            if let accommodation = building.accommodation {
                cleanlinessSum += accommodation.cleanliness
                cleanlinessCount += 1
            }
            if let facility = building.facility {
                cleanlinessSum += facility.cleanliness
                cleanlinessCount += 1
            }
        }
        if cleanlinessCount > 0 {
            world.reputation.cleanliness = movingAverage(
                current: world.reputation.cleanliness,
                sample: cleanlinessSum / Double(cleanlinessCount),
                weight: 0.04
            )
        }

        // Safety: supervised pools and buildings in good repair.
        world.reputation.safety = movingAverage(
            current: world.reputation.safety, sample: safetyScore(in: world), weight: 0.03
        )

        // Service: are the facilities that need staff actually staffed?
        world.reputation.service = movingAverage(
            current: world.reputation.service, sample: serviceScore(in: world), weight: 0.03
        )

        // Sustainability: green space and energy intensity per guest.
        world.reputation.sustainability = movingAverage(
            current: world.reputation.sustainability, sample: sustainabilityScore(in: world), weight: 0.02
        )
    }

    public static func safetyScore(in world: World) -> Double {
        var total = 0.0
        var count = 0
        for building in world.buildings.items {
            total += building.condition
            count += 1
        }
        let condition = count > 0 ? total / Double(count) : 1.0

        let pools = world.index.facilities(ofKind: .pool)
        var supervision = 1.0
        if !pools.isEmpty {
            let lifeguards = world.staff.items.filter { $0.roleID == "lifeguard" }.count
            let required = pools.count * 2
            supervision = required > 0 ? clamp01(Double(lifeguards) / Double(required)) : 1.0
        }
        return clamp01(0.45 * condition + 0.55 * supervision)
    }

    public static func serviceScore(in world: World) -> Double {
        var required = 0
        for id in world.index.facilityIDs {
            guard let facility = world.definition(ofBuilding: id)?.facility else { continue }
            required += facility.staffRequired
        }
        guard required > 0 else { return 0.7 }
        let available = world.staff.items.count
        return clamp01(Double(available) / Double(required))
    }

    public static func sustainabilityScore(in world: World) -> Double {
        let size = world.tiles.size
        var green = 0
        for index in 0..<size.tileCount {
            let point = size.point(at: index)
            let terrain = world.tiles.terrain(at: point)
            if terrain == .forest || terrain == .water || (terrain == .grass && world.tiles.building(at: point) == nil) {
                green += 1
            }
        }
        let greenShare = Double(green) / Double(max(1, size.tileCount))
        let energyPerGuest = world.statistics.dailySeries(.energyKWh)?.latest.map { value -> Double in
            let guests = Double(max(1, world.guestsOnSite))
            return value / guests
        } ?? 20.0
        let energyScore = 1.0 - clamp01((energyPerGuest - 8.0) / 40.0)
        return clamp01(0.55 * greenShare + 0.45 * energyScore)
    }
}
