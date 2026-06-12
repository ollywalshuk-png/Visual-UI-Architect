// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VisualUIArchitect",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VisualUIArchitect", targets: ["VisualUIArchitect"]),
        .executable(name: "VUACheck", targets: ["VUACheck"]),
        .library(name: "VUACore", targets: ["VUACore"]),
        // Reusable SwiftUI plugin controls — generated code imports this.
        .library(name: "VUAControls", targets: ["VUAControls"]),
        .library(name: "VUAEngines", targets: [
            "LayerEngine", "CanvasEngine", "AssetEngine", "LayoutEngine",
            "ConstraintEngine", "ValidationEngine", "GitEngine",
            "CodeGenEngine", "AIEngine", "PreviewEngine", "RepositoryEngine",
            "ExportIntegrityEngine", "PersistenceEngine", "PresetEngine", "WorkspaceEngine", "ComponentEngine",
            "BuildIntelligenceEngine", "HandoffGeneratorEngine", "UIQualityEngine", "ControlBehaviourEngine", "ImportEngine",
            "RasterDrawingEngine", "VectorDrawingEngine"
        ])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0")
    ],
    targets: [
        // Foundation domain layer — shared by every engine.
        .target(name: "VUACore"),

        // Shipping SwiftUI control library (self-contained, no engine deps).
        .target(name: "VUAControls"),

        // Compile-time proof that generated control code matches the library API.
        .target(name: "ControlsExample", dependencies: ["VUAControls"]),

        // Engines (modular, single-responsibility).
        .target(name: "LayerEngine", dependencies: ["VUACore"]),
        .target(name: "CanvasEngine", dependencies: ["VUACore", "LayerEngine"]),
        .target(name: "AssetEngine", dependencies: ["VUACore"]),
        .target(name: "ControlBehaviourEngine", dependencies: ["VUACore"]),
        .target(name: "RasterDrawingEngine", dependencies: ["VUACore"]),
        .target(name: "VectorDrawingEngine", dependencies: ["VUACore"]),
        .target(name: "LayoutEngine", dependencies: ["VUACore", "LayerEngine"]),
        .target(name: "ConstraintEngine", dependencies: ["VUACore", "LayerEngine"]),
        .target(name: "ValidationEngine", dependencies: ["VUACore", "LayerEngine", "RasterDrawingEngine", "VectorDrawingEngine"]),
        .target(name: "GitEngine", dependencies: ["VUACore"]),
        .target(name: "CodeGenEngine", dependencies: ["VUACore", "LayerEngine", "LayoutEngine", "ControlBehaviourEngine"]),
        .target(name: "AIEngine", dependencies: ["VUACore", "LayerEngine"]),
        .target(name: "PreviewEngine", dependencies: ["VUACore", "LayerEngine"]),

        // Repository round-trip: SwiftSyntax-based parse + source-fidelity write.
        .target(
            name: "RepositoryEngine",
            dependencies: [
                "VUACore", "LayerEngine", "ValidationEngine", "CodeGenEngine", "GitEngine",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax")
            ]
        ),

        // Universal import architecture: framework detection + adapter routing metadata.
        .target(name: "ImportEngine", dependencies: ["VUACore", "RepositoryEngine"]),

        // Persistence: .vuaproj document bundle (document.json + Assets/).
        .target(name: "PersistenceEngine", dependencies: ["VUACore", "AssetEngine"]),

        // Reusable layout presets (insertable layer subtrees).
        .target(name: "PresetEngine", dependencies: ["VUACore"]),

        // Repo/workspace safety: resolve the right repo/app/target before writes.
        .target(name: "WorkspaceEngine", dependencies: ["VUACore", "GitEngine"]),

        // Reusable components: masters, instances, propagation, detach.
        .target(name: "ComponentEngine", dependencies: ["VUACore", "LayerEngine"]),

        // Build intelligence: toolchain/package diagnostics + failure explanation.
        .target(name: "BuildIntelligenceEngine", dependencies: ["VUACore"]),

        // AI/developer handoff generation (HANDOFF.md).
        .target(name: "HandoffGeneratorEngine", dependencies: ["VUACore"]),

        // UI quality assessment: density/spacing/contrast/noise heuristics + scores.
        .target(name: "UIQualityEngine", dependencies: ["VUACore"]),

        // Export Integrity Pipeline: portable, target-buildable SwiftUI export.
        .target(
            name: "ExportIntegrityEngine",
            dependencies: [
                "VUACore", "LayerEngine", "AssetEngine", "CodeGenEngine",
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ],
            // Ship VUAControls sources as a resource so we can copy them into
            // an export destination on a machine that has no source checkout.
            resources: [.copy("VUAControlsSources")]
        ),

        // Application (SwiftUI + AppKit shell).
        .executableTarget(
            name: "VisualUIArchitect",
            dependencies: [
                "VUACore", "LayerEngine", "CanvasEngine", "AssetEngine",
                "LayoutEngine", "ConstraintEngine", "ValidationEngine",
                "GitEngine", "CodeGenEngine", "AIEngine", "PreviewEngine", "RepositoryEngine",
                "VUAControls", "ExportIntegrityEngine", "PersistenceEngine", "PresetEngine",
                "WorkspaceEngine", "BuildIntelligenceEngine", "HandoffGeneratorEngine", "ImportEngine",
                "UIQualityEngine", "ComponentEngine", "ControlBehaviourEngine", "RasterDrawingEngine", "VectorDrawingEngine"
            ]
        ),

        // Toolchain-independent verification harness (runs without Xcode).
        .executableTarget(
            name: "VUACheck",
            dependencies: [
                "VUACore", "LayerEngine", "CodeGenEngine", "ValidationEngine",
                "ConstraintEngine", "LayoutEngine", "PreviewEngine", "AIEngine", "RepositoryEngine",
                "AssetEngine", "VUAControls", "ExportIntegrityEngine", "PersistenceEngine", "PresetEngine",
                "CanvasEngine", "WorkspaceEngine", "BuildIntelligenceEngine", "HandoffGeneratorEngine", "ImportEngine",
                "UIQualityEngine", "ComponentEngine", "ControlBehaviourEngine", "RasterDrawingEngine", "VectorDrawingEngine"
            ]
        ),

        // XCTest targets (run via `swift test` once Xcode is installed, or in CI).
        .testTarget(name: "VUACoreTests", dependencies: ["VUACore"]),
        .testTarget(name: "CodeGenEngineTests", dependencies: ["CodeGenEngine", "VUACore", "LayerEngine"]),
        .testTarget(name: "ValidationEngineTests", dependencies: ["ValidationEngine", "VUACore", "LayerEngine"]),
        .testTarget(name: "RepositoryEngineTests", dependencies: ["RepositoryEngine", "VUACore", "LayerEngine"]),
        .testTarget(name: "ComponentEngineTests", dependencies: ["ComponentEngine", "CodeGenEngine", "VUACore", "LayerEngine"]),
        .testTarget(name: "ControlBehaviourEngineTests", dependencies: ["ControlBehaviourEngine", "CodeGenEngine", "VUACore"])
    ]
)
