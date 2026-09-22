import SpriteKit

/// Reuses `SKSpriteNode`s instead of creating and destroying them each frame.
///
/// Node count is tied to what is on screen, not to how big the park is — the world itself is a
/// data grid, never a node tree (brief §42).
final class SpriteNodePool {

    private let parent: SKNode
    private var available: [SKSpriteNode] = []
    private var inUse: [SKSpriteNode] = []

    init(parent: SKNode, prewarm: Int = 0) {
        self.parent = parent
        available.reserveCapacity(prewarm)
        for _ in 0..<prewarm {
            let node = SKSpriteNode()
            node.isHidden = true
            parent.addChild(node)
            available.append(node)
        }
    }

    /// Call at the start of a frame; every node not claimed this frame is hidden again.
    func beginFrame() {
        available.append(contentsOf: inUse)
        inUse.removeAll(keepingCapacity: true)
    }

    func claim() -> SKSpriteNode {
        if let node = available.popLast() {
            node.isHidden = false
            inUse.append(node)
            return node
        }
        let node = SKSpriteNode()
        parent.addChild(node)
        inUse.append(node)
        return node
    }

    /// Call at the end of a frame to hide anything left over.
    func endFrame() {
        for node in available where !node.isHidden {
            node.isHidden = true
        }
    }

    var activeCount: Int { inUse.count }
    var totalCount: Int { inUse.count + available.count }
}
