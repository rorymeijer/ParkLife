import Foundation

/// An entity that lives in an `EntityStore`.
public protocol StoredEntity {
    associatedtype Identifier: EntityIdentifier
    var id: Identifier { get }
}

/// Dense storage with stable identifiers.
///
/// Iteration is over a contiguous array (cache friendly, and the tick loop iterates constantly),
/// while lookup by id stays O(1). Removal is swap-remove, so ids must never be confused with
/// indices — they are not.
public struct EntityStore<Element: StoredEntity> {

    public private(set) var items: [Element]
    private var indexByID: [UInt32: Int]

    public init() {
        self.items = []
        self.indexByID = [:]
    }

    public init(_ elements: [Element]) {
        self.items = elements
        self.indexByID = [:]
        self.indexByID.reserveCapacity(elements.count)
        for (index, element) in elements.enumerated() {
            self.indexByID[element.id.raw] = index
        }
    }

    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }

    public func contains(_ id: Element.Identifier) -> Bool {
        indexByID[id.raw] != nil
    }

    public subscript(id: Element.Identifier) -> Element? {
        get {
            guard let index = indexByID[id.raw] else { return nil }
            return items[index]
        }
        set {
            if let newValue {
                insert(newValue)
            } else {
                remove(id)
            }
        }
    }

    /// Inserts or replaces.
    public mutating func insert(_ element: Element) {
        if let index = indexByID[element.id.raw] {
            items[index] = element
        } else {
            indexByID[element.id.raw] = items.count
            items.append(element)
        }
    }

    @discardableResult
    public mutating func remove(_ id: Element.Identifier) -> Element? {
        guard let index = indexByID[id.raw] else { return nil }
        let removed = items[index]
        let lastIndex = items.count - 1
        if index != lastIndex {
            items.swapAt(index, lastIndex)
            indexByID[items[index].id.raw] = index
        }
        items.removeLast()
        indexByID[id.raw] = nil
        return removed
    }

    public mutating func removeAll() {
        items.removeAll()
        indexByID.removeAll()
    }

    /// In-place mutation without copying the element out and back.
    @discardableResult
    public mutating func modify<T>(_ id: Element.Identifier, _ body: (inout Element) -> T) -> T? {
        guard let index = indexByID[id.raw] else { return nil }
        return body(&items[index])
    }

    /// Mutates every element in storage order (deterministic).
    public mutating func forEachMutating(_ body: (inout Element) -> Void) {
        for index in items.indices {
            body(&items[index])
        }
    }

    /// Identifiers in ascending order — use this whenever iteration order must be deterministic
    /// across runs (storage order changes with swap-remove).
    public var sortedIDs: [Element.Identifier] {
        items.map(\.id).sorted()
    }
}

extension EntityStore: Codable where Element: Codable {

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode([Element].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        // Storage order, deliberately *not* id order. Where entities sit in the array is itself
        // deterministic simulation state, and floating-point aggregates over `items` — mean guest
        // happiness, mean cleanliness — depend on summation order. Sorting here made a reloaded
        // game drift away from the one that was saved, which `DeterminismTests` caught.
        try container.encode(items)
    }
}
