import Foundation

/// An imported visual asset tracked by the asset engine.
public struct Asset: Identifiable, Codable, Hashable, Sendable {
    public enum Format: String, Codable, Hashable, Sendable, CaseIterable {
        case png, jpeg, svg, pdf

        public init?(fileExtension ext: String) {
            switch ext.lowercased() {
            case "png": self = .png
            case "jpg", "jpeg": self = .jpeg
            case "svg": self = .svg
            case "pdf": self = .pdf
            default: return nil
            }
        }

        public var isVector: Bool { self == .svg || self == .pdf }
    }

    public let id: UUID
    public var name: String
    /// Repository-relative path to the asset on disk.
    public var path: String
    public var format: Format
    /// Intrinsic point size (pre-scale). Vector assets may have nominal size.
    public var intrinsicSize: VSize
    /// Asset scale factor (1x/2x/3x) for raster retina assets.
    public var scale: Int
    public var isLocked: Bool
    /// Organisational tags for the asset library (e.g. "panel", "knob", "bg").
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        format: Format,
        intrinsicSize: VSize = .zero,
        scale: Int = 1,
        isLocked: Bool = false,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.format = format
        self.intrinsicSize = intrinsicSize
        self.scale = scale
        self.isLocked = isLocked
        self.tags = tags
    }
}
