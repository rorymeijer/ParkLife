import Foundation

/// Records how a group felt about something that actually happened.
///
/// Reviews are assembled from these moments, so every star in a review traces back to a real
/// event with a reason attached (brief §26).
public enum SatisfactionService {

    public static func record(
        groupID: GroupID,
        category: ReviewCategory,
        delta: Double,
        reasonKey: String,
        world: inout World,
        tick: Tick
    ) {
        let bounded = clamp(delta, -1.2, 1.2)
        world.groups.modify(groupID) { group in
            group.record(
                SatisfactionMoment(category: category, delta: bounded, reasonKey: reasonKey, tick: tick)
            )
        }
    }

    /// Records a moment and the matching guest thought in one step.
    public static func recordThought(
        guestID: GuestID,
        kind: ThoughtKind,
        magnitude: Double,
        delta: Double,
        world: inout World,
        tick: Tick,
        subject: UInt32? = nil
    ) {
        guard let guest = world.guests[guestID] else { return }
        world.guests.modify(guestID) { stored in
            stored.remember(GuestThought(kind: kind, magnitude: magnitude, tick: tick, subject: subject))
        }
        record(
            groupID: guest.groupID,
            category: kind.reviewCategory,
            delta: delta,
            reasonKey: kind.localizationKey,
            world: &world,
            tick: tick
        )
    }
}
