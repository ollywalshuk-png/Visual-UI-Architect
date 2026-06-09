import Foundation

/// Edge a layer can be pinned to within its parent.
public enum LayerEdge: String, Codable, Hashable, Sendable, CaseIterable {
    case top, bottom, leading, trailing
    case centerX, centerY
    case width, height
}

/// A single adaptive constraint. Maps to Auto Layout anchors and informs
/// SwiftUI layout/alignment generation.
public struct LayerConstraint: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var edge: LayerEdge
    /// nil target == pin relative to the parent container.
    public var targetLayerID: UUID?
    public var targetEdge: LayerEdge?
    public var constant: Double
    /// 1.0 == equal; used for proportional width/height.
    public var multiplier: Double
    public var priority: Int   // 1...1000 (Auto Layout style)

    public init(
        id: UUID = UUID(),
        edge: LayerEdge,
        targetLayerID: UUID? = nil,
        targetEdge: LayerEdge? = nil,
        constant: Double = 0,
        multiplier: Double = 1,
        priority: Int = 1000
    ) {
        self.id = id
        self.edge = edge
        self.targetLayerID = targetLayerID
        self.targetEdge = targetEdge
        self.constant = constant
        self.multiplier = multiplier
        self.priority = priority
    }
}
