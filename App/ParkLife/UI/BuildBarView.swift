import SwiftUI
import ParkLifeCore

/// The build-mode strip that sits above the navigation bar while building.
struct BuildBarView: View {

    @EnvironmentObject private var session: GameSession

    var body: some View {
        if session.buildMode != .off {
            HStack(spacing: 10) {
                Text(modeDescription)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if case .building = session.buildMode {
                    Button {
                        session.rotateBuildSelection()
                    } label: {
                        Label(NSLocalizedString("build.rotate", comment: ""), systemImage: "rotate.right")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    session.submit(.undoBuild)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text(NSLocalizedString("build.undo", comment: "")))

                Button {
                    session.submit(.redoBuild)
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text(NSLocalizedString("build.redo", comment: "")))

                Button(role: .cancel) {
                    session.buildMode = .off
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(Text(NSLocalizedString("build.exit", comment: "")))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var modeDescription: String {
        switch session.buildMode {
        case .off:
            return ""
        case .path(let id):
            let name = session.world?.catalog.paths[id]?.nameKey ?? id
            return NSLocalizedString(name, comment: "")
        case .building(let id, _):
            let name = session.world?.catalog.buildings[id]?.nameKey ?? id
            return NSLocalizedString(name, comment: "")
        case .demolish:
            return NSLocalizedString("build.demolish", comment: "")
        }
    }
}

/// The catalogue of everything the player can place, grouped by category.
///
/// Entirely data-driven: this view never names a building. Adding a cottage to `buildings.json`
/// makes it appear here (Rule 4).
struct BuildPanel: View {

    @EnvironmentObject private var session: GameSession

    var body: some View {
        List {
            Section(NSLocalizedString("build.tools", comment: "")) {
                Button {
                    session.buildMode = .demolish
                } label: {
                    Label(NSLocalizedString("build.demolish", comment: ""), systemImage: "trash")
                }
                .tint(.red)

                Button {
                    session.buildMode = .off
                } label: {
                    Label(NSLocalizedString("build.inspect", comment: ""), systemImage: "hand.tap")
                }
            }

            if let catalog = session.world?.catalog {
                Section(NSLocalizedString("buildingCategory.path", comment: "")) {
                    ForEach(availablePaths(catalog), id: \.id) { definition in
                        row(
                            title: NSLocalizedString(definition.nameKey, comment: ""),
                            subtitle: String(
                                format: NSLocalizedString("build.perTile", comment: ""),
                                definition.costPerTile.description
                            ),
                            isSelected: session.buildMode == .path(definition.id)
                        ) {
                            session.buildMode = .path(definition.id)
                        }
                    }
                }

                ForEach(BuildingCategory.allCases, id: \.self) { category in
                    let definitions = availableBuildings(catalog, category: category)
                    if !definitions.isEmpty {
                        Section(NSLocalizedString(category.localizationKey, comment: "")) {
                            ForEach(definitions, id: \.id) { definition in
                                row(
                                    title: NSLocalizedString(definition.nameKey, comment: ""),
                                    subtitle: subtitle(for: definition),
                                    isSelected: isSelected(definition.id)
                                ) {
                                    session.buildMode = .building(definition.id, .none)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func availablePaths(_ catalog: ContentCatalog) -> [PathDefinition] {
        let completed = Set(session.world?.completedResearch ?? [])
        return catalog.pathIDs
            .compactMap { catalog.paths[$0] }
            .filter { $0.researchID == nil || completed.contains($0.researchID!) }
    }

    private func availableBuildings(_ catalog: ContentCatalog, category: BuildingCategory) -> [BuildingDefinition] {
        let completed = Set(session.world?.completedResearch ?? [])
        return catalog.availableBuildings(completedResearch: completed)
            .filter { $0.category == category && $0.facility?.kind != .entrance }
    }

    private func isSelected(_ id: String) -> Bool {
        if case .building(let selected, _) = session.buildMode { return selected == id }
        return false
    }

    private func subtitle(for definition: BuildingDefinition) -> String {
        var parts = [definition.constructionCost.description]
        parts.append("\(definition.footprintWidth)×\(definition.footprintHeight)")
        if let accommodation = definition.accommodation {
            parts.append(
                String(
                    format: NSLocalizedString("build.sleeps", comment: ""),
                    accommodation.capacity
                )
            )
            parts.append(NSLocalizedString(accommodation.tier.localizationKey, comment: ""))
        }
        if let facility = definition.facility, facility.basePrice.cents > 0 {
            parts.append(facility.basePrice.description)
        }
        return parts.joined(separator: " · ")
    }

    private func row(title: String, subtitle: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
