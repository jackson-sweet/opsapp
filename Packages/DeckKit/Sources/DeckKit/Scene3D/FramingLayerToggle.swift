import SceneKit

public struct FramingLayer: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let decking = FramingLayer(rawValue: 1 << 0)
    public static let joists = FramingLayer(rawValue: 1 << 1)
    public static let beams = FramingLayer(rawValue: 1 << 2)
    public static let posts = FramingLayer(rawValue: 1 << 3)
    public static let footings = FramingLayer(rawValue: 1 << 4)
    public static let rim = FramingLayer(rawValue: 1 << 5)
    public static let blocking = FramingLayer(rawValue: 1 << 6)

    public static let all: FramingLayer = [
        .decking,
        .joists,
        .beams,
        .posts,
        .footings,
        .rim,
        .blocking,
    ]

    public static let displayOrder: [FramingLayer] = [
        .decking,
        .joists,
        .beams,
        .posts,
        .footings,
        .rim,
        .blocking,
    ]

    public var layerNodeName: String {
        switch self {
        case .decking: return "layer.decking"
        case .joists: return "layer.joists"
        case .beams: return "layer.beams"
        case .posts: return "layer.posts"
        case .footings: return "layer.footings"
        case .rim: return "layer.rim"
        case .blocking: return "layer.blocking"
        default: return "layer.unknown"
        }
    }

    static let addressableLayers: [FramingLayer] = displayOrder
}

public enum FramingLayerToggle {
    public static func apply(_ visibleLayers: FramingLayer, to root: SCNNode) {
        for layer in FramingLayer.addressableLayers {
            for node in root.nodes(named: layer.layerNodeName) {
                node.isHidden = !visibleLayers.contains(layer)
            }
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
