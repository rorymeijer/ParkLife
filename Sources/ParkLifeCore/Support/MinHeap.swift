import Foundation

/// Binary min-heap used by A*, the flow-field sweep and the tick scheduler.
///
/// Written by hand rather than pulled in as a dependency: it is 60 lines, it must be
/// deterministic, and it must be usable from a value-type simulation state.
public struct MinHeap<Element: Comparable> {

    public private(set) var storage: [Element]

    public init() {
        self.storage = []
    }

    public init(_ elements: [Element]) {
        self.storage = elements
        guard storage.count > 1 else { return }
        for index in stride(from: storage.count / 2 - 1, through: 0, by: -1) {
            siftDown(from: index)
        }
    }

    public var isEmpty: Bool { storage.isEmpty }
    public var count: Int { storage.count }
    public var min: Element? { storage.first }

    public mutating func insert(_ element: Element) {
        storage.append(element)
        siftUp(from: storage.count - 1)
    }

    @discardableResult
    public mutating func removeMin() -> Element? {
        guard !storage.isEmpty else { return nil }
        storage.swapAt(0, storage.count - 1)
        let element = storage.removeLast()
        if !storage.isEmpty { siftDown(from: 0) }
        return element
    }

    public mutating func removeAll(keepingCapacity: Bool = true) {
        storage.removeAll(keepingCapacity: keepingCapacity)
    }

    private mutating func siftUp(from start: Int) {
        var child = start
        while child > 0 {
            let parent = (child - 1) / 2
            if storage[child] < storage[parent] {
                storage.swapAt(child, parent)
                child = parent
            } else {
                return
            }
        }
    }

    private mutating func siftDown(from start: Int) {
        var parent = start
        let count = storage.count
        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var smallest = parent
            if left < count, storage[left] < storage[smallest] { smallest = left }
            if right < count, storage[right] < storage[smallest] { smallest = right }
            if smallest == parent { return }
            storage.swapAt(parent, smallest)
            parent = smallest
        }
    }
}
