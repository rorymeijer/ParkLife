import Foundation

public enum ContentError: Error, CustomStringConvertible {
    case resourceMissing(String)
    case decodingFailed(String, String)
    case unknownDefinition(String)

    public var description: String {
        switch self {
        case .resourceMissing(let name):
            return "Content resource '\(name)' is missing from the bundle"
        case .decodingFailed(let name, let reason):
            return "Content resource '\(name)' could not be decoded: \(reason)"
        case .unknownDefinition(let id):
            return "No definition with id '\(id)'"
        }
    }
}

/// All game content, loaded from JSON.
///
/// Everything here is immutable: definitions describe gameplay properties, runtime instances hold
/// the changing state. Adding a cottage type, a restaurant or a whole new map is a data change
/// (brief §40).
public struct ContentCatalog {

    public let buildings: [String: BuildingDefinition]
    public let paths: [String: PathDefinition]
    public let staffRoles: [String: StaffRoleDefinition]
    public let research: [String: ResearchDefinition]
    public let scenarios: [String: ScenarioDefinition]
    public let archetypes: [String: GroupArchetypeDefinition]
    public let maps: [String: MapDefinition]
    public let calendars: [String: CalendarDefinition]
    public let names: NameCatalog

    /// Stable, sorted id lists. Dictionary order is not deterministic, and the simulation must be.
    public let buildingIDs: [String]
    public let pathIDs: [String]
    public let archetypeIDs: [String]

    public init(
        buildings: [BuildingDefinition],
        paths: [PathDefinition],
        staffRoles: [StaffRoleDefinition],
        research: [ResearchDefinition],
        scenarios: [ScenarioDefinition],
        archetypes: [GroupArchetypeDefinition],
        maps: [MapDefinition],
        calendars: [CalendarDefinition],
        names: NameCatalog
    ) {
        var buildingMap: [String: BuildingDefinition] = [:]
        for definition in buildings { buildingMap[definition.id] = definition }
        var pathMap: [String: PathDefinition] = [:]
        for definition in paths { pathMap[definition.id] = definition }
        var roleMap: [String: StaffRoleDefinition] = [:]
        for definition in staffRoles { roleMap[definition.id] = definition }
        var researchMap: [String: ResearchDefinition] = [:]
        for definition in research { researchMap[definition.id] = definition }
        var scenarioMap: [String: ScenarioDefinition] = [:]
        for definition in scenarios { scenarioMap[definition.id] = definition }
        var archetypeMap: [String: GroupArchetypeDefinition] = [:]
        for definition in archetypes { archetypeMap[definition.id] = definition }
        var mapMap: [String: MapDefinition] = [:]
        for definition in maps { mapMap[definition.id] = definition }
        var calendarMap: [String: CalendarDefinition] = [:]
        for definition in calendars { calendarMap[definition.regionID] = definition }

        self.buildings = buildingMap
        self.paths = pathMap
        self.staffRoles = roleMap
        self.research = researchMap
        self.scenarios = scenarioMap
        self.archetypes = archetypeMap
        self.maps = mapMap
        self.calendars = calendarMap
        self.names = names

        self.buildingIDs = buildingMap.keys.sorted()
        self.pathIDs = pathMap.keys.sorted()
        self.archetypeIDs = archetypeMap.keys.sorted()
    }

    // MARK: - Lookup

    public func building(_ id: String) throws -> BuildingDefinition {
        guard let definition = buildings[id] else { throw ContentError.unknownDefinition(id) }
        return definition
    }

    public func path(_ id: String) throws -> PathDefinition {
        guard let definition = paths[id] else { throw ContentError.unknownDefinition(id) }
        return definition
    }

    public func archetype(_ id: String) throws -> GroupArchetypeDefinition {
        guard let definition = archetypes[id] else { throw ContentError.unknownDefinition(id) }
        return definition
    }

    public func map(_ id: String) throws -> MapDefinition {
        guard let definition = maps[id] else { throw ContentError.unknownDefinition(id) }
        return definition
    }

    public func scenario(_ id: String) throws -> ScenarioDefinition {
        guard let definition = scenarios[id] else { throw ContentError.unknownDefinition(id) }
        return definition
    }

    public func staffRole(_ id: String) throws -> StaffRoleDefinition {
        guard let definition = staffRoles[id] else { throw ContentError.unknownDefinition(id) }
        return definition
    }

    /// Building definitions in a category, in stable id order.
    public func buildings(in category: BuildingCategory) -> [BuildingDefinition] {
        buildingIDs.compactMap { buildings[$0] }.filter { $0.category == category }
    }

    /// Accommodation definitions in stable id order.
    public var accommodationDefinitions: [BuildingDefinition] {
        buildingIDs.compactMap { buildings[$0] }.filter { $0.isAccommodation }
    }

    public func facilityDefinitions(ofKind kind: FacilityKind) -> [BuildingDefinition] {
        buildingIDs.compactMap { buildings[$0] }.filter { $0.facility?.kind == kind }
    }

    /// Definitions available to the player given completed research.
    public func availableBuildings(completedResearch: Set<String>) -> [BuildingDefinition] {
        buildingIDs.compactMap { buildings[$0] }.filter { definition in
            guard let required = definition.researchID else { return true }
            return completedResearch.contains(required)
        }
    }

    // MARK: - Loading

    public static func load(from bundle: Bundle) throws -> ContentCatalog {
        let decoder = JSONDecoder()

        func read<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
            guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Catalog")
                ?? bundle.url(forResource: name, withExtension: "json") else {
                throw ContentError.resourceMissing(name)
            }
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw ContentError.resourceMissing(name)
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw ContentError.decodingFailed(name, String(describing: error))
            }
        }

        let catalog = ContentCatalog(
            buildings: try read("buildings", as: [BuildingDefinition].self),
            paths: try read("paths", as: [PathDefinition].self),
            staffRoles: try read("staffRoles", as: [StaffRoleDefinition].self),
            research: try read("research", as: [ResearchDefinition].self),
            scenarios: try read("scenarios", as: [ScenarioDefinition].self),
            archetypes: try read("groupArchetypes", as: [GroupArchetypeDefinition].self),
            maps: try read("maps", as: [MapDefinition].self),
            calendars: try read("calendars", as: [CalendarDefinition].self),
            names: try read("names", as: NameCatalog.self)
        )
        ParkLog.shared.info(
            .content,
            "Loaded catalog: \(catalog.buildings.count) buildings, \(catalog.maps.count) maps, \(catalog.archetypes.count) archetypes"
        )
        return catalog
    }

    /// Loads the catalog shipped inside ParkLifeCore.
    public static func bundled() throws -> ContentCatalog {
        try load(from: Bundle.module)
    }
}
