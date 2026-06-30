import SceneKit

public enum DeckSceneLayerToggle {
    public static let overheadLayerNodeName = "layer.overhead"

    public static func apply(overheadVisible: Bool, to root: SCNNode) {
        for node in root.nodes(named: overheadLayerNodeName) {
            node.isHidden = !overheadVisible
        }
    }
}

private extension SCNNode {
    func nodes(named targetName: String) -> [SCNNode] {
        var matches: [SCNNode] = []
        if name == targetName {
            matches.append(self)
        }
        for child in childNodes {
            matches.append(contentsOf: child.nodes(named: targetName))
        }
        return matches
    }
}
