import SwiftUI
import ParkLifeCore

// MARK: - Park

struct ParkPanel: View {

    @EnvironmentObject private var session: GameSession

    var body: some View {
        List {
            if let world = session.world {
                Section(NSLocalizedString("park.overview", comment: "")) {
                    LabeledContent(NSLocalizedString("park.name", comment: ""), value: world.parkName)
                    LabeledContent(NSLocalizedString("park.company", comment: ""), value: world.companyName)
                    LabeledContent(
                        NSLocalizedString("park.units", comment: ""),
                        value: "\(world.index.accommodationIDs.count)"
                    )
                    LabeledContent(
                        NSLocalizedString("park.beds", comment: ""),
                        value: "\(world.totalUnitCapacity)"
                    )
                    LabeledContent(
                        NSLocalizedString("park.facilities", comment: ""),
                        value: "\(world.index.facilityIDs.count)"
                    )
                }

                Section(NSLocalizedString("park.ratings", comment: "")) {
                    rating(NSLocalizedString("park.overall", comment: ""), world.reputation.overall)
                    rating(NSLocalizedString("park.cleanliness", comment: ""), world.reputation.cleanliness)
                    rating(NSLocalizedString("park.service", comment: ""), world.reputation.service)
                    rating(NSLocalizedString("park.safety", comment: ""), world.reputation.safety)
                    rating(NSLocalizedString("park.sustainability", comment: ""), world.reputation.sustainability)
                    rating(NSLocalizedString("park.value", comment: ""), world.reputation.valueForMoney)
                }

                Section(NSLocalizedString("park.overlays", comment: "")) {
                    Picker(NSLocalizedString("park.overlay", comment: ""), selection: $session.activeOverlay) {
                        ForEach(MapOverlay.allCases) { overlay in
                            Label(
                                NSLocalizedString(overlay.localizationKey, comment: ""),
                                systemImage: overlay.symbolName
                            )
                            .tag(overlay)
                        }
                    }
                    .pickerStyle(.inline)
                }

                if !ObjectiveSystem.statuses(in: world).isEmpty {
                    Section(NSLocalizedString("park.objectives", comment: "")) {
                        ForEach(ObjectiveSystem.statuses(in: world), id: \.definition.id) { status in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: status.isComplete ? "checkmark.seal.fill" : "target")
                                        .foregroundStyle(status.isComplete ? .green : .secondary)
                                    Text(NSLocalizedString(status.definition.titleKey, comment: ""))
                                        .font(.subheadline)
                                    Spacer()
                                    Text(String(format: "%.0f / %.0f", status.currentValue, status.definition.target))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: status.progress)
                                if status.definition.sustainedDays > 0 {
                                    Text(
                                        String(
                                            format: NSLocalizedString("park.sustained", comment: ""),
                                            status.sustainedDays, status.definition.sustainedDays
                                        )
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    private func rating(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            ProgressView(value: min(max(value, 0), 1))
                .frame(width: 110)
            Text("\(Int((value * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label): \(Int((value * 100).rounded())) percent"))
    }
}

// MARK: - Research

struct ResearchPanel: View {

    @EnvironmentObject private var session: GameSession

    var body: some View {
        List {
            if let world = session.world {
                if let activeID = world.activeResearchID, let definition = world.catalog.research[activeID] {
                    Section(NSLocalizedString("research.inProgress", comment: "")) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(NSLocalizedString(definition.nameKey, comment: "")).font(.headline)
                            ProgressView(
                                value: Double(world.researchWeeksElapsed),
                                total: Double(max(1, definition.weeksRequired))
                            )
                            Text(
                                String(
                                    format: NSLocalizedString("research.weeks", comment: ""),
                                    world.researchWeeksElapsed, definition.weeksRequired
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(NSLocalizedString("research.available", comment: "")) {
                    ForEach(ResearchSystem.availableProjects(in: world), id: \.id) { definition in
                        Button {
                            session.submit(.startResearch(definition.id))
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(NSLocalizedString(definition.nameKey, comment: ""))
                                    .font(.subheadline.weight(.medium))
                                Text(NSLocalizedString(definition.summaryKey, comment: ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(
                                    String(
                                        format: NSLocalizedString("research.cost", comment: ""),
                                        definition.costPerWeek.description, definition.weeksRequired
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section(NSLocalizedString("research.completed", comment: "")) {
                    if world.completedResearch.isEmpty {
                        Text(NSLocalizedString("research.none", comment: ""))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(world.completedResearch, id: \.self) { id in
                            Label(
                                NSLocalizedString(world.catalog.research[id]?.nameKey ?? id, comment: ""),
                                systemImage: "checkmark.circle.fill"
                            )
                            .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Notifications

struct NotificationsPanel: View {

    @EnvironmentObject private var session: GameSession

    var body: some View {
        List {
            if let world = session.world {
                let items = world.notifications.sortedForDisplay
                if items.isEmpty {
                    Text(NSLocalizedString("notifications.none", comment: ""))
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        Button(NSLocalizedString("notifications.markAllRead", comment: "")) {
                            session.submit(.markNotificationsRead)
                        }
                    }
                    ForEach(items, id: \.id.raw) { notification in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: symbol(for: notification.priority))
                                .foregroundStyle(colour(for: notification.priority))
                                .accessibilityLabel(
                                    Text(NSLocalizedString(notification.priority.localizationKey, comment: ""))
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(localised(notification.text))
                                    .font(.subheadline)
                                    .fontWeight(notification.isRead ? .regular : .semibold)
                                HStack(spacing: 6) {
                                    Text(GameDate(minutesSinceEpoch: notification.tick).description)
                                    if notification.occurrences > 1 {
                                        Text("×\(notification.occurrences)")
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                session.submit(.dismissNotification(notification.id))
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text(NSLocalizedString("common.dismiss", comment: "")))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    /// Resolves a core `LocalizedText` (key + typed arguments) against the string table.
    private func localised(_ text: LocalizedText) -> String {
        let format = NSLocalizedString(text.key, comment: "")
        guard !text.arguments.isEmpty else { return format }
        let arguments: [CVarArg] = text.arguments.map { argument in
            switch argument {
            case .text(let value): return value
            case .integer(let value): return value
            case .number(let value): return value
            case .money(let value): return value.description
            case .minutes(let value): return value
            }
        }
        return String(format: format, arguments: arguments)
    }

    private func symbol(for priority: NotificationPriority) -> String {
        switch priority {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    private func colour(for priority: NotificationPriority) -> Color {
        switch priority {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Saves

struct SavesPanel: View {

    @EnvironmentObject private var session: GameSession
    @State private var slots: [SaveMetadata] = []

    var body: some View {
        List {
            Section(NSLocalizedString("saves.manual", comment: "")) {
                ForEach(0..<SaveStore.manualSlotCount, id: \.self) { slot in
                    slotRow(slot)
                }
            }

            Section(NSLocalizedString("saves.autosave", comment: "")) {
                slotRow(SaveStore.autosaveSlot)
            }

            Section(NSLocalizedString("saves.newGame", comment: "")) {
                if let catalog = session.world?.catalog {
                    ForEach(catalog.scenarios.keys.sorted(), id: \.self) { id in
                        Button {
                            session.newGame(scenarioID: id)
                            refresh()
                        } label: {
                            Label(
                                NSLocalizedString(catalog.scenarios[id]?.nameKey ?? id, comment: ""),
                                systemImage: "play.circle"
                            )
                        }
                    }
                }
            }

            Section(NSLocalizedString("saves.cloud", comment: "")) {
                Text(NSLocalizedString("saves.cloudExplainer", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: refresh)
    }

    private func slotRow(_ slot: Int) -> some View {
        let metadata = slots.first { $0.slot == slot }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(slotTitle(slot)).font(.subheadline.weight(.medium))
                if let metadata {
                    Text("\(metadata.parkName) · \(metadata.inGameDate.description)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(
                        String(
                            format: NSLocalizedString("saves.summary", comment: ""),
                            Money(cents: metadata.cashCents).description,
                            metadata.guestCount,
                            metadata.occupancyPercent
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else {
                    Text(NSLocalizedString("saves.empty", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(NSLocalizedString("saves.save", comment: "")) {
                session.save(slot: slot)
                refresh()
            }
            .buttonStyle(.bordered)
            if metadata != nil {
                Button(NSLocalizedString("saves.load", comment: "")) {
                    session.load(slot: slot)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func slotTitle(_ slot: Int) -> String {
        slot == SaveStore.autosaveSlot
            ? NSLocalizedString("saves.autosave", comment: "")
            : String(format: NSLocalizedString("saves.slot", comment: ""), slot + 1)
    }

    private func refresh() {
        slots = session.availableSlots()
    }
}
