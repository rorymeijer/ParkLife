import SwiftUI
import ParkLifeCore

// MARK: - Guests

struct GuestsPanel: View {

    @EnvironmentObject private var session: GameSession
    @State private var sortByHappiness = false

    var body: some View {
        List {
            if let world = session.world {
                Section(NSLocalizedString("guests.summary", comment: "")) {
                    LabeledContent(
                        NSLocalizedString("guests.onSite", comment: ""),
                        value: "\(world.guestsOnSite)"
                    )
                    LabeledContent(
                        NSLocalizedString("guests.averageHappiness", comment: ""),
                        value: "\(Int((world.averageGuestHappiness * 100).rounded()))%"
                    )
                    LabeledContent(
                        NSLocalizedString("guests.parties", comment: ""),
                        value: "\(world.activeGroupIDs.count)"
                    )
                    Toggle(NSLocalizedString("guests.sortByHappiness", comment: ""), isOn: $sortByHappiness)
                }

                Section(NSLocalizedString("guests.thoughts", comment: "")) {
                    let thoughts = recentThoughts(world)
                    if thoughts.isEmpty {
                        Text(NSLocalizedString("guests.noThoughts", comment: ""))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(thoughts, id: \.0) { item in
                            HStack {
                                Image(systemName: item.1 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                                    .foregroundStyle(item.1 ? .green : .orange)
                                Text(NSLocalizedString(item.0, comment: ""))
                                    .font(.subheadline)
                                Spacer()
                                Text("\(item.2)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section(NSLocalizedString("guests.inPark", comment: "")) {
                    ForEach(listedGuests(world), id: \.id.raw) { guest in
                        Button {
                            session.selection = .guest(guest.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(guest.firstName), \(guest.age)")
                                        .font(.subheadline.weight(.medium))
                                    Text(NSLocalizedString(guest.activity.localizationKey, comment: ""))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(Int((guest.happiness * 100).rounded()))%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(happinessColour(guest.happiness))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section(NSLocalizedString("guests.recentReviews", comment: "")) {
                    ForEach(world.reviews.suffix(12).reversed(), id: \.id.raw) { review in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(stars(review.overallStars))
                                    .foregroundStyle(.yellow)
                                Text(String(format: "%.1f", review.overallStars))
                                    .font(.caption.monospacedDigit())
                                Spacer()
                                Text(
                                    String(
                                        format: NSLocalizedString("guests.reviewMeta", comment: ""),
                                        review.nights, review.partySize
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            ForEach(review.bodyKeys, id: \.self) { key in
                                Text(NSLocalizedString(key, comment: ""))
                                    .font(.caption)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func listedGuests(_ world: World) -> [Guest] {
        let present = world.guests.items.filter { $0.activity != .departed && $0.activity != .offPark }
        let sorted = sortByHappiness
            ? present.sorted { $0.happiness < $1.happiness }
            : present.sorted { $0.id.raw < $1.id.raw }
        return Array(sorted.prefix(60))
    }

    /// Aggregated so the list shows what guests keep saying, not one row per guest.
    private func recentThoughts(_ world: World) -> [(String, Bool, Int)] {
        var counts: [String: (Bool, Int)] = [:]
        for guest in world.guests.items {
            for thought in guest.thoughts {
                let key = thought.kind.localizationKey
                let existing = counts[key] ?? (thought.kind.isPositive, 0)
                counts[key] = (existing.0, existing.1 + 1)
            }
        }
        return counts
            .map { ($0.key, $0.value.0, $0.value.1) }
            .sorted { lhs, rhs in
                if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
                return lhs.0 < rhs.0
            }
            .prefix(8)
            .map { $0 }
    }

    private func stars(_ value: Double) -> String {
        let filled = Int(value.rounded())
        return String(repeating: "★", count: max(0, min(5, filled)))
            + String(repeating: "☆", count: max(0, 5 - min(5, filled)))
    }

    private func happinessColour(_ value: Double) -> Color {
        if value > 0.66 { return .green }
        if value > 0.4 { return .orange }
        return .red
    }
}

// MARK: - Staff

struct StaffPanel: View {

    @EnvironmentObject private var session: GameSession

    var body: some View {
        List {
            if let world = session.world {
                Section(NSLocalizedString("staff.hire", comment: "")) {
                    ForEach(world.catalog.staffRoles.keys.sorted(), id: \.self) { roleID in
                        if let role = world.catalog.staffRoles[roleID] {
                            Button {
                                session.submit(.hireStaff(roleID: roleID))
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(NSLocalizedString(role.nameKey, comment: ""))
                                        Text(
                                            String(
                                                format: NSLocalizedString("staff.perMonth", comment: ""),
                                                role.monthlySalary.description
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section(NSLocalizedString("staff.workload", comment: "")) {
                    LabeledContent(
                        NSLocalizedString("staff.cleaningQueue", comment: ""),
                        value: "\(StaffSystem.pendingCleaningCount(in: world))"
                    )
                    LabeledContent(
                        NSLocalizedString("staff.serviceCoverage", comment: ""),
                        value: "\(Int((ReputationSystem.serviceScore(in: world) * 100).rounded()))%"
                    )
                    LabeledContent(
                        NSLocalizedString("staff.monthlyWages", comment: ""),
                        value: Money(cents: world.staff.items.reduce(0) { $0 + $1.monthlySalary.cents }).description
                    )
                }

                Section(NSLocalizedString("staff.team", comment: "")) {
                    ForEach(world.staff.items.sorted { $0.id.raw < $1.id.raw }, id: \.id.raw) { member in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.name).font(.subheadline.weight(.medium))
                                Text(NSLocalizedString("role.\(member.roleID)", comment: ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(shiftText(member))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(activityText(member))
                                    .font(.caption)
                                Text("\(Int((member.skill * 100).rounded()))%")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Button(role: .destructive) {
                                session.submit(.dismissStaff(member.id))
                            } label: {
                                Image(systemName: "person.badge.minus")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text(NSLocalizedString("staff.dismiss", comment: "")))
                        }
                    }
                }
            }
        }
    }

    private func shiftText(_ member: StaffMember) -> String {
        String(
            format: NSLocalizedString("staff.shift", comment: ""),
            member.shiftStartMinute / 60, member.shiftStartMinute % 60,
            member.shiftEndMinute / 60, member.shiftEndMinute % 60
        )
    }

    private func activityText(_ member: StaffMember) -> String {
        switch member.activity {
        case .idle: return NSLocalizedString("staffActivity.idle", comment: "")
        case .walkingTo: return NSLocalizedString("staffActivity.walking", comment: "")
        case .working: return NSLocalizedString("staffActivity.working", comment: "")
        case .onBreak: return NSLocalizedString("staffActivity.break", comment: "")
        case .offDuty: return NSLocalizedString("staffActivity.offDuty", comment: "")
        }
    }
}
