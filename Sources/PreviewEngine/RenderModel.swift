import Foundation
import VUACore
import LayerEngine

/// A flattened, absolutely-positioned representation of the document ready for
/// rendering by any front-end (the SwiftUI canvas, an export rasteriser, etc).
public struct RenderModel: Sendable {
    public struct Node: Identifiable, Sendable {
        public let id: UUID
        public var layer: Layer
        /// Absolute frame in canvas coordinates.
        public var absoluteFrame: VRect
        public var depth: Int
    }

    public var canvasSize: VSize
    public var nodes: [Node]   // back-to-front order

    public init(canvasSize: VSize, nodes: [Node]) {
        self.canvasSize = canvasSize
        self.nodes = nodes
    }
}

/// Builds a `RenderModel` for a document, optionally adapting to a device.
public struct PreviewBuilder: Sendable {
    public init() {}

    public func build(_ document: Document) -> RenderModel {
        var nodes: [RenderModel.Node] = []
        func walk(_ layers: [Layer], offset: VPoint, depth: Int) {
            for layer in layers where layer.isVisible {
                let abs = VRect(
                    x: offset.x + layer.frame.origin.x,
                    y: offset.y + layer.frame.origin.y,
                    width: layer.frame.width, height: layer.frame.height)
                nodes.append(.init(id: layer.id, layer: layer, absoluteFrame: abs, depth: depth))
                walk(layer.children, offset: abs.origin, depth: depth + 1)
            }
        }
        walk(document.roots, offset: .zero, depth: 0)
        return RenderModel(canvasSize: document.canvasSize, nodes: nodes)
    }
}
