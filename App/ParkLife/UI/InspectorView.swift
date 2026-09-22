import SwiftUI
import ParkLifeCore

/// Details for whatever the player last tapped.
struct InspectorView: View {

    @EnvironmentObject private var session: GameSession

    var body: some View {
        switch session.selection {
        case .none:
            EmptyView()
        case .building(let id):
            card { buildingDetails(id) }
        case .guest(let id):
            card { guestDetails(id) }
        case .staff(let id):
            card { staffDetails(id) }
        case .tile(let point):
            card { tileDetails(point) }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button {
                session.selection = .none
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .accessibilityLabel(Text(NSLocalizedString("common.close", comment: "")))
        }
    }

    @ViewBuilder
    private func buildingDetails(_ id: BuildingID) -> some View {
        if let world = session.world,
           let instance = world.buildings[id],
           let definition = world.definition(of: instance) {

            Text(NSLocalizedString(definition.nameKey, comment: ""))
                .font(.headline)

            meter(NSLocalizedString("inspector.condition", comment: ""), value: instance.condition)

            if let accommodation = instance.accommodation, let spec = definition.accommodation {
                Text(NSLocalizedString(accommodation.state.localizationKey, comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(stateColour(accommodation.state))
                meter(NSLocalizedString("inspector.cleanliness", comment: ""), value: accommodation.cleanliness)
                LabeledContent(
                    NSLocalizedString("inspector.sleeps", comment: ""),
                    value: "\(spec.capacity)"
                )
                LabeledContent(
                    NSLocalizedString("inspector.nightlyRate", comment: ""),
                    value: world.pricing.nightlyPrice(definition: definition, instance: instance, date: world.date).description
                )
                LabeledContent(
                    NSLocalizedString("inspector.nightsSold", comment: ""),
                    value: "\(accommodation.totalNightsSold)"
                )
            }

            if let facility = instance.facility, let spec = definition.facility {
                LabeledContent(
                    NSLocalizedString("inspector.visitorsToday", comment: ""),
                    value: "\(facility.visitsToday)"
                )
                LabeledContent(
                    NSLocalizedString("inspector.queue", comment: ""),
                    value: "\(facility.queue.count) / \(spec.queueCapacity)"
                )
                LabeledContent(
                    NSLocalizedString("inspector.revenueToday", comment: ""),
                    value: facility.revenueToday.description
                )
                if spec.basePrice.cents > 0 {
                    LabeledContent(
                        NSLocalizedString("inspector.price", comment: ""),
                        value: world.pricing.facilityPrice(definition: definition, instance: instance).description
                    )
                }
                Toggle(
                    NSLocalizedString("inspector.open", comment: ""),
                    isOn: Binding(
                        get: { facility.isOpen },
                        set: { session.submit(.openFacility(id, $0)) }
                    )
                )
                .font(.subheadline)
            }

            Button(role: .destructive) {
                session.submit(.build(.demolishBuilding(id)))
                session.selection = .none
            } label: {
                Label(NSLocalizedString("inspector.demolish", comment: ""), systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func guestDetails(_ id: GuestID) -> some View {
        if let world = session.world, let guest = world.guests[id] {
            Text("\(guest.firstName), \(guest.age)").font(.headline)
            Text(NSLocalizedString(guest.activity.localizationKey, comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            meter(NSLocalizedString("inspector.happiness", comment: ""), value: guest.happiness)
            meter(NSLocalizedString("need.hunger", comment: ""), value: guest.needs.hunger, inverted: true)
            meter(NSLocalizedString("need.thirst", comment: ""), value: guest.needs.thirst, inverted: true)
            meter(NSLocalizedString("need.tiredness", comment: ""), value: guest.needs.tiredness, inverted: true)
            meter(NSLocalizedString("need.boredom", comment: ""), value: guest.needs.boredom, inverted: true)
            if let thought = guest.thoughts.last {
                Label(
                    NSLocalizedString(thought.kind.localizationKey, comment: ""),
                    systemImage: thought.kind.isPositive ? "hand.thumbsup" : "hand.thumbsdown"
                )
                .font(.caption)
                .foregroundStyle(thought.kind.isPositive ? .green : .orange)
            }
        }
    }

    @ViewBuilder
    private func staffDetails(_ id: StaffID) -> some View {
        if let world = session.world, let member = world.staff[id] {
            Text(member.name).font(.headline)
            Text(NSLocalizedString("role.\(member.roleID)", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            meter(NSLocalizedString("inspector.skill", comment: ""), value: member.skill)
            meter(NSLocalizedString("inspector.morale", comment: ""), value: member.happiness)
            LabeledContent(
                NSLocalizedString("inspector.salary", comment: ""),
                value: member.monthlySalary.description
            )
        }
    }

    @ViewBuilder
    private func tileDetails(_ point: GridPoint) -> some View {
        if let world = session.world {
            Text(NSLocalizedString("inspector.tile", comment: "") + " \(point.x), \(point.y)")
                .font(.headline)
            LabeledContent(
                NSLocalizedString("inspector.terrain", comment: ""),
                value: NSLocalizedString(world.tiles.terrain(at: point).localizationKey, comment: "")
            )
            LabeledContent(
                NSLocalizedString("inspector.surface", comment: ""),
                value: NSLocalizedString(world.tiles.surface(at: point).localizationKey, comment: "")
            )
            meter(NSLocalizedString("inspector.scenery", comment: ""), value: (world.tiles.scenery(at: point) + 1) / 2)
        }
    }

    private func stateColour(_ state: UnitState) -> Color {
        switch state {
        case .ready: return .green
        case .occupied: return .blue
        case .dirty: return .orange
        case .cleaning: return .yellow
        case .maintenance: return .red
        }
    }

    /// A labelled bar. Status is never colour alone: the number is always shown too (brief §48).
    private func meter(_ label: String, value: Double, inverted: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 88, alignment: .leading)
            ProgressView(value: min(max(value, 0), 1))
                .tint(tint(for: value, inverted: inverted))
            Text("\(Int((value * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .frame(width: 42, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label): \(Int((value * 100).rounded())) percent"))
    }

    private func tint(for value: Double, inverted: Bool) -> Color {
        let effective = inverted ? 1 - value : value
        if effective > 0.66 { return .green }
        if effective > 0.33 { return .yellow }
        return .red
    }
}
