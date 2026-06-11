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
    /// Phase 17: functional metadata (role / function / binding). Optional so
    /// legacy `Asset` JSON (without this key) decodes unchanged.
    public var metadata: AssetMetadata?

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        format: Format,
        intrinsicSize: VSize = .zero,
        scale: Int = 1,
        isLocked: Bool = false,
        tags: [String] = [],
        metadata: AssetMetadata? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.format = format
        self.intrinsicSize = intrinsicSize
        self.scale = scale
        self.isLocked = isLocked
        self.tags = tags
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, path, format, intrinsicSize, scale, isLocked, tags, metadata
    }

    /// Custom decoder so assets saved before Phase 17 (no `metadata` key)
    /// still load — `metadata` defaults to nil.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        format = try c.decode(Format.self, forKey: .format)
        intrinsicSize = try c.decode(VSize.self, forKey: .intrinsicSize)
        scale = try c.decode(Int.self, forKey: .scale)
        isLocked = try c.decode(Bool.self, forKey: .isLocked)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        metadata = try c.decodeIfPresent(AssetMetadata.self, forKey: .metadata)
    }
}
