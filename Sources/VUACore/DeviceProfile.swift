import Foundation

/// A device + orientation the canvas can be previewed against.
public struct DeviceProfile: Identifiable, Codable, Hashable, Sendable {
    public enum Family: String, Codable, Hashable, Sendable, CaseIterable {
        case mac, iPad, iPhone, watch
        // Reserved for expansion.
        case vision
    }

    public enum Orientation: String, Codable, Hashable, Sendable, CaseIterable {
        case portrait, landscape
    }

    public let id: UUID
    public var name: String
    public var family: Family
    /// Logical (point) size in portrait orientation.
    public var portraitSize: VSize
    public var scale: Int
    public var supportsLandscape: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        family: Family,
        portraitSize: VSize,
        scale: Int,
        supportsLandscape: Bool
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.portraitSize = portraitSize
        self.scale = scale
        self.supportsLandscape = supportsLandscape
    }

    public func size(for orientation: Orientation) -> VSize {
        switch orientation {
        case .portrait: return portraitSize
        case .landscape where supportsLandscape:
            return VSize(width: portraitSize.height, height: portraitSize.width)
        case .landscape:
            return portraitSize
        }
    }

    // MARK: - Built-in catalog

    public static let mac = DeviceProfile(
        name: "Mac Window", family: .mac,
        portraitSize: VSize(width: 1280, height: 800), scale: 2, supportsLandscape: false)

    public static let iPadPro11 = DeviceProfile(
        name: "iPad Pro 11\"", family: .iPad,
        portraitSize: VSize(width: 834, height: 1194), scale: 2, supportsLandscape: true)

    public static let iPhone15Pro = DeviceProfile(
        name: "iPhone 15 Pro", family: .iPhone,
        portraitSize: VSize(width: 393, height: 852), scale: 3, supportsLandscape: true)

    public static let appleWatch = DeviceProfile(
        name: "Apple Watch 45mm", family: .watch,
        portraitSize: VSize(width: 198, height: 242), scale: 2, supportsLandscape: false)

    public static let catalog: [DeviceProfile] = [.mac, .iPadPro11, .iPhone15Pro, .appleWatch]
}
