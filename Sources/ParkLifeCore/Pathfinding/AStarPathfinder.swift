import Foundation

/// A* over the walkable tile grid.
///
/// Used only for *private* destinations (a specific cottage, a staff task). Shared destinations go
/// through flow fields instead, because running A* per guest per destination is exactly the thing
/// the brief says not to do.
public enum AStarPathfinder {

    struct Node: Comparable {
        let estimatedTotal: Int32
        let index: Int32

        static func < (lhs: Node, rhs: Node) -> Bool {
            if lhs.estimatedTotal != rhs.estimatedTotal { return lhs.estimatedTotal < rhs.estimatedTotal }
            // Deterministic tie-break, otherwise equal-cost paths vary between runs.
            return lhs.index < rhs.index
        }
    }

    public struct Result {
        public let tiles: [GridPoint]
        public let cost: Int
        public let nodesExplored: Int
    }

    /// Finds the cheapest path from `start` to any tile in `goals`.
    ///
    /// - Parameter nodeBudget: hard cap on explored nodes, so one pathological request can never
    ///   stall a tick. Returns `nil` when the budget is exhausted.
    public static func findPath(
        from start: GridPoint,
        toAnyOf goals: [GridPoint],
        network: PathNetwork,
        nodeBudget: Int = 8_000
    ) -> Result? {
        guard network.isWalkable(start) else { return nil }
        let size = network.size
        guard let startIndex = size.index(of: start) else { return nil }

        var goalIndices: [Int] = []
        var reachableGoals: [GridPoint] = []
        let startComponent = network.component(at: start)
        for goal in goals {
            guard let index = size.index(of: goal), network.walkable[index] else { continue }
            guard network.component[index] == startComponent else { continue }
            goalIndices.append(index)
            reachableGoals.append(goal)
        }
        guard !goalIndices.isEmpty else { return nil }

        if goalIndices.contains(startIndex) {
            return Result(tiles: [start], cost: 0, nodesExplored: 0)
        }

        let tileCount = size.tileCount
        var gScore = [Int32](repeating: Int32.max, count: tileCount)
        var cameFrom = [Int32](repeating: -1, count: tileCount)
        var closed = [Bool](repeating: false, count: tileCount)

        func heuristic(_ index: Int) -> Int32 {
            let x = index % size.width
            let y = index / size.width
            var best = Int32.max
            for goal in reachableGoals {
                let distance = Int32((abs(x - goal.x) + abs(y - goal.y)) * 9)
                if distance < best { best = distance }
            }
            return best
        }

        var open = MinHeap<Node>()
        gScore[startIndex] = 0
        open.insert(Node(estimatedTotal: heuristic(startIndex), index: Int32(startIndex)))

        var explored = 0
        while let node = open.removeMin() {
            let index = Int(node.index)
            if closed[index] { continue }
            closed[index] = true
            explored += 1
            if explored > nodeBudget { return nil }

            if goalIndices.contains(index) {
                return Result(
                    tiles: reconstruct(from: index, cameFrom: cameFrom, size: size),
                    cost: Int(gScore[index]),
                    nodesExplored: explored
                )
            }

            let x = index % size.width
            let y = index / size.width
            let currentScore = gScore[index]

            var neighbours: [Int] = []
            neighbours.reserveCapacity(4)
            if x > 0 { neighbours.append(index - 1) }
            if x < size.width - 1 { neighbours.append(index + 1) }
            if y > 0 { neighbours.append(index - size.width) }
            if y < size.height - 1 { neighbours.append(index + size.width) }

            for neighbour in neighbours {
                guard network.walkable[neighbour], !closed[neighbour] else { continue }
                let tentative = currentScore + Int32(network.cost[neighbour])
                if tentative < gScore[neighbour] {
                    gScore[neighbour] = tentative
                    cameFrom[neighbour] = Int32(index)
                    open.insert(Node(estimatedTotal: tentative + heuristic(neighbour), index: Int32(neighbour)))
                }
            }
        }
        return nil
    }

    private static func reconstruct(from goal: Int, cameFrom: [Int32], size: GridSize) -> [GridPoint] {
        var reversed: [GridPoint] = []
        var cursor = goal
        while cursor >= 0 {
            reversed.append(size.point(at: cursor))
            let previous = cameFrom[cursor]
            if previous < 0 { break }
            cursor = Int(previous)
        }
        return reversed.reversed()
    }
}
