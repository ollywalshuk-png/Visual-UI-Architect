import Foundation
import RepositoryEngine

public enum ImportFramework: String, Codable, Hashable, Sendable, CaseIterable {
    case swiftUI
    case uiKit
    case appKit
    case react
    case reactNative
    case electron
    case htmlCSS
    case flutter
    case unknown

    public var displayName: String {
        switch self {
        case .swiftUI: return "SwiftUI"
        case .uiKit: return "UIKit"
        case .appKit: return "AppKit"
        case .react: return "React"
        case .reactNative: return "React Native"
        case .electron: return "Electron"
        case .htmlCSS: return "HTML/CSS"
        case .flutter: return "Flutter"
        case .unknown: return "Unknown"
        }
    }

    public var isImportImplemented: Bool {
        switch self {
        case .swiftUI, .react, .reactNative, .electron, .htmlCSS:
            return true
        case .uiKit, .appKit, .flutter, .unknown:
            return false
        }
    }
}

public enum ImportCompatibilityRating: String, Codable, Hashable, Sendable {
    case green, yellow, red
}

public enum ImplementationState: String, Codable, Hashable, Sendable {
    case implemented
    case foundationOnly
    case comingSoon
    case unsupported
}

public struct ImportProjectSummary: Hashable, Sendable {
    public var rootPath: String
    public var framework: ImportFramework
    public var implementationState: ImplementationState
    public var rating: ImportCompatibilityRating
    public var fileCount: Int
    public var screenCount: Int
    public var componentCount: Int
    public var warnings: [String]
    public var candidates: [ExistingUIImport.Candidate]
}
