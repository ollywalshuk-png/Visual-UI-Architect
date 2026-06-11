import Foundation
import VUACore
import LayerEngine
import CodeGenEngine
import ValidationEngine
import ConstraintEngine
import LayoutEngine
import PreviewEngine
import AIEngine
import RepositoryEngine
import AssetEngine
import ConstraintEngine
import VUAControls
import AppKit
import ExportIntegrityEngine
import PersistenceEngine
import PresetEngine
import CanvasEngine
import WorkspaceEngine
import BuildIntelligenceEngine
import HandoffGeneratorEngine
import UIQualityEngine
import ComponentEngine
import ControlBehaviourEngine
import RasterDrawingEngine
import VectorDrawingEngine

// A dependency-free assertion harness so the engines can be verified with
// `swift run VUACheck` on a machine that has no Xcode (no XCTest).
final class Checker: @unchecked Sendable {
    private(set) var failures = 0
    private(set) var passed = 0
    func check(_ name: String, _ condition: Bool) {
        if condition {
            passed += 1
        } else {
            failures += 1
            FileHandle.standardError.write(Data("✗ FAIL: \(name)\n".utf8))
        }
    }
}

func runChecks() async {
    let c = Checker()

    if CommandLine.arguments.contains("--dump") {
        let button = Layer(name: "Play", kind: .button,
                           frame: VRect(x: 20, y: 40, width: 120, height: 44),
                           style: LayerStyle(backgroundColor: VColor(hex: "#3478F6"),
                                             foregroundColor: .white, cornerRadius: 8),
                           text: "Play")
        let panel = Layer(name: "Transport", kind: .panel,
                          frame: VRect(x: 0, y: 0, width: 320, height: 120), children: [button])
        print((try? CodeGenService().generate(Document(roots: [panel])).contents) ?? "")
        exit(0)
    }

    // MARK: Geometry & color
    let r = VRect(x: 0, y: 0, width: 100, height: 50)
    c.check("rect contains", r.contains(VPoint(x: 50, y: 25)))
    c.check("rect intersects", r.intersects(VRect(x: 90, y: 40, width: 20, height: 20)))
    c.check("hex round trip", VColor(hex: "#3478F6")?.hexString == "#3478F6")
    c.check("luminance white", abs(VColor.white.relativeLuminance - 1) < 0.001)

    // MARK: Layer tree
    var roots: [Layer] = [Layer(name: "Root", kind: .container)]
    let child = Layer(name: "Child", kind: .label, frame: VRect(x: 10, y: 10, width: 20, height: 20))
    LayerTree.insert(child, into: &roots, parentID: roots[0].id)
    c.check("insert child", roots[0].children.count == 1)
    c.check("absolute frame", LayerTree.absoluteFrame(of: child.id, in: roots) == VRect(x: 10, y: 10, width: 20, height: 20))
    c.check("hit test", LayerTree.hitTest(VPoint(x: 15, y: 15), in: roots) == child.id)
    LayerTree.remove(child.id, from: &roots)
    c.check("remove child", roots[0].children.isEmpty)

    // Z-order: later siblings draw on top; panel "Move Up" maps to towardFront.
    var stack: [Layer] = [
        Layer(name: "Backplate", kind: .background, frame: VRect(x: 0, y: 0, width: 200, height: 200)),
        Layer(name: "Knob", kind: .knob, frame: VRect(x: 40, y: 40, width: 60, height: 60)),
        Layer(name: "Button", kind: .button, frame: VRect(x: 80, y: 80, width: 80, height: 32))
    ]
    let knobID = stack[1].id
    c.check("can reorder toward front", LayerTree.canReorder(knobID, towardFront: true, in: stack))
    c.check("cannot reorder past front", !LayerTree.canReorder(stack[2].id, towardFront: true, in: stack))
    c.check("cannot reorder past back", !LayerTree.canReorder(stack[0].id, towardFront: false, in: stack))
    LayerTree.reorder(knobID, towardFront: true, in: &stack)
    c.check("reorder toward front", stack[2].id == knobID)
    c.check("front wins hit test", LayerTree.hitTest(VPoint(x: 70, y: 70), in: stack) == knobID)
    LayerTree.reorder(knobID, towardFront: false, in: &stack)
    c.check("reorder toward back", stack[1].id == knobID)

    // MARK: Code generation
    do {
        let button = Layer(name: "Play", kind: .button,
                           frame: VRect(x: 20, y: 40, width: 120, height: 44),
                           style: LayerStyle(backgroundColor: VColor(hex: "#3478F6"),
                                             foregroundColor: .white, cornerRadius: 8),
                           text: "Play",
                           binding: CodeBinding(filePath: "UI.swift", anchorID: "playButton"))
        let panel = Layer(name: "Transport", kind: .panel,
                          frame: VRect(x: 0, y: 0, width: 320, height: 120), children: [button])
        let src = (try? CodeGenService().generate(Document(name: "Synth", roots: [panel])).contents) ?? ""
        c.check("codegen import", src.contains("import SwiftUI"))
        c.check("codegen struct", src.contains("struct GeneratedView: View"))
        c.check("codegen anchor", src.contains(".accessibilityIdentifier(\"playButton\")"))
        c.check("codegen text", src.contains("Text(\"Play\")"))
        c.check("codegen balanced braces", src.filter { $0 == "{" }.count == src.filter { $0 == "}" }.count)
    }

    // MARK: Validation
    let label = Layer(name: "Faint", kind: .label,
                      frame: VRect(x: 0, y: 0, width: 100, height: 20),
                      style: LayerStyle(backgroundColor: VColor(hex: "#EEEEEE"),
                                        foregroundColor: VColor(hex: "#DDDDDD")),
                      text: "Hi")
    let report = ValidationService().validate(Document(roots: [label]))
    c.check("contrast flagged", report.issues.contains { $0.category == .contrast })
    c.check("AA black/white", WCAG.passesAA(WCAG.contrastRatio(.black, .white), largeText: false))

    // MARK: Constraints
    var pinned = Layer(name: "Pinned", kind: .panel, frame: VRect(x: 0, y: 0, width: 50, height: 50))
    pinned.constraints = [LayerConstraint(edge: .leading, constant: 10),
                          LayerConstraint(edge: .trailing, constant: 10)]
    let solved = ConstraintSolver().resolveFrame(for: pinned, in: VSize(width: 200, height: 100))
    c.check("constraint stretches width", solved.origin.x == 10 && solved.width == 180)

    // MARK: Responsive
    let rRoot = Layer(name: "R", kind: .panel, frame: VRect(x: 0, y: 0, width: 100, height: 100))
    let adapted = ResponsiveEngine().adapt([rRoot], from: VSize(width: 100, height: 100), to: VSize(width: 200, height: 100))
    c.check("responsive scales", adapted[0].frame.width == 200 && adapted[0].frame.height == 100)
    c.check("size class", SizeClass.classify(width: 1000) == .large)

    // MARK: Preview render model
    let pChild = Layer(name: "C", kind: .label, frame: VRect(x: 5, y: 5, width: 10, height: 10))
    let pRoot = Layer(name: "R", kind: .panel, frame: VRect(x: 20, y: 20, width: 50, height: 50), children: [pChild])
    let model = PreviewBuilder().build(Document(roots: [pRoot]))
    c.check("render node count", model.nodes.count == 2)
    c.check("render absolute offset", model.nodes.first { $0.layer.name == "C" }?.absoluteFrame.origin == VPoint(x: 25, y: 25))

    // MARK: AI adapter (suggestions only)
    let aiDoc = Document(roots: [Layer(name: "Button", kind: .button, text: "OK")])
    let suggestions = (try? await HeuristicAdapter().suggest(SuggestionRequest(document: aiDoc))) ?? []
    c.check("ai naming suggestion", suggestions.contains { $0.kind == .naming })

    // MARK: Repository round-trip (SwiftSyntax)
    let viewSource = """
    import SwiftUI

    struct DemoView: View {
        var body: some View {
            ZStack(alignment: .topLeading) {
                // The title of the panel.
                Text("Title")
                    .font(.system(size: 22))
                    .frame(width: 200, height: 28)
                    .position(x: 120, y: 40)
                    .accessibilityIdentifier("titleLabel")
                Button("Play") {}
                    .frame(width: 120, height: 44)
                    .position(x: 80, y: 120)
                    .accessibilityIdentifier("playButton")
            }
        }
    }
    """
    let parsed = SwiftUIParser().parse(source: viewSource, filePath: "Demo.swift")
    c.check("parse one view", parsed.count == 1)
    let parsedLayers = parsed.first?.roots.flatMap { $0.flattened() } ?? []
    c.check("parse anchors", parsedLayers.contains { $0.binding?.anchorID == "titleLabel" }
            && parsedLayers.contains { $0.binding?.anchorID == "playButton" })
    if let play = parsedLayers.first(where: { $0.binding?.anchorID == "playButton" }) {
        // position x:80, width 120 → origin.x 20
        c.check("parse explicit position", abs(play.frame.origin.x - 20) < 0.5 && abs(play.frame.width - 120) < 0.5)
    } else {
        c.check("parse explicit position", false)
    }

    let rewritten = (try? SourceFidelityWriter().updatePositions(
        in: viewSource, changes: ["playButton": VRect(x: 200, y: 300, width: 120, height: 44)])) ?? ""
    c.check("round-trip new position", rewritten.contains(".position(x: 260, y: 322)"))
    c.check("round-trip preserves comment", rewritten.contains("// The title of the panel."))
    c.check("round-trip preserves other node", rewritten.contains(".position(x: 120, y: 40)"))
    let reparsed = SwiftUIParser().parse(source: rewritten, filePath: "Demo.swift")
        .first?.roots.flatMap { $0.flattened() } ?? []
    if let play2 = reparsed.first(where: { $0.binding?.anchorID == "playButton" }) {
        c.check("round-trip reparse origin", abs(play2.frame.origin.x - 200) < 0.5 && abs(play2.frame.origin.y - 300) < 0.5)
    } else {
        c.check("round-trip reparse origin", false)
    }

    // MARK: Safe-apply pipeline (real file IO + git diff)
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("vua-pipeline-\(UUID().uuidString)")
    try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }
    let viewFile = tmp.appendingPathComponent("View.swift")
    try? viewSource.write(to: viewFile, atomically: true, encoding: .utf8)
    // Init a git repo so the diff stage exercises GitEngine.
    func git(_ args: [String]) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git"] + args; p.currentDirectoryURL = tmp
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
    }
    git(["init", "-q"]); git(["add", "."]); git(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init"])

    // Build a document whose bound layer maps to "View.swift" → "playButton",
    // moved to a new frame, and run the pipeline.
    let movedButton = Layer(name: "Play", kind: .button,
                            frame: VRect(x: 200, y: 300, width: 120, height: 44),
                            text: "Play",
                            binding: CodeBinding(filePath: "View.swift", anchorID: "playButton"))
    let pipelineDoc = Document(roots: [movedButton])
    if let result = try? SafeApplyPipeline().apply(document: pipelineDoc, repoRoot: tmp, runBuild: false) {
        c.check("pipeline succeeded", result.succeeded)
        c.check("pipeline wrote file", result.filesWritten == ["View.swift"])
        c.check("pipeline produced diff", result.diff.contains(".position(x: 260, y: 322)"))
        let onDisk = (try? String(contentsOf: viewFile, encoding: .utf8)) ?? ""
        c.check("pipeline file updated", onDisk.contains(".position(x: 260, y: 322)"))
        c.check("pipeline preserved comment", onDisk.contains("// The title of the panel."))
    } else {
        c.check("pipeline succeeded", false)
    }

    // MARK: Phase 26 — advanced SwiftUI round-trip
    let roundTripDir = fm.temporaryDirectory.appendingPathComponent("vua-p26-\(UUID().uuidString)")
    try? fm.createDirectory(at: roundTripDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: roundTripDir) }
    let roundTripFile = roundTripDir.appendingPathComponent("RoundTrip.swift")
    let roundTripSource = """
    import SwiftUI

    struct RoundTrip: View {
        var body: some View {
            VStack {
                // VUA_UNSUPPORTED: custom animation logic owned by app code
                Text("Keep")
                    .frame(width: 80, height: 20)
                    .position(x: 40, y: 20)
                    .accessibilityIdentifier("keepLabel")
            }
        }
    }
    """.replacingOccurrences(of: "\n", with: "\r\n")
    try? roundTripSource.write(to: roundTripFile, atomically: true, encoding: .utf8)
    let roundTripLayer = Layer(name: "Keep", kind: .label,
                               frame: VRect(x: 20, y: 40, width: 90, height: 24),
                               text: "Keep",
                               binding: CodeBinding(filePath: "RoundTrip.swift", anchorID: "keepLabel"))
    let roundTripDoc = Document(roots: [roundTripLayer])
    if let preview = try? SafeApplyPipeline().preview(document: roundTripDoc, repoRoot: roundTripDir) {
        let stillOriginal = (try? String(contentsOf: roundTripFile, encoding: .utf8)) ?? ""
        c.check("p26 preview does not write", stillOriginal == roundTripSource)
        c.check("p26 preview diff contains partial update", preview.previewOnly && preview.diff.contains("@@ line"))
        c.check("p26 preview planned anchor line", preview.plannedChanges.contains { $0.contains("RoundTrip.swift:") && $0.contains("keepLabel") })
        c.check("p26 unsupported region surfaced", preview.unsupportedRegions.contains { $0.contains("VUA_UNSUPPORTED") })
    } else {
        c.check("p26 preview does not write", false)
        c.check("p26 preview diff contains partial update", false)
        c.check("p26 preview planned anchor line", false)
        c.check("p26 unsupported region surfaced", false)
    }
    if let applied = try? SafeApplyPipeline().apply(document: roundTripDoc, repoRoot: roundTripDir, runBuild: false) {
        let updated = (try? String(contentsOf: roundTripFile, encoding: .utf8)) ?? ""
        c.check("p26 apply writes changed region", applied.filesWritten == ["RoundTrip.swift"] && updated.contains(".position(x: 65, y: 52)"))
        c.check("p26 preserves CRLF", updated.contains("\r\n"))
        c.check("p26 preserves unsupported code", updated.contains("custom animation logic owned by app code"))
    } else {
        c.check("p26 apply writes changed region", false)
        c.check("p26 preserves CRLF", false)
        c.check("p26 preserves unsupported code", false)
    }

    try? fm.removeItem(at: tmp)   // exit() skips defer; clean up explicitly.

    // MARK: Phase 3 — control metadata
    let meta = ControlMetadata(parameterID: "cutoff", minValue: 20, maxValue: 20000, defaultValue: 1000, unit: .hertz)
    c.check("control clamp", meta.clamp(50000) == 20000 && meta.clamp(-5) == 20)
    c.check("control normalized default", abs(meta.normalizedDefault - (980.0/19980.0)) < 0.0001)
    c.check("control unit symbol", ControlUnit.decibels.symbol == "dB")

    // MARK: Phase 3 — codegen for plugin controls
    var knob = Layer(name: "Cutoff", kind: .knob,
                     frame: VRect(x: 0, y: 0, width: 64, height: 64),
                     binding: CodeBinding(filePath: "P.swift", anchorID: "cutoff"))
    knob.control = meta
    let knobSrc = (try? CodeGenService().generate(Document(roots: [knob])).contents) ?? ""
    c.check("codegen knob view", knobSrc.contains("KnobView(value:"))
    c.check("codegen AU param comment", knobSrc.contains("// AU param: cutoff"))
    c.check("codegen knob braces", knobSrc.filter { $0 == "{" }.count == knobSrc.filter { $0 == "}" }.count)

    // MARK: Phase 3 — image asset write-back
    let imageSource = """
    import SwiftUI
    struct Brand: View {
        var body: some View {
            ZStack {
                // brand mark
                Group {
                    Image(systemName: "photo").resizable()
                }
                .frame(width: 80, height: 80)
                .position(x: 60, y: 60)
                .accessibilityIdentifier("logo")
            }
        }
    }
    """
    let imageOut = (try? SourceFidelityWriter().updateImageNames(in: imageSource, changes: ["logo": "BrandLogo"])) ?? ""
    c.check("image write-back name", imageOut.contains("Image(\"BrandLogo\")"))
    c.check("image write-back preserves comment", imageOut.contains("// brand mark"))
    c.check("image write-back preserves frame", imageOut.contains(".frame(width: 80, height: 80)"))

    // MARK: Phase 3 — asset library
    let assets = [
        Asset(name: "PanelBG", path: "p.png", format: .png, tags: ["bg", "panel"]),
        Asset(name: "Knob", path: "k.svg", format: .svg, tags: ["control"])
    ]
    c.check("asset filter by tag", AssetLibrary.filter(assets, query: "bg").count == 1)
    c.check("asset filter by name", AssetLibrary.filter(assets, query: "knob").count == 1)
    c.check("asset all tags", AssetLibrary.allTags(assets) == ["bg", "control", "panel"])

    // MARK: Phase 4 — VUAControls library + codegen wiring
    c.check("codegen imports VUAControls", knobSrc.contains("import VUAControls"))
    c.check("codegen knob range", knobSrc.contains("in: 20...20000"))
    c.check("codegen knob label", knobSrc.contains("label: \"cutoff\""))
    // A plain view (no plugin controls) must NOT import the control library.
    let plainSrc = (try? CodeGenService().generate(Document(roots: [
        Layer(name: "T", kind: .label, frame: VRect(x: 0, y: 0, width: 50, height: 20), text: "Hi")
    ])).contents) ?? ""
    c.check("plain view skips control import", !plainSrc.contains("import VUAControls"))

    // ControlRange mapping (the library's value math).
    let cr = ControlRange(20, 20000)
    c.check("range normalize", abs(cr.normalize(20) - 0) < 0.0001 && abs(cr.normalize(20000) - 1) < 0.0001)
    c.check("range denormalize", abs(cr.denormalize(1) - 20000) < 0.0001)
    c.check("range clamp", cr.clamp(50000) == 20000)

    // MARK: Phase 4 — constraint solving (fixed size + edge pins)
    var fixed = Layer(name: "Fixed", kind: .panel, frame: VRect(x: 0, y: 0, width: 80, height: 40))
    fixed.constraints = [
        LayerConstraint(edge: .width, constant: 80, multiplier: 0),
        LayerConstraint(edge: .trailing, constant: 10)
    ]
    let fixedSolved = ConstraintSolver().resolveFrame(for: fixed, in: VSize(width: 300, height: 100))
    // width fixed at 80, pinned 10 from right → origin.x = 300 - 10 - 80 = 210
    c.check("constraint fixed width + trailing", fixedSolved.width == 80 && fixedSolved.origin.x == 210)

    // MARK: Phase 4 fix — asset resolution + placement pipeline
    let dir = URL(fileURLWithPath: "/tmp/vua-assets")
    let png = Asset(name: "Trinity8_BasePanel", path: "Trinity8_BasePanel.png", format: .png,
                    intrinsicSize: VSize(width: 2000, height: 1200))
    let resolved = AssetLibrary.fileURL(for: png, in: dir)
    c.check("asset url resolves under dir", resolved.path == "/tmp/vua-assets/Trinity8_BasePanel.png")

    // Placement: large image is scaled down but keeps aspect, frame non-zero.
    let place = AssetLibrary.placement(for: png, maxDimension: 320)
    c.check("placement non-zero", place.size.width > 0 && place.size.height > 0)
    c.check("placement capped", max(place.size.width, place.size.height) <= 320.5)
    c.check("placement aspect preserved",
            abs((place.size.width / place.size.height) - (2000.0/1200.0)) < 0.01)
    c.check("placement frame centered", place.frame(centeredOn: VPoint(x: 100, y: 100)).midX == 100)

    // Background-tagged asset → locked background placement.
    let bg = Asset(name: "Backplate", path: "bp.png", format: .png,
                   intrinsicSize: VSize(width: 800, height: 400), tags: ["background"])
    let bgPlace = AssetLibrary.placement(for: bg)
    c.check("bg placement is background+locked", bgPlace.isBackground && bgPlace.isLocked)

    // Real decode path: write a PNG, resolve its URL, load it (what the canvas
    // resolver does). Proves imported files actually become NSImages.
    let imgDir = fm.temporaryDirectory.appendingPathComponent("vua-img-\(UUID().uuidString)")
    try? fm.createDirectory(at: imgDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: imgDir) }
    let realPNG = Asset(name: "Probe", path: "probe.png", format: .png)
    let pngURL = AssetLibrary.fileURL(for: realPNG, in: imgDir)
    let madeImage = NSImage(size: NSSize(width: 8, height: 8))
    madeImage.lockFocus()
    NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: 8, height: 8).fill()
    madeImage.unlockFocus()
    if let tiff = madeImage.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: pngURL)
    }
    let loaded = NSImage(contentsOf: pngURL)
    c.check("png decodes to image", loaded != nil && (loaded?.size.width ?? 0) > 0)
    c.check("missing file is detected", !fm.fileExists(atPath: AssetLibrary.fileURL(for: Asset(name: "x", path: "nope.png", format: .png), in: imgDir).path))
    try? fm.removeItem(at: imgDir)

    // MARK: Phase 5 — Export Integrity Pipeline
    do {
        // Generated-code scanner: image refs + imports + library usage.
        let snippet = """
        import SwiftUI
        import VUAControls
        struct V: View {
            var body: some View {
                ZStack {
                    Image("Trinity8_BasePanel").resizable()
                    Image("Trinity8_Keybed").resizable()
                    Image(systemName: "photo")
                    KnobView(value: .constant(0.5), in: 0...1, label: "cutoff")
                }
            }
        }
        """
        let refs = GeneratedCodeScanner.imageReferences(in: snippet)
        c.check("scanner finds image names", refs.contains("Trinity8_BasePanel") && refs.contains("Trinity8_Keybed"))
        c.check("scanner skips systemName", !refs.contains("photo"))
        c.check("scanner detects controls", GeneratedCodeScanner.usesControlsLibrary(in: snippet))
        c.check("scanner finds imports", Set(GeneratedCodeScanner.imports(in: snippet)) == ["SwiftUI", "VUAControls"])

        // Asset planner sanitises unsafe filenames.
        let safe = AssetPlanner.sanitize("Trinity8/Base*Panel?", extensionFallback: "png")
        c.check("filename sanitised", safe == "Trinity8_Base_Panel_.png")

        // Parameter placeholder detection.
        let meta = ControlMetadata(parameterID: "cutoff", displayName: "cutoff",
                                   minValue: 0, maxValue: 1, defaultValue: 0)
        c.check("placeholder detected", ParameterPlanner.isPlaceholder(meta))
        let reviewed = ControlMetadata(parameterID: "filter_cutoff", displayName: "Filter Cutoff",
                                       minValue: 20, maxValue: 20000, defaultValue: 1200)
        c.check("non-placeholder ok", !ParameterPlanner.isPlaceholder(reviewed))

        // End-to-end: export a synth panel into a temp dir, including a real PNG
        // referenced by an image layer, and verify the export package builds
        // outside Visual UI Architect via `swift build`.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let assetsDir = appSupport.appendingPathComponent("VisualUIArchitect/Assets")
        try? fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        // Write a real PNG into the resolver's expected location.
        let basePanelURL = assetsDir.appendingPathComponent("Trinity8_BasePanel.png")
        let img = NSImage(size: NSSize(width: 16, height: 8))
        img.lockFocus(); NSColor.brown.setFill(); NSRect(x: 0, y: 0, width: 16, height: 8).fill(); img.unlockFocus()
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: basePanelURL)
        }

        let asset = Asset(name: "Trinity8_BasePanel", path: "Trinity8_BasePanel.png",
                          format: .png, intrinsicSize: VSize(width: 16, height: 8))
        var knob2 = Layer(name: "Cutoff", kind: .knob,
                          frame: VRect(x: 80, y: 80, width: 64, height: 64),
                          binding: CodeBinding(filePath: "G.swift", anchorID: "cutoff"))
        knob2.control = ControlMetadata(parameterID: "filter_cutoff", displayName: "Filter Cutoff",
                                        minValue: 20, maxValue: 20000, defaultValue: 1200, unit: .hertz)
        let backplate = Layer(name: "Backplate", kind: .background,
                              frame: VRect(x: 0, y: 0, width: 320, height: 200),
                              assetID: asset.id, isLocked: true,
                              binding: CodeBinding(filePath: "G.swift", anchorID: "backplate"))
        let doc = Document(name: "Trinity8", roots: [backplate, knob2], assets: [asset])

        let exportDir = fm.temporaryDirectory.appendingPathComponent("vua-export-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: exportDir) }

        let result = try ExportIntegrityPipeline().export(
            document: doc,
            request: ExportRequest(destination: exportDir, viewName: "Trinity8View"))

        c.check("export wrote generated view", fm.fileExists(atPath: result.generatedCodePath.path))
        c.check("export wrote asset manifest", fm.fileExists(atPath: result.assetManifestPath.path))
        c.check("export wrote parameter manifest", fm.fileExists(atPath: result.parameterManifestPath.path))
        c.check("export wrote report", fm.fileExists(atPath: result.reportPath.path))
        c.check("export copied image asset", fm.fileExists(atPath: exportDir
            .appendingPathComponent("Sources/GeneratedUI/Resources/Trinity8_BasePanel.png").path))
        c.check("export bundles VUAControls", result.includedControlsLibrary &&
            fm.fileExists(atPath: exportDir.appendingPathComponent("Sources/VUAControls/KnobView.swift").path))
        c.check("export has Package.swift", fm.fileExists(atPath: exportDir.appendingPathComponent("Package.swift").path))
        c.check("export no errors", !result.hasErrors)
        c.check("export parameter manifest non-empty", !result.parameters.isEmpty)

        // The big one: build the exported package as a real SwiftPM project.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["swift", "build"]
        p.currentDirectoryURL = exportDir
        let outPipe = Pipe(); p.standardOutput = outPipe; p.standardError = outPipe
        do {
            try p.run(); p.waitUntilExit()
            let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let ok = p.terminationStatus == 0
            if !ok {
                FileHandle.standardError.write(Data("export build output:\n\(output)\n".utf8))
            }
            c.check("exported target builds with swift build", ok)
        } catch {
            c.check("exported target builds with swift build", false)
        }

        // Negative: missing-asset diagnostic when generated code references an
        // image name with no matching imported asset. Fed directly to the
        // planner so it doesn't depend on document/codegen plumbing.
        let badSnippet = """
        import SwiftUI
        struct V: View { var body: some View { Image("NotImported") } }
        """
        let badPlan = AssetPlanner.plan(generatedSource: badSnippet, document: Document(),
                                        assetsDirectory: fm.temporaryDirectory)
        c.check("missing asset emits diagnostic",
                badPlan.diagnostics.contains { $0.code == .unresolvedAssetReference })
    } catch {
        FileHandle.standardError.write(Data("export exception: \(error)\n".utf8))
        c.check("export pipeline exception", false)
    }

    // MARK: Phase 6 — Persistence (.vuaproj bundle round-trip)
    do {
        // Build a document with a real image asset, write it to a bundle, then
        // read it back and verify everything survived.
        let sourceAssetsDir = fm.temporaryDirectory.appendingPathComponent("vua-persist-src-\(UUID().uuidString)")
        try fm.createDirectory(at: sourceAssetsDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: sourceAssetsDir) }

        let pngURL2 = sourceAssetsDir.appendingPathComponent("Backplate.png")
        let img2 = NSImage(size: NSSize(width: 4, height: 4))
        img2.lockFocus(); NSColor.systemGreen.setFill(); NSRect(x: 0, y: 0, width: 4, height: 4).fill(); img2.unlockFocus()
        if let tiff = img2.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) {
            try data.write(to: pngURL2)
        }

        let savedAsset = Asset(name: "Backplate", path: "Backplate.png", format: .png,
                               intrinsicSize: VSize(width: 4, height: 4), tags: ["bg"])
        let savedLayer = Layer(name: "Backplate", kind: .background,
                               frame: VRect(x: 0, y: 0, width: 200, height: 100),
                               assetID: savedAsset.id, isLocked: true)
        let savedDoc = Document(name: "PersistMe", roots: [savedLayer], assets: [savedAsset])

        let bundleURL = fm.temporaryDirectory
            .appendingPathComponent("Persist-\(UUID().uuidString).\(VUABundle.fileExtension)")
        defer { try? fm.removeItem(at: bundleURL) }

        let copied = try VUABundle.write(savedDoc, to: bundleURL, copyingAssetsFrom: sourceAssetsDir)
        c.check("bundle wrote document.json", fm.fileExists(atPath: VUABundle.documentFile(in: bundleURL).path))
        c.check("bundle copied asset", copied == ["Backplate.png"] &&
                fm.fileExists(atPath: VUABundle.assetsDirectory(in: bundleURL).appendingPathComponent("Backplate.png").path))

        let restored = try VUABundle.read(from: bundleURL)
        c.check("bundle round-trip name", restored.name == savedDoc.name)
        c.check("bundle round-trip layer count", restored.allLayers.count == savedDoc.allLayers.count)
        c.check("bundle round-trip asset survives", restored.assets.first?.name == "Backplate")
        c.check("bundle round-trip layer asset link",
                restored.roots.first?.assetID == savedDoc.roots.first?.assetID)

        // Wrong extension: read should refuse rather than fall through.
        let badURL = fm.temporaryDirectory.appendingPathComponent("Persist-\(UUID().uuidString).notabundle")
        try fm.createDirectory(at: badURL, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: badURL) }
        var refused = false
        do { _ = try VUABundle.read(from: badURL) } catch { refused = true }
        c.check("bundle refuses wrong extension", refused)

        // Idempotent write: writing a doc back into its existing bundle is a no-op.
        let secondCopy = try VUABundle.write(restored, to: bundleURL,
                                             copyingAssetsFrom: VUABundle.assetsDirectory(in: bundleURL))
        c.check("bundle idempotent write", secondCopy == ["Backplate.png"])

        // Recent-documents store (use an isolated UserDefaults so we don't
        // pollute the user's app).
        let suiteName = "vua.check.recents.\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        defer { isolated.removePersistentDomain(forName: suiteName) }
        let recents = RecentDocumentsStore(defaults: isolated, maxCount: 3)
        recents.record(bundleURL)
        let canonical = bundleURL.standardizedFileURL.path
        c.check("recents records url", recents.recents.first?.standardizedFileURL.path == canonical)
        c.check("recents lastOpened set", recents.lastOpened?.standardizedFileURL.path == canonical)
        c.check("recents most recent existing", recents.mostRecentExisting()?.standardizedFileURL.path == canonical)
        // Dedup + cap.
        recents.record(URL(fileURLWithPath: "/tmp/a.\(VUABundle.fileExtension)"))
        recents.record(URL(fileURLWithPath: "/tmp/b.\(VUABundle.fileExtension)"))
        recents.record(URL(fileURLWithPath: "/tmp/c.\(VUABundle.fileExtension)"))
        c.check("recents capped to maxCount", recents.recents.count == 3)
        recents.record(bundleURL)
        recents.record(bundleURL)
        c.check("recents dedupes",
                recents.recents.filter { $0.standardizedFileURL.path == canonical }.count == 1)
    } catch {
        FileHandle.standardError.write(Data("persistence exception: \(error)\n".utf8))
        c.check("persistence pipeline exception", false)
    }

    // MARK: Phase 7 — shapes / lines / polygons / gradients / groups / masks
    do {
        func gen(_ doc: Document) -> String { (try? CodeGenService().generate(doc).contents) ?? "" }
        func balanced(_ s: String) -> Bool { s.filter { $0 == "{" }.count == s.filter { $0 == "}" }.count }

        let rectSrc = gen(Document(roots: [Layer(name: "R", kind: .shape(.rectangle),
            frame: VRect(x: 0, y: 0, width: 40, height: 40),
            style: LayerStyle(backgroundColor: VColor(hex: "#FF0000")))]))
        c.check("codegen shape rectangle", rectSrc.contains("Rectangle()") && rectSrc.contains(".fill(") && balanced(rectSrc))

        let ellSrc = gen(Document(roots: [Layer(name: "E", kind: .shape(.ellipse),
            frame: VRect(x: 0, y: 0, width: 40, height: 40), style: LayerStyle(backgroundColor: .white))]))
        c.check("codegen shape ellipse", ellSrc.contains("Ellipse()"))

        let lineSrc = gen(Document(roots: [Layer(name: "L", kind: .line,
            frame: VRect(x: 0, y: 0, width: 100, height: 2),
            line: LineSpec(start: VPoint(x: 0, y: 1), end: VPoint(x: 100, y: 1), dashed: true))]))
        c.check("codegen line path", lineSrc.contains("Path { path in") && lineSrc.contains("addLine(to:") && lineSrc.contains("dash:"))

        let polySrc = gen(Document(roots: [Layer(name: "P", kind: .polygon,
            frame: VRect(x: 0, y: 0, width: 80, height: 80),
            style: LayerStyle(backgroundColor: VColor(hex: "#00FF00")),
            polygon: PolygonSpec(sides: 6))]))
        c.check("codegen polygon path", polySrc.contains("path.move(to:") && polySrc.contains("closeSubpath()") && balanced(polySrc))

        let gradSrc = gen(Document(roots: [Layer(name: "G", kind: .gradient,
            frame: VRect(x: 0, y: 0, width: 100, height: 60),
            style: LayerStyle(gradient: GradientSpec()))]))
        c.check("codegen gradient", gradSrc.contains("LinearGradient(") && gradSrc.contains("Gradient.Stop("))

        let group = Layer(name: "Grp", kind: .group, frame: VRect(x: 0, y: 0, width: 120, height: 80),
            children: [Layer(name: "Child", kind: .label, frame: VRect(x: 10, y: 10, width: 60, height: 20), text: "Hi",
                             binding: CodeBinding(filePath: "G.swift", anchorID: "child"))])
        let grpSrc = gen(Document(roots: [group]))
        c.check("codegen group nests children", grpSrc.contains("ZStack(alignment: .topLeading)") &&
                grpSrc.contains(".accessibilityIdentifier(\"child\")") && balanced(grpSrc))

        let maskedSrc = gen(Document(roots: [Layer(name: "M", kind: .image,
            frame: VRect(x: 0, y: 0, width: 80, height: 80), clipShape: .ellipse)]))
        c.check("codegen clipShape mask", maskedSrc.contains(".clipShape(Ellipse())"))

        // Clone (copy/paste): unique ids, children preserved, binding dropped.
        let clone = LayerTree.cloneWithNewIDs(group)
        c.check("clone new id", clone.id != group.id)
        c.check("clone preserves children", clone.children.count == 1 && clone.children[0].id != group.children[0].id)
        c.check("clone drops binding", clone.children[0].binding == nil)

        // Group / ungroup on a root collection.
        var roots: [Layer] = [
            Layer(name: "A", kind: .shape(.rectangle), frame: VRect(x: 0, y: 0, width: 40, height: 40)),
            Layer(name: "B", kind: .shape(.ellipse), frame: VRect(x: 60, y: 0, width: 40, height: 40))
        ]
        let gid = LayerTree.group([roots[0].id, roots[1].id], in: &roots)
        c.check("group wraps two layers", roots.count == 1 && roots[0].kind.isGroupLike && roots[0].children.count == 2)
        if let gid { let lifted = LayerTree.ungroup(gid, in: &roots); c.check("ungroup lifts children", lifted.count == 2 && roots.count == 2) }
        else { c.check("ungroup lifts children", false) }

        // Z-order: bring to front / send to back among siblings.
        var z: [Layer] = [Layer(name: "back", kind: .label), Layer(name: "mid", kind: .label), Layer(name: "front", kind: .label)]
        let backID = z[0].id
        LayerTree.bringToFront(backID, in: &z)
        c.check("bringToFront", z.last?.id == backID)
        LayerTree.sendToBack(backID, in: &z)
        c.check("sendToBack", z.first?.id == backID)

        // Validation extensions.
        let badDoc = Document(roots: [
            Layer(name: "Zero", kind: .shape(.rectangle), frame: VRect(x: 0, y: 0, width: 0, height: 20)),
            Layer(name: "BadPoly", kind: .polygon, frame: VRect(x: 0, y: 0, width: 40, height: 40), polygon: PolygonSpec(sides: 6, starInnerRatio: 1.5)),
            Layer(name: "Ghost", kind: .image, frame: VRect(x: 0, y: 0, width: 20, height: 20), assetID: UUID())
        ])
        let report7 = ValidationService().validate(badDoc)
        c.check("validation zero size", report7.issues.contains { $0.category == .structure && $0.message.contains("zero size") })
        c.check("validation invalid polygon", report7.issues.contains { $0.category == .structure && $0.message.contains("invalid polygon") })
        c.check("validation missing asset", report7.issues.contains { $0.category == .asset })

        // Presets.
        c.check("preset library populated", PresetLibrary.all.count >= 20)
        if let osc = PresetLibrary.preset(id: "plugin.oscillator") {
            let built = osc.build(VPoint(x: 0, y: 0))
            c.check("preset builds subtree", built.kind.isGroupLike && built.children.count >= 3)
        } else { c.check("preset builds subtree", false) }

        // End-to-end export of a shapes+gradient+group doc → swift build it.
        let exportDoc = Document(name: "ShapesUI", roots: [
            Layer(name: "BG", kind: .gradient, frame: VRect(x: 0, y: 0, width: 320, height: 200),
                  style: LayerStyle(gradient: GradientSpec()),
                  binding: CodeBinding(filePath: "G.swift", anchorID: "bg")),
            Layer(name: "Card", kind: .shape(.roundedRectangle), frame: VRect(x: 40, y: 40, width: 200, height: 100),
                  style: LayerStyle(backgroundColor: VColor(hex: "#2C2C2E"), cornerRadius: 12, shadow: ShadowSpec()),
                  binding: CodeBinding(filePath: "G.swift", anchorID: "card")),
            Layer(name: "Star", kind: .shape(.star), frame: VRect(x: 120, y: 60, width: 40, height: 40),
                  style: LayerStyle(backgroundColor: VColor(hex: "#FFD60A")),
                  binding: CodeBinding(filePath: "G.swift", anchorID: "star"))
        ])
        let exDir = fm.temporaryDirectory.appendingPathComponent("vua-p7-export-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: exDir) }
        let exResult = try ExportIntegrityPipeline().export(
            document: exportDoc, request: ExportRequest(destination: exDir, viewName: "ShapesView", includeControlsLibrary: false))
        c.check("p7 export no errors", !exResult.hasErrors)
        let bp = Process()
        bp.executableURL = URL(fileURLWithPath: "/usr/bin/env"); bp.arguments = ["swift", "build"]
        bp.currentDirectoryURL = exDir
        let bpipe = Pipe(); bp.standardOutput = bpipe; bp.standardError = bpipe
        try bp.run(); bp.waitUntilExit()
        let bout = String(data: bpipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if bp.terminationStatus != 0 { FileHandle.standardError.write(Data("p7 export build:\n\(bout)\n".utf8)) }
        c.check("p7 exported shapes/gradient builds", bp.terminationStatus == 0)
    } catch {
        FileHandle.standardError.write(Data("phase7 exception: \(error)\n".utf8))
        c.check("phase7 exception", false)
    }

    // MARK: Phase 8 — canvas workflow math
    c.check("grid snap value", CanvasGrid.snap(13, spacing: 8) == 16 && CanvasGrid.snap(3, spacing: 8) == 0)
    c.check("grid snap no-op", CanvasGrid.snap(13, spacing: 0) == 13)
    c.check("grid snap rect origin", CanvasGrid.snap(VRect(x: 13, y: 5, width: 40, height: 40), spacing: 8).origin == VPoint(x: 16, y: 8))

    // Fit zoom: 320×200 content into 800×600 viewport (padding 40) → limited by width.
    let fit = CanvasViewport.fitZoom(content: VSize(width: 320, height: 200), viewport: VSize(width: 800, height: 600))
    c.check("fit zoom limited dimension", abs(fit - (520.0 / 200.0)) < 0.001 || abs(fit - (720.0 / 320.0)) < 0.001)
    c.check("fit zoom clamped", CanvasViewport.fitZoom(content: VSize(width: 1, height: 1), viewport: VSize(width: 10000, height: 10000)) <= CanvasViewport.maxZoom)
    c.check("zoom clamp bounds", CanvasViewport.clampZoom(100) == CanvasViewport.maxZoom && CanvasViewport.clampZoom(0.001) == CanvasViewport.minZoom)

    // Ruler ticks: nice step, monotonic, covers range.
    let ticks = CanvasRuler.ticks(lengthPoints: 1000, zoom: 1)
    c.check("ruler ticks start at 0", ticks.first == 0)
    c.check("ruler ticks ascend", zip(ticks, ticks.dropFirst()).allSatisfy { $0 < $1 })
    c.check("ruler nice step", CanvasRuler.niceStep(atLeast: 60) == 100 && CanvasRuler.niceStep(atLeast: 12) == 20)

    // Alignment guide detection: moving rect whose left edge is 4pt from a sibling left.
    let ag = AlignmentGuides.detect(
        moving: VRect(x: 104, y: 0, width: 50, height: 50),
        siblings: [VRect(x: 100, y: 200, width: 50, height: 50)])
    c.check("alignment guide snaps left edge", abs(ag.snappedDelta.x - (-4)) < 0.001)
    c.check("alignment guide reports vertical", ag.verticals.contains(100))

    // MARK: Phase 9 — document safety (snapshots / recovery / diagnostics)
    do {
        let bundle = fm.temporaryDirectory.appendingPathComponent("Safe-\(UUID().uuidString).\(VUABundle.fileExtension)")
        defer { try? fm.removeItem(at: bundle) }
        let doc = Document(name: "SafeDoc", roots: [Layer(name: "L", kind: .label, text: "Hi")])
        try VUABundle.write(doc, to: bundle, copyingAssetsFrom: nil)

        // Snapshots: write two at distinct times, list newest-first, restore.
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let t1 = Date(timeIntervalSince1970: 1_000_060)
        _ = try SnapshotStore.write(doc, into: bundle, at: t0)
        var doc2 = doc; doc2.name = "SafeDoc v2"
        _ = try SnapshotStore.write(doc2, into: bundle, at: t1)
        let snaps = SnapshotStore.list(in: bundle)
        c.check("snapshots listed", snaps.count == 2)
        c.check("snapshots newest first", snaps.first!.date >= snaps.last!.date)
        let restored = try SnapshotStore.read(snaps.first!.url)
        c.check("snapshot restore decodes", restored.name == "SafeDoc v2")

        // Snapshot pruning keeps newest N.
        for i in 0..<5 { _ = try SnapshotStore.write(doc, into: bundle, at: Date(timeIntervalSince1970: 2_000_000 + Double(i))) }
        SnapshotStore.prune(in: bundle, keeping: 3)
        c.check("snapshot prune caps count", SnapshotStore.list(in: bundle).count == 3)

        // Recovery round-trip in an isolated directory.
        let recDir = fm.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: recDir) }
        let recovery = RecoveryStore(directory: recDir)
        c.check("recovery initially empty", !recovery.hasRecovery)
        try recovery.write(doc, originalPath: bundle.path, at: t1)
        c.check("recovery present after write", recovery.hasRecovery)
        let loaded = recovery.load()
        c.check("recovery loads document", loaded?.document.name == "SafeDoc")
        c.check("recovery keeps origin path", loaded?.meta.originalPath == bundle.path)
        recovery.clear()
        c.check("recovery cleared", !recovery.hasRecovery)

        // Corrupted-document diagnostics.
        c.check("diagnose healthy bundle", VUABundle.diagnose(bundle) == nil)
        let corrupt = fm.temporaryDirectory.appendingPathComponent("Corrupt-\(UUID().uuidString).\(VUABundle.fileExtension)")
        defer { try? fm.removeItem(at: corrupt) }
        try fm.createDirectory(at: corrupt, withIntermediateDirectories: true)
        try "{ not valid json".data(using: .utf8)!.write(to: VUABundle.documentFile(in: corrupt))
        c.check("diagnose corrupt bundle", VUABundle.diagnose(corrupt) != nil)
        let missingDoc = fm.temporaryDirectory.appendingPathComponent("Empty-\(UUID().uuidString).\(VUABundle.fileExtension)")
        defer { try? fm.removeItem(at: missingDoc) }
        try fm.createDirectory(at: missingDoc, withIntermediateDirectories: true)
        c.check("diagnose missing document", VUABundle.diagnose(missingDoc) != nil)
    } catch {
        FileHandle.standardError.write(Data("phase9 exception: \(error)\n".utf8))
        c.check("phase9 exception", false)
    }

    // MARK: Phase 9+ — recovery conflict classification + open-doc registry
    do {
        let bundle = fm.temporaryDirectory.appendingPathComponent("Conf-\(UUID().uuidString).\(VUABundle.fileExtension)")
        defer { try? fm.removeItem(at: bundle) }
        try VUABundle.write(Document(name: "C"), to: bundle, copyingAssetsFrom: nil)
        let savedMod = (try? VUABundle.documentFile(in: bundle).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let newer = RecoveryStore.Meta(savedAt: savedMod.addingTimeInterval(120), originalPath: bundle.path, documentName: "C")
        let older = RecoveryStore.Meta(savedAt: savedMod.addingTimeInterval(-120), originalPath: bundle.path, documentName: "C")
        let none = RecoveryStore.Meta(savedAt: Date(), originalPath: nil, documentName: "C")
        c.check("recovery newer-than-save", RecoveryStore.classify(meta: newer) == .recoveryNewer)
        c.check("recovery older-than-save", RecoveryStore.classify(meta: older) == .recoveryOlder)
        c.check("recovery no-saved-file", RecoveryStore.classify(meta: none) == .noSavedFile)

        let reg = OpenDocumentRegistry()
        c.check("registry opens once", reg.register(bundle) == true)
        c.check("registry detects duplicate", reg.register(bundle) == false && reg.isOpen(bundle))
        reg.unregister(bundle)
        c.check("registry unregister", !reg.isOpen(bundle))
    } catch {
        FileHandle.standardError.write(Data("p9+ exception: \(error)\n".utf8))
        c.check("p9+ exception", false)
    }

    // MARK: Phase 10 — workspace safety resolver
    do {
        let resolver = WorkspaceResolver()
        // The project's own repo: a real git repo with a Package.swift.
        let repoCtx = resolver.resolve(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        // (currentDirectoryPath under `swift run` is the package root.)
        c.check("workspace finds package", repoCtx.packageManifests.count >= 1)

        // A generated export folder should be flagged and unsafe to write.
        let gen = fm.temporaryDirectory.appendingPathComponent("gen-\(UUID().uuidString)")
        try fm.createDirectory(at: gen, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: gen) }
        try "# Export Report".data(using: .utf8)!.write(to: gen.appendingPathComponent("EXPORT_REPORT.md"))
        let genCtx = resolver.resolve(gen)
        c.check("workspace flags generated export", genCtx.looksLikeGeneratedExport && !genCtx.isSafeToWrite)
        c.check("workspace generated has error warning",
                genCtx.warnings.contains { $0.code == .generatedExportFolder && $0.severity == .error })

        // A build folder should be flagged unsafe.
        let buildDir = fm.temporaryDirectory.appendingPathComponent("proj-\(UUID().uuidString)/.build")
        try fm.createDirectory(at: buildDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: buildDir.deletingLastPathComponent()) }
        c.check("workspace flags build folder", !resolver.resolve(buildDir).isSafeToWrite)

        // Nested-repo detection.
        let outer = fm.temporaryDirectory.appendingPathComponent("outer-\(UUID().uuidString)")
        try fm.createDirectory(at: outer.appendingPathComponent("inner/.git"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outer) }
        c.check("workspace detects nested repo", !resolver.resolve(outer).nestedGitRepos.isEmpty)

        // Confidence: clean empty temp folder should outscore a generated export.
        c.check("workspace confidence ordering", resolver.resolve(outer).confidence > genCtx.confidence)
    } catch {
        FileHandle.standardError.write(Data("p10 exception: \(error)\n".utf8))
        c.check("p10 exception", false)
    }

    // MARK: Phase 11 — build intelligence
    do {
        let inspector = BuildInspector()

        // Build command formatting.
        c.check("build command debug", BuildInspector.buildCommand(kind: .debug) == ["swift", "build", "-c", "debug"])
        c.check("build command release product",
                BuildInspector.buildCommand(kind: .release, product: "App") == ["swift", "build", "-c", "release", "--product", "App"])
        c.check("build kind config mapping", BuildKind.production.configuration == "release" && BuildKind.ci.configuration == "debug")

        // Pipeline model: canonical order + stage updates.
        var pipe = BuildPipeline()
        c.check("pipeline order", pipe.entries.first?.stage == .workspaceResolve && pipe.entries.last?.stage == .artifact)
        pipe.set(.swiftBuild, .failed, note: "boom")
        c.check("pipeline failure tracking", pipe.failed && pipe.entries.first(where: { $0.stage == .swiftBuild })?.note == "boom")

        // Toolchain probe: must produce a Swift version on any machine that can run this harness.
        let tc = inspector.detectToolchain()
        c.check("toolchain swift version", tc.swiftVersion?.isEmpty == false)

        // Context on a folder without Package.swift → blocking diagnostic.
        let empty = fm.temporaryDirectory.appendingPathComponent("nopkg-\(UUID().uuidString)")
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: empty) }
        let noPkg = inspector.makeContext(root: empty, toolchain: tc)
        c.check("missing manifest diagnostic",
                noPkg.diagnostics.contains { $0.code == .missingPackageManifest && $0.severity == .error } && noPkg.hasBlockingIssue)

        // Package.resolved missing → info diagnostic; stale → warning.
        let pkgDir = fm.temporaryDirectory.appendingPathComponent("pkg-\(UUID().uuidString)")
        try fm.createDirectory(at: pkgDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: pkgDir) }
        try "// swift-tools-version: 6.0".data(using: .utf8)!.write(to: pkgDir.appendingPathComponent("Package.swift"))
        c.check("resolved missing diagnostic",
                inspector.makeContext(root: pkgDir, toolchain: tc).diagnostics.contains { $0.code == .packageResolvedMissing })
        try "{}".data(using: .utf8)!.write(to: pkgDir.appendingPathComponent("Package.resolved"))
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)],
                             ofItemAtPath: pkgDir.appendingPathComponent("Package.resolved").path)
        c.check("resolved stale diagnostic",
                inspector.makeContext(root: pkgDir, toolchain: tc).diagnostics.contains { $0.code == .packageResolvedStale })

        // Generated-source scanning.
        let clt = ToolchainInfo(swiftVersionLine: "Swift version 6.0", developerDir: "/Library/Developer/CommandLineTools", hasFullXcode: false)
        let badImport = inspector.scanGeneratedSource("import SwiftUI\nimport MysteryKit\n", knownModules: [], bundlesVUAControls: true, toolchain: clt)
        c.check("invalid generated import", badImport.contains { $0.code == .invalidGeneratedImport })
        let noControls = inspector.scanGeneratedSource("import VUAControls\n", knownModules: [], bundlesVUAControls: false, toolchain: clt)
        c.check("missing VUAControls diagnostic", noControls.contains { $0.code == .missingVUAControls && $0.severity == .error })
        let bundled = inspector.scanGeneratedSource("import VUAControls\n", knownModules: [], bundlesVUAControls: true, toolchain: clt)
        c.check("bundled VUAControls clean", !bundled.contains { $0.code == .missingVUAControls })
        let preview = inspector.scanGeneratedSource("#Preview { Text(\"hi\") }", knownModules: [], bundlesVUAControls: true, toolchain: clt)
        c.check("CLT #Preview diagnostic", preview.contains { $0.code == .previewMacroCLTIncompatible })

        // Failure explanations.
        c.check("explain no such module",
                BuildInspector.explainFailure("error: no such module 'VUAControls'")?.contains("VUAControls") == true)
        c.check("explain manifest error",
                BuildInspector.explainFailure("error: the manifest is invalid")?.lowercased().contains("package.swift") == true)
        c.check("explain unknown returns nil", BuildInspector.explainFailure("everything is fine") == nil)
    } catch {
        FileHandle.standardError.write(Data("p11 exception: \(error)\n".utf8))
        c.check("p11 exception", false)
    }

    // MARK: Phase 12 — source / asset / layer hardening
    do {
        let hardening = HardeningValidator()

        // Duplicate layer IDs + duplicate source anchors.
        var dupLayer = Layer(name: "A", kind: .label, frame: VRect(x: 0, y: 0, width: 10, height: 10))
        dupLayer.binding = CodeBinding(filePath: "V.swift", anchorID: "anchor1")
        var dupLayer2 = Layer(name: "B", kind: .label, frame: VRect(x: 20, y: 0, width: 10, height: 10))
        dupLayer2.binding = CodeBinding(filePath: "V.swift", anchorID: "anchor1")
        let dupDoc = Document(roots: [dupLayer, dupLayer, dupLayer2])
        let dupIssues = hardening.validate(dupDoc)
        c.check("duplicate layer ID detected", dupIssues.contains { $0.message.contains("IDs must be unique") && $0.severity == .error })
        c.check("duplicate anchor detected", dupIssues.contains { $0.message.contains("anchor1") && $0.severity == .error })

        // Off-canvas detection.
        let off = Layer(name: "Lost", kind: .panel, frame: VRect(x: -5000, y: -5000, width: 50, height: 50))
        c.check("off-canvas detected", hardening.validate(Document(roots: [off]))
            .contains { $0.message.contains("off-canvas") })

        // Fully-transparent gradient.
        var ghost = Layer(name: "Ghost", kind: .panel, frame: VRect(x: 0, y: 0, width: 100, height: 100))
        ghost.style.gradient = GradientSpec(stops: [
            GradientStop(color: VColor(red: 1, green: 0, blue: 0, alpha: 0), location: 0),
            GradientStop(color: VColor(red: 0, green: 0, blue: 1, alpha: 0), location: 1)])
        c.check("transparent gradient detected", hardening.validate(Document(roots: [ghost]))
            .contains { $0.message.contains("fully transparent") })

        // Asset collisions: exact, case-only, sanitised.
        let assetDoc = Document(roots: [], assets: [
            Asset(name: "Logo", path: "a.png", format: .png),
            Asset(name: "Logo", path: "b.png", format: .png),
            Asset(name: "logo", path: "c.png", format: .png),
            Asset(name: "My Image!", path: "d.png", format: .png),
            Asset(name: "my_image", path: "e.png", format: .png)
        ])
        let assetIssues = hardening.validate(assetDoc)
        c.check("duplicate asset name", assetIssues.contains { $0.message.contains("both named") && $0.severity == .error })
        c.check("case-only asset collision", assetIssues.contains { $0.message.contains("differ only by case") })
        c.check("sanitised asset collision", assetIssues.contains { $0.message.contains("sanitise to the same") })
        c.check("sanitiser", HardeningValidator.sanitised("My Image!") == "my_image")

        // Missing asset file on disk (absolute path).
        let gone = Document(roots: [], assets: [Asset(name: "Gone", path: "/nonexistent/\(UUID().uuidString).png", format: .png)])
        c.check("missing asset file", hardening.validate(gone).contains { $0.message.contains("missing on disk") })

        // Source preflight (pure-text inspection).
        let conflicted = "let a = 1\n<<<<<<< HEAD\nlet b = 2\n=======\nlet b = 3\n>>>>>>> branch\n"
        let confFindings = SourceSafety.inspect(source: conflicted, fileName: "F.swift")
        c.check("merge markers block", confFindings.contains { $0.code == .mergeConflictMarkers && $0.severity == .blocker })

        c.check("CRLF detected", SourceSafety.inspect(source: "a\r\nb\r\n", fileName: "F.swift")
            .contains { $0.code == .crlfLineEndings })
        c.check("tabs detected", SourceSafety.inspect(source: "\tlet a = 1\n", fileName: "F.swift")
            .contains { $0.code == .tabIndentation })

        // External modification (hash drift).
        let h = SourceSafety.hash(of: "original")
        c.check("hash stable", SourceSafety.hash(of: "original") == h)
        c.check("external change detected", SourceSafety.inspect(source: "edited", fileName: "F.swift", expectedHash: h)
            .contains { $0.code == .externallyModified && $0.severity == .blocker })

        // Anchor sanity in source text.
        let src = """
        Text("a").accessibilityIdentifier("dup")
        Text("b").accessibilityIdentifier("dup")
        Text("c").accessibilityIdentifier("solo")
        """
        c.check("anchor counts", SourceSafety.anchorCounts(in: src) == ["dup": 2, "solo": 1])
        let anchorFindings = SourceSafety.inspect(source: src, fileName: "F.swift", expectedAnchors: ["dup", "solo", "missing"])
        c.check("duplicate source anchor blocks", anchorFindings.contains { $0.code == .duplicateAnchors })
        c.check("missing source anchor blocks", anchorFindings.contains { $0.code == .missingAnchor })

        // File-level preflight: missing + read-only files.
        let missingURL = fm.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).swift")
        c.check("preflight missing file", SourceSafety().preflight(fileURL: missingURL).hasBlocker)
        let roURL = fm.temporaryDirectory.appendingPathComponent("ro-\(UUID().uuidString).swift")
        try "let x = 1\n".data(using: .utf8)!.write(to: roURL)
        try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: roURL.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: roURL.path); try? fm.removeItem(at: roURL) }
        c.check("preflight read-only file", SourceSafety().preflight(fileURL: roURL).findings
            .contains { $0.code == .notWritable && $0.severity == .blocker })
    } catch {
        FileHandle.standardError.write(Data("p12 exception: \(error)\n".utf8))
        c.check("p12 exception", false)
    }

    // MARK: Phase 13 — handoff generator
    do {
        let input = HandoffInput(
            repoPath: "/tmp/Example",
            branch: "main",
            latestCommit: "abc1234",
            workingTreeDirty: false,
            buildStatus: "clean",
            checkResult: "189 passed, 0 failed",
            modules: ["VUACore", "LayerEngine"],
            capabilities: ["Visual canvas editing"],
            documentName: "Demo",
            layerCount: 12,
            assetCount: 3,
            targetDevice: "MacBook Pro 14″",
            warnings: ["example warning"],
            knownLimitations: ["example limitation"],
            roadmap: ["Phase 14 — UI Quality Engine"],
            nextRecommendedPhase: "Phase 14")
        let gen = HandoffGenerator()
        let md = gen.generate(input, mode: .fullProject)

        c.check("handoff has mission", md.contains("local-first") && md.contains("Product mission"))
        c.check("handoff has build commands", md.contains("swift build") && md.contains("swift run VUACheck"))
        c.check("handoff has module list", md.contains("`VUACore`") && md.contains("`LayerEngine`"))
        c.check("handoff has safety rules", md.contains("Do not replace SwiftSyntax parsing with regex"))
        c.check("handoff has roadmap", md.contains("Phase 14 — UI Quality Engine"))
        c.check("handoff has commit", md.contains("abc1234") && md.contains("main"))
        c.check("handoff has check result", md.contains("189 passed, 0 failed"))
        c.check("handoff has recovery", md.contains("git log --oneline"))
        c.check("handoff has phase rule", md.contains("commit only when green"))
        c.check("handoff deterministic", md == gen.generate(input, mode: .fullProject))

        // Dirty-tree warning appears when (and only when) the tree is dirty.
        var dirty = input
        dirty.workingTreeDirty = true
        c.check("handoff dirty warning", gen.generate(dirty, mode: .fullProject).contains("DIRTY")
                && !md.contains("DIRTY"))

        // Bug-fix mode constrains scope and drops the capability inventory.
        let bugfix = gen.generate(input, mode: .bugFix)
        c.check("bugfix scope rule", bugfix.contains("No refactors"))
        c.check("bugfix omits capabilities", !bugfix.contains("do not rebuild"))
    }

    // MARK: Phase 14 — UI quality engine
    do {
        let qa = QualityAssessor()

        // Contrast: grey-on-grey text must be flagged; black-on-white must not.
        var lowText = Layer(name: "Faint", kind: .label, frame: VRect(x: 0, y: 0, width: 200, height: 20), text: "Hello")
        lowText.style.foregroundColor = VColor(hex: "#9A9A9A")
        lowText.style.backgroundColor = VColor(hex: "#8C8C8C")
        let lowReport = qa.assess(Document(roots: [lowText]))
        c.check("low contrast flagged", lowReport.issues.contains { $0.dimension == .contrast && $0.severity == .problem })
        var goodText = lowText
        goodText.style.foregroundColor = VColor(hex: "#000000")
        goodText.style.backgroundColor = VColor(hex: "#FFFFFF")
        c.check("good contrast clean", !qa.assess(Document(roots: [goodText])).issues.contains { $0.dimension == .contrast })
        c.check("contrast ratio maths", abs(QualityAssessor.contrastRatio(.white, .black) - 21) < 0.2)

        // Density: 35 controls trip the problem threshold.
        let many = (0..<35).map { i in
            Layer(name: "K\(i)", kind: .knob, frame: VRect(x: Double(i % 8) * 90, y: Double(i / 8) * 90, width: 64, height: 64))
        }
        c.check("density flagged", qa.assess(Document(roots: many)).issues.contains { $0.dimension == .density && $0.severity == .problem })

        // Tap targets: tiny button on iPhone flagged; same on Mac not.
        let tiny = Layer(name: "Tap", kind: .button, frame: VRect(x: 0, y: 0, width: 30, height: 24), text: "Go")
        var touchDoc = Document(roots: [tiny])
        if let phone = DeviceProfile.catalog.first(where: { $0.family == .iPhone }) {
            touchDoc.activeDevice = phone
            c.check("tap target flagged on touch", qa.assess(touchDoc).issues.contains { $0.message.contains("44") })
        } else {
            c.check("tap target flagged on touch", false)
        }
        var macDoc = Document(roots: [tiny])
        if let mac = DeviceProfile.catalog.first(where: { $0.family == .mac }) {
            macDoc.activeDevice = mac
            c.check("tap target ok on mac", !qa.assess(macDoc).issues.contains { $0.message.contains("44") })
        } else {
            c.check("tap target ok on mac", false)
        }

        // Icon-only button label warning.
        let iconOnly = Layer(name: "Gear", kind: .button, frame: VRect(x: 0, y: 0, width: 44, height: 44))
        c.check("icon-only button flagged", qa.assess(Document(roots: [iconOnly])).issues
            .contains { $0.dimension == .accessibility && $0.message.contains("no title") })

        // Text overflow: long copy in a narrow frame.
        let overflow = Layer(name: "Caption", kind: .label, frame: VRect(x: 0, y: 0, width: 60, height: 18),
                             text: "An extremely long caption that cannot possibly fit")
        c.check("overflow flagged", qa.assess(Document(roots: [overflow])).issues
            .contains { $0.dimension == .typography && $0.message.contains("truncate") })
        let url = Layer(name: "Link", kind: .label, frame: VRect(x: 0, y: 0, width: 80, height: 18),
                        text: "https://example.com/a/very/long/unbreakable/path/segment")
        c.check("unbreakable run flagged", qa.assess(Document(roots: [url])).issues
            .contains { $0.message.contains("unbreakable") })

        // Spacing: off-grid layers flagged.
        let offGrid = (0..<6).map { i in
            Layer(name: "P\(i)", kind: .panel, frame: VRect(x: Double(i) * 50 + 1.7, y: 3.3, width: 40, height: 40))
        }
        c.check("off-grid spacing flagged", qa.assess(Document(roots: offGrid)).issues.contains { $0.dimension == .spacing })

        // Visual noise: effects on everything.
        let noisy = (0..<10).map { i -> Layer in
            var l = Layer(name: "N\(i)", kind: .panel, frame: VRect(x: Double(i) * 48, y: 0, width: 40, height: 40))
            l.style.shadow = ShadowSpec()
            return l
        }
        let noisyReport = qa.assess(Document(roots: noisy))
        c.check("effect noise flagged", noisyReport.issues.contains { $0.dimension == .noise })

        // Scores: clean doc outscores noisy doc; grades map sanely.
        let clean = qa.assess(Document(roots: [goodText]))
        c.check("scores ordering", clean.scores.overall > noisyReport.scores.overall)
        c.check("grade mapping", QualityScores.grade(95) == "A" && QualityScores.grade(40) == "E")
    }

    // MARK: Phase 15 — Component System
    do {
        // Build a master from two real layers; instance must reference it.
        let label = Layer(name: "Title", kind: .label,
                          frame: VRect(x: 10, y: 10, width: 80, height: 18), text: "Hi")
        let panel = Layer(name: "Card", kind: .panel,
                          frame: VRect(x: 0, y: 0, width: 120, height: 60),
                          style: LayerStyle(backgroundColor: VColor(hex: "#2C2C2E"), cornerRadius: 10))
        let (component, instance) = try ComponentEngine.makeComponent(named: "BadgeCard", from: [panel, label])
        c.check("component creation", component.name == "BadgeCard")
        c.check("component master has children", component.master.children.count == 2)
        c.check("instance references master", instance.componentID == component.id)
        c.check("instance body cloned", instance.children.count == 2)
        c.check("instance child ids unique vs master",
                Set(instance.children.map { $0.id }).isDisjoint(with: Set(component.master.children.map { $0.id })))

        // Propagate master edits to instances.
        var doc = Document(roots: [instance], components: [component])
        var edited = component
        edited.master.children[0] = Layer(name: "BG", kind: .panel,
            frame: VRect(x: 0, y: 0, width: 200, height: 100),
            style: LayerStyle(backgroundColor: VColor(hex: "#FF3B30")))
        doc.components[0] = edited
        let propagated = ComponentEngine.propagateMaster(edited, in: &doc.roots)
        c.check("master propagates to instances", propagated == 1)
        // Master still has 2 children (we replaced child[0], didn't remove child[1]).
        c.check("instance body now matches master child count",
                doc.roots[0].children.count == edited.master.children.count)
        // Master frame is unchanged from creation (bounding box at make-time).
        c.check("instance frame syncs to master size",
                doc.roots[0].frame.size == edited.master.frame.size)

        // Detach stops propagation.
        let id = doc.roots[0].id
        _ = ComponentEngine.detach(id, in: &doc.roots)
        c.check("detach removes link", doc.roots[0].componentID == nil)
        let propagated2 = ComponentEngine.propagateMaster(edited, in: &doc.roots)
        c.check("detached instance not re-synced", propagated2 == 0)

        // Cycle detection: making a component reference itself is rejected.
        let selfCycle = ComponentEngine.wouldCreateCycle(insertingMaster: component.id,
                                                        intoMaster: component.id,
                                                        components: [component])
        c.check("self-cycle detected", selfCycle)

        // Indirect cycle: component A contains an instance of B, then B tries
        // to contain A.
        let bChild = Layer(name: "Stub", kind: .label, frame: VRect(x: 0, y: 0, width: 20, height: 20))
        let (compB, _) = try ComponentEngine.makeComponent(named: "B", from: [bChild])
        // Place an instance of A inside B's master.
        var compBWithA = compB
        compBWithA.master.children.append(ComponentEngine.makeInstance(of: component, at: .zero))
        let cycle = ComponentEngine.wouldCreateCycle(
            insertingMaster: compBWithA.id, intoMaster: component.id,
            components: [component, compBWithA])
        c.check("indirect cycle detected", cycle)

        // Missing master diagnostic.
        let orphan = Layer(name: "Orphan", kind: .group,
                           frame: VRect(x: 0, y: 0, width: 10, height: 10))
        var orphanDoc = Document(roots: [orphan])
        // Force a componentID pointing at nothing.
        let fakeID = UUID()
        orphanDoc.roots[0] = Layer(
            id: orphan.id, name: orphan.name, kind: orphan.kind, frame: orphan.frame,
            componentID: fakeID, children: orphan.children)
        let diag = ComponentEngine.diagnose(orphanDoc)
        c.check("missing master diagnostic", diag.contains { $0.code == .missingMaster })

        // Document backwards-compat: a JSON without `components` decodes to [].
        let oldJSON = #"""
        {
          "name": "Legacy",
          "roots": [],
          "assets": [],
          "activeDevice": {"id":"00000000-0000-0000-0000-000000000001","name":"Mac","family":"mac","portraitSize":{"width":1280,"height":800},"scale":2,"supportsLandscape":false},
          "activeOrientation": "portrait",
          "codeGenTarget": "swiftUI",
          "schemaVersion": 1
        }
        """#
        let legacy = try JSONDecoder().decode(Document.self, from: oldJSON.data(using: .utf8)!)
        c.check("legacy doc decodes with empty components", legacy.components.isEmpty)

        // Round-trip: a doc with a component re-encodes and decodes losslessly.
        let liveDoc = Document(name: "Live", roots: [instance], components: [component])
        let encoded = try JSONEncoder().encode(liveDoc)
        let decoded = try JSONDecoder().decode(Document.self, from: encoded)
        c.check("component round-trip preserves count", decoded.components.count == 1)
        c.check("component round-trip preserves id", decoded.components[0].id == component.id)
        c.check("instance link survives round-trip",
                decoded.roots[0].componentID == component.id)

        // Codegen: produce a component struct + instance call.
        let codeDoc = Document(name: "CodeGen", roots: [instance], components: [component])
        let src = (try? CodeGenService().generate(codeDoc).contents) ?? ""
        c.check("codegen emits component struct",
                src.contains("struct \(component.generatedTypeName): View"))
        c.check("codegen emits instance call",
                src.contains("\(component.generatedTypeName)()"))
        // Brace balance (cheap structural sanity).
        c.check("codegen braces balanced",
                src.filter { $0 == "{" }.count == src.filter { $0 == "}" }.count)

        // Real swift build of an exported component-bearing doc.
        let exDir = fm.temporaryDirectory.appendingPathComponent("vua-p15-export-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: exDir) }
        let exResult = try ExportIntegrityPipeline().export(
            document: codeDoc,
            request: ExportRequest(destination: exDir, viewName: "ComponentDemo", includeControlsLibrary: false))
        c.check("p15 export ok", !exResult.hasErrors)
        let bp = Process()
        bp.executableURL = URL(fileURLWithPath: "/usr/bin/env"); bp.arguments = ["swift", "build"]
        bp.currentDirectoryURL = exDir
        let bpipe = Pipe(); bp.standardOutput = bpipe; bp.standardError = bpipe
        try bp.run(); bp.waitUntilExit()
        if bp.terminationStatus != 0 {
            let bout = String(data: bpipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            FileHandle.standardError.write(Data("p15 export build:\n\(bout)\n".utf8))
        }
        c.check("p15 exported component builds with swift build", bp.terminationStatus == 0)

        // Cloning preserves componentID (so paste keeps the link).
        let clone = LayerTree.cloneWithNewIDs(instance)
        c.check("clone preserves componentID", clone.componentID == component.id)
        c.check("clone has fresh id", clone.id != instance.id)
    } catch {
        FileHandle.standardError.write(Data("p15 exception: \(error)\n".utf8))
        c.check("p15 exception", false)
    }

    // MARK: Phase 16 — Advanced control presets
    do {
        let all = ControlPresetLibrary.all
        c.check("control catalog total", all.count == 250)
        c.check("control catalog has knobs", ControlPresetLibrary.presets(in: .knob).count == 50)
        c.check("control catalog has faders", ControlPresetLibrary.presets(in: .fader).count == 50)
        c.check("control catalog has sliders", ControlPresetLibrary.presets(in: .slider).count == 50)
        c.check("control catalog has buttons", ControlPresetLibrary.presets(in: .button).count == 50)
        c.check("control catalog has toggles", ControlPresetLibrary.presets(in: .toggle).count == 50)

        // Unique ids and unique names.
        c.check("control preset ids unique", Set(all.map { $0.id }).count == all.count)
        c.check("control preset names unique", Set(all.map { $0.name }).count == all.count)

        // Families: 10 named families per kind.
        for k in ControlPresetKind.allCases {
            c.check("families per \(k) == 10", ControlPresetLibrary.families(in: k).count == 10)
        }

        // Each preset produces a real, non-zero, correctly-kinded layer.
        var samples: [Layer] = []
        for preset in all {
            let layer = preset.makeLayer(at: VPoint(x: 10, y: 20))
            samples.append(layer)
        }
        c.check("layers non-zero size", samples.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 })
        c.check("layer kinds match", zip(all, samples).allSatisfy { p, l in
            switch (p.kind, l.kind) {
            case (.knob, .knob), (.fader, .fader), (.slider, .slider),
                 (.button, .button), (.toggle, .toggle): return true
            default: return false
            }
        })
        c.check("non-button presets carry metadata",
                all.filter { $0.kind != .button }.allSatisfy { $0.metadata != nil })

        // Search hits.
        let danger = ControlPresetLibrary.search("danger", in: .button)
        c.check("search by tag", danger.count == 5 && danger.allSatisfy { $0.tags.contains("danger") })
        let cutoff = ControlPresetLibrary.search("cutoff", in: .knob)
        c.check("search by name", cutoff.count == 10 && cutoff.allSatisfy { $0.name.contains("Cutoff") })

        // End-to-end codegen sanity: a doc containing one of each kind generates
        // SwiftUI that mentions every control type and balances braces.
        let one = { (k: ControlPresetKind) -> Layer in
            ControlPresetLibrary.presets(in: k).first!.makeLayer(at: .zero)
        }
        let mix = Document(name: "Mix", roots: [one(.knob), one(.fader), one(.slider), one(.button), one(.toggle)])
        let src = (try? CodeGenService().generate(mix).contents) ?? ""
        c.check("codegen knob view", src.contains("KnobView("))
        c.check("codegen fader view", src.contains("FaderView("))
        c.check("codegen button", src.contains("Button(action:"))
        c.check("codegen toggle", src.contains("Toggle("))
        c.check("codegen braces balanced",
                src.filter { $0 == "{" }.count == src.filter { $0 == "}" }.count)

        // Existing layout presets still load (regression guard).
        c.check("layout preset library still loads", PresetLibrary.all.count > 0)
    }

    // MARK: Phase 19 — Control asset library expansion
    do {
        let assets = ControlAssetLibrary.all
        c.check("p19 control assets total", assets.count == 120)
        c.check("p19 at least 20 knobs", ControlAssetLibrary.assets(in: .knob).count >= 20)
        c.check("p19 at least 20 faders", ControlAssetLibrary.assets(in: .fader).count >= 20)
        c.check("p19 at least 20 sliders", ControlAssetLibrary.assets(in: .slider).count >= 20)
        c.check("p19 at least 20 buttons", ControlAssetLibrary.assets(in: .button).count >= 20)
        c.check("p19 at least 20 toggles", ControlAssetLibrary.assets(in: .toggle).count >= 20)
        c.check("p19 at least 20 meters", ControlAssetLibrary.assets(in: .meter).count >= 20)

        c.check("p19 ids unique", Set(assets.map { $0.id }).count == assets.count)
        for category in ControlAssetCategory.allCases {
            let inCategory = ControlAssetLibrary.assets(in: category)
            c.check("p19 names unique \(category.rawValue)",
                    Set(inCategory.map { $0.name }).count == inCategory.count)
        }

        c.check("p19 every asset has metadata", assets.allSatisfy { asset in
            let metadata = asset.metadata
            return metadata.role == asset.role &&
                metadata.function == asset.function &&
                !asset.accessibilityLabelTemplate.isEmpty &&
                !asset.tags.isEmpty
        })

        let layers = assets.map { $0.makeLayer(at: VPoint(x: 8, y: 12)) }
        c.check("p19 every asset creates non-zero layer",
                layers.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 })
        c.check("p19 layer kinds match categories",
                zip(assets, layers).allSatisfy { asset, layer in asset.category.layerKind == layer.kind })
        c.check("p19 control metadata present",
                zip(assets, layers).allSatisfy { asset, layer in
                    asset.category == .button ? layer.control != nil : layer.control != nil
                })
        c.check("p19 meter assets are readout metadata",
                ControlAssetLibrary.assets(in: .meter).allSatisfy {
                    $0.behaviour == .meterReadout && $0.metadata.interaction == .none
                })

        let sampleLayers = ControlAssetCategory.allCases.compactMap {
            ControlAssetLibrary.assets(in: $0).first?.makeLayer(at: .zero)
        }
        let src = (try? CodeGenService().generate(Document(name: "AssetControls", roots: sampleLayers)).contents) ?? ""
        c.check("p19 codegen includes controls import", src.contains("import VUAControls"))
        c.check("p19 codegen includes knob", src.contains("KnobView("))
        c.check("p19 codegen includes fader", src.contains("FaderView("))
        c.check("p19 codegen includes slider", src.contains("Slider(value:"))
        c.check("p19 codegen includes button", src.contains("Button(action:"))
        c.check("p19 codegen includes toggle", src.contains("Toggle("))
        c.check("p19 codegen includes meter", src.contains("MeterView("))
        c.check("p19 generated SwiftUI braces balanced",
                src.filter { $0 == "{" }.count == src.filter { $0 == "}" }.count)

        let search = ControlAssetLibrary.search("neon", in: .meter)
        c.check("p19 asset search works", !search.isEmpty && search.allSatisfy { $0.tags.contains("neon") || $0.visualStyle.family == "Neon" })
    }

    // MARK: Phase 17 — Functional asset metadata
    do {
        // Defaults & promotion.
        let knobDefaults = AssetMetadata.defaults(for: .knobCap)
        c.check("knob defaults role+function", knobDefaults.role == .knobCap && knobDefaults.function == .rotaryControl)
        c.check("knob defaults rotation", knobDefaults.rotation?.sweepDegrees == 270)

        let thinBinding = AssetControlBinding(parameterID: "cutoff")
        c.check("thin binding does not promote", thinBinding.toControlMetadata() == nil)

        var fullBinding = thinBinding
        fullBinding.minValue = 20; fullBinding.maxValue = 20000; fullBinding.defaultValue = 1000
        fullBinding.unit = .hertz
        let promoted = fullBinding.toControlMetadata()
        c.check("full binding promotes to ControlMetadata",
                promoted?.parameterID == "cutoff" && promoted?.minValue == 20 && promoted?.maxValue == 20000)

        // Backwards-compat: a legacy Asset JSON without `metadata` still decodes.
        let legacyJSON = #"""
        {
          "id":"11111111-1111-1111-1111-111111111111",
          "name":"PanelBG","path":"p.png",
          "format":"png",
          "intrinsicSize":{"width":1280,"height":800},
          "scale":1,"isLocked":false,"tags":["bg"]
        }
        """#
        let legacy = try JSONDecoder().decode(Asset.self, from: legacyJSON.data(using: .utf8)!)
        c.check("legacy asset decodes with nil metadata", legacy.metadata == nil)

        // Round-trip with metadata.
        var stored = Asset(name: "Cutoff Knob", path: "k.png", format: .png,
                           intrinsicSize: VSize(width: 100, height: 100), tags: ["knob"])
        stored.metadata = {
            var m = AssetMetadata.defaults(for: .knobCap)
            m.binding.parameterID = "cutoff"
            m.binding.minValue = 20; m.binding.maxValue = 20000; m.binding.defaultValue = 1000
            m.binding.unit = .hertz; m.binding.midiCC = 74; m.binding.auParameterID = "au_cutoff"
            return m
        }()
        let encoded = try JSONEncoder().encode(stored)
        let decoded = try JSONDecoder().decode(Asset.self, from: encoded)
        c.check("asset metadata round-trip role", decoded.metadata?.role == .knobCap)
        c.check("asset metadata round-trip binding", decoded.metadata?.binding.parameterID == "cutoff"
                && decoded.metadata?.binding.midiCC == 74
                && decoded.metadata?.binding.auParameterID == "au_cutoff")

        // Placement: metadata drives layer kind + control binding.
        let placement = AssetLibrary.placement(for: stored)
        c.check("placement layer kind from role", placement.layerKind == .knob)
        c.check("placement control populated", placement.control?.parameterID == "cutoff")
        c.check("placement frame centred",
                placement.frame(centeredOn: VPoint(x: 100, y: 200)).midX == 100 &&
                placement.frame(centeredOn: VPoint(x: 100, y: 200)).midY == 200)

        // Plain decorative asset still drops as .image.
        let decor = Asset(name: "Decor", path: "d.png", format: .png,
                          intrinsicSize: VSize(width: 80, height: 80))
        c.check("decorative asset is image", AssetLibrary.placement(for: decor).layerKind == .image)

        // Background-tagged asset still drops as .background and locked.
        let bg = Asset(name: "Backplate", path: "bp.png", format: .png,
                       intrinsicSize: VSize(width: 800, height: 400), tags: ["background"])
        let bgPlacement = AssetLibrary.placement(for: bg)
        c.check("background placement", bgPlacement.layerKind == .background && bgPlacement.isLocked)

        // Diagnostics: parameter id missing, range missing, default out of range, MIDI CC out of range, invalid range.
        var bad = stored
        bad.metadata?.binding.parameterID = nil
        let badIssues = AssetMetadataDiagnostics.validate(bad)
        c.check("diag missing parameter id",
                badIssues.contains { $0.code == .missingParameterID && $0.severity == .error })

        var rangeBad = stored
        rangeBad.metadata?.binding.minValue = 200; rangeBad.metadata?.binding.maxValue = 100
        c.check("diag invalid range",
                AssetMetadataDiagnostics.validate(rangeBad).contains { $0.code == .invalidRange })

        var defOOR = stored
        defOOR.metadata?.binding.defaultValue = 99_999
        c.check("diag default out of range",
                AssetMetadataDiagnostics.validate(defOOR).contains { $0.code == .defaultOutOfRange })

        var ccBad = stored
        ccBad.metadata?.binding.midiCC = 200
        c.check("diag midi CC out of range",
                AssetMetadataDiagnostics.validate(ccBad).contains { $0.code == .midiCCOutOfRange })

        var stepped = stored
        stepped.metadata?.binding.isContinuous = false
        stepped.metadata?.binding.stepCount = nil
        c.check("diag missing steps",
                AssetMetadataDiagnostics.validate(stepped).contains { $0.code == .missingSteps })

        var mismatch = stored
        mismatch.metadata?.function = .linearControl // knobCap role + linearControl function
        c.check("diag role/function mismatch",
                AssetMetadataDiagnostics.validate(mismatch).contains { $0.code == .roleFunctionMismatch })

        // Tagged-as-control without metadata → missingMetadata warning.
        let taggedNoMeta = Asset(name: "K", path: "k.png", format: .png,
                                 intrinsicSize: VSize(width: 64, height: 64), tags: ["knob"])
        c.check("diag missingMetadata for tagged asset",
                AssetMetadataDiagnostics.validate(taggedNoMeta).contains { $0.code == .missingMetadata })

        // Bulk validator across multiple assets.
        let bulk = AssetMetadataDiagnostics.validate(assets: [stored, decor, bad, taggedNoMeta])
        c.check("bulk validator returns issues",
                bulk.contains { $0.code == .missingParameterID } &&
                bulk.contains { $0.code == .missingMetadata })

        // Codegen: a knob layer wired from asset metadata produces a KnobView call.
        let knobLayer = Layer(name: "K", kind: .knob,
                              frame: VRect(x: 0, y: 0, width: 64, height: 64),
                              assetID: stored.id,
                              control: stored.metadata?.binding.toControlMetadata())
        let doc = Document(roots: [knobLayer], assets: [stored])
        let src = (try? CodeGenService().generate(doc).contents) ?? ""
        c.check("codegen emits knob from asset metadata", src.contains("KnobView(") && src.contains("20...20000"))
        c.check("codegen braces balanced",
                src.filter { $0 == "{" }.count == src.filter { $0 == "}" }.count)
    } catch {
        FileHandle.standardError.write(Data("p17 exception: \(error)\n".utf8))
        c.check("p17 exception", false)
    }

    // MARK: Phase 20 — Control behaviour engine
    do {
        let knobMeta = ControlMetadata(parameterID: "cutoff", displayName: "Cutoff",
                                       minValue: 20, maxValue: 20000, defaultValue: 1000,
                                       unit: .hertz, behaviourType: ControlBehaviourType.rotaryKnob.rawValue,
                                       interactionMode: ControlInteractionMode.verticalDragRotary.rawValue,
                                       responseCurve: ControlResponseCurve.linear.rawValue,
                                       bindingName: "synth.cutoff", midiCC: 74,
                                       auParameterID: "filter.cutoff", automationEnabled: true,
                                       rotationStartDegrees: -135, rotationEndDegrees: 135)
        let knobLayer = Layer(name: "Cutoff", kind: .knob, control: knobMeta)
        let knobProfile = ControlBehaviourResolver.profile(for: knobLayer)
        c.check("p20 behaviour maps range", knobProfile?.minValue == 20 && knobProfile?.maxValue == 20000)
        c.check("p20 knob normalisation", abs((knobProfile?.normalizedValue ?? 0) - knobMeta.normalizedDefault) < 0.0001)
        c.check("p20 knob metadata links", knobProfile?.bindingName == "synth.cutoff" && knobProfile?.midiCC == 74 && knobProfile?.automationEnabled == true)

        let bipolar = Layer(name: "Pan", kind: .knob,
                            control: ControlMetadata(parameterID: "pan", minValue: -100, maxValue: 100,
                                                     defaultValue: 0, unit: .percent,
                                                     behaviourType: ControlBehaviourType.bipolarKnob.rawValue))
        c.check("p20 bipolar knob centre", ControlBehaviourResolver.profile(for: bipolar)?.normalizedValue == 0.5)

        let stepped = Layer(name: "Mode", kind: .knob,
                            control: ControlMetadata(parameterID: "mode", minValue: 0, maxValue: 3,
                                                     defaultValue: 1.8, isContinuous: false, stepCount: 4,
                                                     behaviourType: ControlBehaviourType.steppedKnob.rawValue))
        c.check("p20 stepped clamps", ControlBehaviourResolver.profile(for: stepped)?.clamped(1.8) == 2)
        c.check("p20 stepped mode", ControlBehaviourResolver.profile(for: stepped)?.snapBehaviour == .step)

        let fader = Layer(name: "Level", kind: .fader,
                          control: ControlMetadata(parameterID: "level", minValue: -60, maxValue: 6,
                                                   defaultValue: 0, unit: .decibels,
                                                   behaviourType: ControlBehaviourType.verticalFader.rawValue))
        c.check("p20 fader vertical behaviour", ControlBehaviourResolver.profile(for: fader)?.dragAxis == .vertical)

        let slider = Layer(name: "Mix", kind: .slider,
                           control: ControlMetadata(parameterID: "mix", minValue: 0, maxValue: 100,
                                                    defaultValue: 50, unit: .percent,
                                                    behaviourType: ControlBehaviourType.horizontalSlider.rawValue))
        c.check("p20 slider horizontal behaviour", ControlBehaviourResolver.profile(for: slider)?.dragAxis == .horizontal)

        let button = Layer(name: "Trigger", kind: .button,
                           control: ControlMetadata(parameterID: "trigger", minValue: 0, maxValue: 1,
                                                    defaultValue: 0, isContinuous: false, stepCount: 2,
                                                    behaviourType: ControlBehaviourType.buttonPress.rawValue))
        c.check("p20 button validates", ControlBehaviourDiagnostics.validate(button).isEmpty)

        let toggle = Layer(name: "Bypass", kind: .toggle,
                           control: ControlMetadata(parameterID: "bypass", minValue: 0, maxValue: 1,
                                                    defaultValue: 1, isContinuous: false, stepCount: 2,
                                                    behaviourType: ControlBehaviourType.toggleSwitch.rawValue))
        c.check("p20 toggle validates", ControlBehaviourDiagnostics.validate(toggle).isEmpty)

        let meter = Layer(name: "Output", kind: .meter,
                          control: ControlMetadata(parameterID: "output", minValue: -60, maxValue: 0,
                                                   defaultValue: -18, unit: .decibels,
                                                   behaviourType: ControlBehaviourType.meterReadout.rawValue,
                                                   interactionMode: ControlInteractionMode.readOnly.rawValue))
        c.check("p20 meter read-only", ControlBehaviourResolver.profile(for: meter)?.interactionMode == .readOnly)

        let missing = Layer(name: "Unbound", kind: .knob)
        c.check("p20 missing behaviour diagnostic",
                ControlBehaviourDiagnostics.validate(missing).contains { $0.code == .missingBehaviour })

        let badMidi = Layer(name: "Bad MIDI", kind: .slider,
                            control: ControlMetadata(parameterID: "bad", minValue: 0, maxValue: 1,
                                                     defaultValue: 0.5, midiCC: 200))
        c.check("p20 invalid midi diagnostic",
                ControlBehaviourDiagnostics.validate(badMidi).contains { $0.code == .invalidMIDI })

        let assetLayer = ControlAssetLibrary.assets(in: .knob).first!.makeLayer()
        c.check("p20 asset carries behaviour metadata",
                assetLayer.control?.behaviourType != nil && ControlBehaviourResolver.profile(for: assetLayer) != nil)

        let src = (try? CodeGenService().generate(Document(name: "Behaviour", roots: [knobLayer])).contents) ?? ""
        c.check("p20 codegen emits behaviour comment", src.contains("// Behaviour: Rotary Knob"))
        c.check("p20 codegen emits binding TODO/comment", src.contains("// Binding target: synth.cutoff"))
        c.check("p20 codegen emits midi comment", src.contains("// MIDI CC: 74"))
    }

    // MARK: Phase 21 — Refined line tool
    do {
        let straight = Layer(name: "Line", kind: .line,
                             frame: VRect(x: 0, y: 0, width: 120, height: 24),
                             style: LayerStyle(borderColor: .white, borderWidth: 2),
                             line: LineSpec(start: VPoint(x: 0, y: 12),
                                            end: VPoint(x: 120, y: 12)))
        let straightSrc = (try? CodeGenService().generate(Document(roots: [straight])).contents) ?? ""
        c.check("p21 line start/end generate path",
                straightSrc.contains("path.move(to: CGPoint(x: 0, y: 12))") &&
                straightSrc.contains("path.addLine(to: CGPoint(x: 120, y: 12))"))

        let dashed = Layer(name: "Dashed", kind: .line,
                           frame: VRect(x: 0, y: 0, width: 120, height: 24),
                           style: LayerStyle(borderColor: .white, borderWidth: 2),
                           line: LineSpec(start: VPoint(x: 0, y: 12), end: VPoint(x: 120, y: 12),
                                          dashed: true, lineCap: .butt, lineJoin: .bevel))
        let dashedSrc = (try? CodeGenService().generate(Document(roots: [dashed])).contents) ?? ""
        c.check("p21 dashed line generates SwiftUI",
                dashedSrc.contains("dash: [6, 4]") && dashedSrc.contains("lineCap: .butt") && dashedSrc.contains("lineJoin: .bevel"))

        let dotted = Layer(name: "Dotted", kind: .line,
                           frame: VRect(x: 0, y: 0, width: 120, height: 24),
                           style: LayerStyle(borderColor: .white, borderWidth: 3),
                           line: LineSpec(start: VPoint(x: 0, y: 12), end: VPoint(x: 120, y: 12),
                                          dotted: true))
        let dottedSrc = (try? CodeGenService().generate(Document(roots: [dotted])).contents) ?? ""
        c.check("p21 dotted line generates SwiftUI", dottedSrc.contains("dash: [1, 6]"))

        let arrow = Layer(name: "Arrow", kind: .line,
                          frame: VRect(x: 0, y: 0, width: 140, height: 40),
                          style: LayerStyle(borderColor: .white, borderWidth: 2),
                          line: LineSpec(start: VPoint(x: 10, y: 20), end: VPoint(x: 130, y: 20),
                                         arrowEnd: true))
        let arrowSrc = (try? CodeGenService().generate(Document(roots: [arrow])).contents) ?? ""
        c.check("p21 arrow line generates SwiftUI",
                arrowSrc.components(separatedBy: "path.addLine(to:").count >= 4)

        let curved = Layer(name: "Curve", kind: .line,
                           frame: VRect(x: 0, y: 0, width: 160, height: 80),
                           style: LayerStyle(borderColor: .white, borderWidth: 2),
                           line: LineSpec(start: VPoint(x: 0, y: 40), end: VPoint(x: 160, y: 40),
                                          connectorMode: .curved,
                                          controlPoint1: VPoint(x: 40, y: 0),
                                          controlPoint2: VPoint(x: 120, y: 80)))
        let curvedSrc = (try? CodeGenService().generate(Document(roots: [curved])).contents) ?? ""
        c.check("p21 curved connector generates Path", curvedSrc.contains("path.addCurve(to:"))

        let elbow = LineSpec(start: VPoint(x: 0, y: 10), end: VPoint(x: 100, y: 60),
                             connectorMode: .elbow, snapMode: .layerEdge)
        c.check("p21 connector metadata round-trips",
                (try? JSONDecoder().decode(LineSpec.self, from: JSONEncoder().encode(elbow))).map {
                    $0.effectiveConnector == .elbow && $0.effectiveSnap == .layerEdge
                } == true)

        let zero = Layer(name: "ZeroLine", kind: .line,
                         frame: VRect(x: 0, y: 0, width: 20, height: 20),
                         style: LayerStyle(borderColor: .white, borderWidth: 2),
                         line: LineSpec(start: VPoint(x: 5, y: 5), end: VPoint(x: 5, y: 5)))
        c.check("p21 zero-length line diagnostic",
                LineTool.validate(zero, canvasSize: VSize(width: 200, height: 200)).contains { $0.code == .zeroLength })

        let invisible = Layer(name: "InvisibleLine", kind: .line,
                              frame: VRect(x: 0, y: 0, width: 20, height: 20),
                              style: LayerStyle(borderColor: .white, borderWidth: 0),
                              line: LineSpec(start: VPoint(x: 0, y: 10), end: VPoint(x: 20, y: 10)))
        c.check("p21 invisible stroke diagnostic",
                LineTool.validate(invisible, canvasSize: VSize(width: 200, height: 200)).contains { $0.code == .invisibleStroke })

        let outside = Layer(name: "OutsideLine", kind: .line,
                            frame: VRect(x: 190, y: 0, width: 40, height: 20),
                            style: LayerStyle(borderColor: .white, borderWidth: 2),
                            line: LineSpec(start: VPoint(x: 0, y: 10), end: VPoint(x: 40, y: 10)))
        c.check("p21 outside canvas diagnostic",
                LineTool.validate(outside, canvasSize: VSize(width: 200, height: 200)).contains { $0.code == .lineOutsideCanvas })

        let constrained = LineTool.constrainedEnd(start: .zero, proposed: VPoint(x: 30, y: 10))
        c.check("p21 shift constraint snaps angle", abs(constrained.y) < 0.001 || abs(abs(constrained.x) - abs(constrained.y)) < 0.001)
    }

    // MARK: Phase 18 — Existing UI import / screen loader
    do {
        // A representative importable view with anchors + one unsupported call.
        let supportedSrc = """
        import SwiftUI
        struct HomeScreen: View {
            var body: some View {
                ZStack(alignment: .topLeading) {
                    // Title
                    Text("Welcome")
                        .font(.system(size: 22))
                        .frame(width: 200, height: 28)
                        .position(x: 120, y: 30)
                        .accessibilityIdentifier("title")
                    Button("Start") {}
                        .frame(width: 120, height: 44)
                        .position(x: 90, y: 100)
                        .accessibilityIdentifier("startButton")
                    Chart { }   // unsupported on first pass
                }
            }
        }

        struct NotAView { let x = 1 }   // must be ignored

        struct HelperView: View {
            var body: some View { VStack { Text("Hi") } }
        }
        """

        let cands = ExistingUIImport.candidates(inSource: supportedSrc, filePath: "/tmp/Home.swift")
        c.check("scan finds view candidates", cands.contains { $0.viewName == "HomeScreen" })
        c.check("scan ignores non-View struct", !cands.contains { $0.viewName == "NotAView" })
        c.check("scan finds multiple views", cands.count == 2)
        let home = cands.first { $0.viewName == "HomeScreen" }!
        c.check("candidate reports anchors", home.hasAnchors)
        c.check("candidate counts unsupported", home.unsupportedElementCount >= 1)
        c.check("candidate confidence < 1 with unsupported", home.confidence < 1.0 && home.confidence > 0)
        c.check("candidate warns about unsupported", home.warnings.contains { $0.contains("unsupported") })

        // Anchor-less view warns and is still importable.
        let noAnchorSrc = """
        import SwiftUI
        struct Plain: View { var body: some View { VStack { Text("a"); Text("b") } } }
        """
        let plain = ExistingUIImport.candidates(inSource: noAnchorSrc, filePath: "/tmp/Plain.swift").first!
        c.check("no-anchor candidate flagged", !plain.hasAnchors &&
                plain.warnings.contains { $0.localizedCaseInsensitiveContains("anchor") })
        c.check("p22 no-anchor warning is explicit",
                plain.warnings.contains { $0.contains("round-trip editing needs anchors") })

        // Import from a real temp file → editable layers + source hash.
        let dir = fm.temporaryDirectory.appendingPathComponent("vua-import-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("Home.swift")
        try supportedSrc.data(using: .utf8)!.write(to: fileURL)

        let fileCands = ExistingUIImport.candidates(inFile: fileURL)
        let imported = ExistingUIImport.importCandidate(fileCands.first { $0.viewName == "HomeScreen" }!)
        c.check("import parses into layers", (imported?.view.roots.first?.flattened().count ?? 0) > 1)
        c.check("import stores source hash", !(imported?.sourceHash.isEmpty ?? true))
        c.check("p22 provenance stores source hash", imported?.sourceHash == ExistingUIImport.sourceHash(supportedSrc))
        c.check("import preserves anchors", imported?.view.roots.flatMap { $0.flattened() }
                .contains { $0.binding?.anchorID == "startButton" } ?? false)

        let plainURL = dir.appendingPathComponent("Plain.swift")
        try noAnchorSrc.data(using: .utf8)!.write(to: plainURL)
        let plainCandidate = ExistingUIImport.candidates(inFile: plainURL).first!
        let beforePlainImport = (try? String(contentsOf: plainURL, encoding: .utf8)) ?? ""
        let plainImport = ExistingUIImport.importCandidate(plainCandidate)
        let afterPlainImport = (try? String(contentsOf: plainURL, encoding: .utf8)) ?? ""
        c.check("p22 no-anchor import is non-destructive", beforePlainImport == afterPlainImport)
        c.check("p22 no-anchor import remains temporary", plainImport?.hasAnchors == false)

        // Source-change detection: untouched file is unchanged; edited file changed.
        let hash = imported!.sourceHash
        c.check("unchanged source not flagged", !ExistingUIImport.sourceChanged(at: fileURL.path, since: hash))
        try (supportedSrc + "\n// edited").data(using: .utf8)!.write(to: fileURL)
        c.check("edited source flagged changed", ExistingUIImport.sourceChanged(at: fileURL.path, since: hash))
        // Deleted file counts as changed (blocks apply).
        try fm.removeItem(at: fileURL)
        c.check("deleted source flagged changed", ExistingUIImport.sourceChanged(at: fileURL.path, since: hash))

        // Hash determinism.
        c.check("source hash deterministic",
                ExistingUIImport.sourceHash("abc") == ExistingUIImport.sourceHash("abc") &&
                ExistingUIImport.sourceHash("abc") != ExistingUIImport.sourceHash("abd"))

        // Repo scan finds views and detects project shape.
        let repo = fm.temporaryDirectory.appendingPathComponent("vua-import-repo-\(UUID().uuidString)")
        try fm.createDirectory(at: repo.appendingPathComponent("Sources/App"), withIntermediateDirectories: true)
        try "// swift-tools-version: 6.0".data(using: .utf8)!.write(to: repo.appendingPathComponent("Package.swift"))
        try supportedSrc.data(using: .utf8)!.write(to: repo.appendingPathComponent("Sources/App/Home.swift"))
        defer { try? fm.removeItem(at: repo) }
        let repoCands = ExistingUIImport.scanRepository(repo)
        c.check("repo scan finds views", repoCands.contains { $0.viewName == "HomeScreen" })
        c.check("repo scan sets repoRoot", repoCands.allSatisfy { $0.repoRoot != nil })
        c.check("p22 imported source appears in repo scan",
                repoCands.contains { $0.filePath.hasSuffix("Sources/App/Home.swift") && $0.viewName == "HomeScreen" })
        let proj = ExistingUIImport.detectProject(repo)
        c.check("project detects Package.swift + Sources", proj.hasPackageSwift && proj.uiDirectories.contains("Sources"))
    } catch {
        FileHandle.standardError.write(Data("p18 exception: \(error)\n".utf8))
        c.check("p18 exception", false)
    }

    // MARK: Phase 23 — Asset transform system
    do {
        let asset = Asset(name: "Panel", path: "Panel.png", format: .png,
                          intrinsicSize: VSize(width: 800, height: 400))
        let transform = AssetTransformSpec(
            scaleX: 1.5, scaleY: 0.75,
            flipHorizontal: true, flipVertical: false,
            crop: CropSpec(x: 0.1, y: 0.2, width: 0.7, height: 0.6),
            blendMode: .multiply,
            textureOverlayID: "grain-light")
        let layer = Layer(name: "Transformed Panel", kind: .image,
                          frame: VRect(x: 20, y: 20, width: 200, height: 100),
                          style: LayerStyle(cornerRadius: 10,
                                            borderColor: .white, borderWidth: 2,
                                            opacity: 0.8,
                                            shadow: ShadowSpec(),
                                            rotationDegrees: 15,
                                            blurRadius: 1),
                          assetID: asset.id,
                          assetTransform: transform)

        c.check("p23 asset rotation model", layer.style.rotationDegrees == 15)
        c.check("p23 flip transform", transform.effectiveScaleX == -1.5 && transform.effectiveScaleY == 0.75)
        c.check("p23 crop metadata", transform.crop?.isValidUnitRect == true && transform.crop?.isIdentity == false)
        c.check("p23 texture hook persists", layer.assetTransform?.textureOverlayID == "grain-light")

        let encoded = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(Layer.self, from: encoded)
        c.check("p23 transform metadata round-trips",
                decoded.assetTransform?.blendMode == .multiply &&
                decoded.assetTransform?.crop?.x == 0.1 &&
                decoded.assetTransform?.flipHorizontal == true)

        let transformedSrc = (try? CodeGenService().generate(Document(roots: [layer], assets: [asset])).contents) ?? ""
        c.check("p23 transformed layer codegen",
                transformedSrc.contains(".rotationEffect(.degrees(15))") &&
                transformedSrc.contains(".scaleEffect(x: -1.50, y: 0.75)") &&
                transformedSrc.contains(".blendMode(.multiply)") &&
                transformedSrc.contains("// Crop metadata:"))
        c.check("p23 transform codegen keeps border shadow blur",
                transformedSrc.contains(".overlay(RoundedRectangle") &&
                transformedSrc.contains(".shadow(") &&
                transformedSrc.contains(".blur(radius: 1)"))

        let invalidCrop = Layer(name: "Bad Crop", kind: .image,
                                frame: VRect(x: 0, y: 0, width: 100, height: 100),
                                assetID: asset.id,
                                assetTransform: AssetTransformSpec(crop: CropSpec(x: 0.8, y: 0.8, width: 0.5, height: 0.5)))
        let invalidReport = ValidationService().validate(Document(roots: [invalidCrop], assets: [asset]))
        c.check("p23 crop outside image bounds diagnostic",
                invalidReport.issues.contains { $0.message.contains("crop is outside image bounds") })

        let missingAsset = Layer(name: "Missing Asset", kind: .image,
                                 frame: VRect(x: 0, y: 0, width: 100, height: 100),
                                 assetTransform: AssetTransformSpec(scaleX: 2, scaleY: 2))
        let missingReport = ValidationService().validate(Document(roots: [missingAsset]))
        c.check("p23 missing transformed asset diagnostic",
                missingReport.issues.contains { $0.message.contains("transform metadata but no asset") })

        let huge = Layer(name: "Huge Transform", kind: .image,
                         frame: VRect(x: 0, y: 0, width: 700, height: 700),
                         assetID: asset.id,
                         assetTransform: AssetTransformSpec(scaleX: 4, scaleY: 4))
        let hugeReport = ValidationService().validate(Document(roots: [huge], assets: [asset]))
        c.check("p23 huge transformed image warning",
                hugeReport.issues.contains { $0.message.contains("transformed image is very large") })
    } catch {
        FileHandle.standardError.write(Data("p23 exception: \(error)\n".utf8))
        c.check("p23 exception", false)
    }

    // MARK: Phase 24 — Raster drawing tool
    do {
        let original = Asset(name: "Original", path: "Original.png", format: .png,
                             intrinsicSize: VSize(width: 120, height: 80))
        let brush = RasterBrushSpec(tool: .brush, size: 8, opacity: 0.6,
                                    hardness: 0.5, color: VColor(hex: "#FF0000") ?? VColor(red: 1, green: 0, blue: 0))
        let stroke = RasterPaintStroke(brush: brush,
                                       points: [VPoint(x: 10, y: 10), VPoint(x: 60, y: 30), VPoint(x: 100, y: 60)])
        var paint = RasterPaintSpec(isPaintModeEnabled: true, activeBrush: brush, strokes: [stroke])
        let imageLayer = Layer(name: "Paintable", kind: .image,
                               frame: VRect(x: 0, y: 0, width: 120, height: 80),
                               assetID: original.id,
                               rasterPaint: paint)

        c.check("p24 raster stroke creation", stroke.isDrawable && paint.hasDrawableStrokes)
        c.check("p24 paint layer validates", RasterDrawingEngine.validatePaintLayer(imageLayer, asset: original).isEmpty)

        let export = RasterDrawingEngine.exportPaintedPNG(layer: imageLayer, baseAsset: original, name: "Paintable_Edit")
        c.check("p24 paint layer exports PNG metadata",
                export?.asset.name == "Paintable_Edit" &&
                export?.asset.format == .png &&
                export?.asset.tags.contains("paint") == true &&
                !(export?.pngData.isEmpty ?? true))
        c.check("p24 original asset remains unchanged",
                export?.originalAssetID == original.id && original.path == "Original.png")

        paint.exportedAssetID = export?.asset.id
        paint.exportedAssetName = export?.asset.name
        let paintedLayer = Layer(name: "Painted", kind: .image,
                                 frame: VRect(x: 0, y: 0, width: 120, height: 80),
                                 assetID: original.id,
                                 rasterPaint: paint)
        let paintedSrc = (try? CodeGenService().generate(Document(roots: [paintedLayer], assets: [original])).contents) ?? ""
        c.check("p24 codegen emits paint metadata",
                paintedSrc.contains("// Raster paint: 1 stroke") && paintedSrc.contains("// Painted PNG asset: Paintable_Edit"))

        let unsupported = Asset(name: "Vector", path: "Vector.svg", format: .svg)
        let unsupportedIssues = RasterDrawingEngine.validatePaintLayer(imageLayer, asset: unsupported)
        c.check("p24 unsupported image format diagnostic",
                unsupportedIssues.contains { $0.code == RasterPaintDiagnosticCode.unsupportedImageFormat })

        let emptyPaintLayer = Layer(name: "Empty Paint", kind: .image,
                                    frame: VRect(x: 0, y: 0, width: 120, height: 80),
                                    assetID: original.id,
                                    rasterPaint: RasterPaintSpec(isPaintModeEnabled: true))
        c.check("p24 paint layer no strokes diagnostic",
                RasterDrawingEngine.validatePaintLayer(emptyPaintLayer, asset: original).contains { $0.code == .noStrokes })

        let missingPaintedAsset = Layer(name: "Missing Painted", kind: .image,
                                        frame: VRect(x: 0, y: 0, width: 120, height: 80),
                                        assetID: original.id,
                                        rasterPaint: RasterPaintSpec(strokes: [stroke],
                                                                     exportedAssetID: UUID(),
                                                                     exportedAssetName: "MissingPaint"))
        let missingPaintReport = ValidationService().validate(Document(roots: [missingPaintedAsset], assets: [original]))
        c.check("p24 painted asset missing diagnostic",
                missingPaintReport.issues.contains { $0.message.contains("missing painted PNG asset") })
    }

    // MARK: Phase 25 — Vector / SVG drawing tool
    do {
        let path = VectorPathSpec(
            anchors: [
                VectorAnchorPoint(point: VPoint(x: 0, y: 80)),
                VectorAnchorPoint(point: VPoint(x: 40, y: 0),
                                  handleIn: VPoint(x: 15, y: 20),
                                  handleOut: VPoint(x: 70, y: 0)),
                VectorAnchorPoint(point: VPoint(x: 120, y: 80),
                                  handleIn: VPoint(x: 90, y: 0))
            ],
            isClosed: false,
            strokeColor: .black,
            strokeWidth: 2,
            fillColor: nil)
        let vectorLayer = Layer(name: "Bezier", kind: .vectorPath,
                                frame: VRect(x: 0, y: 0, width: 120, height: 90),
                                vectorPath: path)
        let vectorSrc = (try? CodeGenService().generate(Document(roots: [vectorLayer])).contents) ?? ""
        c.check("p25 vector path creates valid SwiftUI Path",
                vectorSrc.contains("Path { path in") &&
                vectorSrc.contains("path.move(to:") &&
                vectorSrc.contains("path.addCurve(to:") &&
                vectorSrc.contains(".stroke("))

        let svgData = VectorDrawingEngine.svgPathData(path)
        c.check("p25 SVG path data", svgData.hasPrefix("M 0 80") && svgData.contains("C "))
        let svg = VectorDrawingEngine.exportSVG(layer: vectorLayer) ?? ""
        c.check("p25 SVG export basic path",
                svg.contains("<svg") && svg.contains("<path") && svg.contains("stroke=\"#000000\""))

        let invalid = Layer(name: "Invalid Vector", kind: .vectorPath,
                            frame: VRect(x: 0, y: 0, width: 100, height: 100),
                            vectorPath: VectorPathSpec(anchors: [VectorAnchorPoint(point: .zero)],
                                                       strokeColor: nil, fillColor: nil))
        let invalidIssues = VectorDrawingEngine.validate(layer: invalid, canvasSize: VSize(width: 200, height: 200))
        c.check("p25 invalid path diagnostic",
                invalidIssues.contains { $0.code == .invalidPath } &&
                invalidIssues.contains { $0.code == .missingFillStroke })

        let unsupported = Layer(name: "SVG Import", kind: .vectorPath,
                                frame: VRect(x: 0, y: 0, width: 100, height: 100),
                                vectorPath: VectorPathSpec(
                                    anchors: [VectorAnchorPoint(point: .zero), VectorAnchorPoint(point: VPoint(x: 20, y: 20))],
                                    unsupportedSVGCommands: ["A"]))
        c.check("p25 unsupported SVG command diagnostic",
                VectorDrawingEngine.validate(layer: unsupported, canvasSize: VSize(width: 200, height: 200))
                    .contains { $0.code == .unsupportedSVGCommand })

        let outside = Layer(name: "Outside Vector", kind: .vectorPath,
                            frame: VRect(x: 190, y: 190, width: 100, height: 100),
                            vectorPath: VectorPathSpec(anchors: [
                                VectorAnchorPoint(point: VPoint(x: 0, y: 0)),
                                VectorAnchorPoint(point: VPoint(x: 40, y: 40))
                            ]))
        c.check("p25 path outside canvas diagnostic",
                VectorDrawingEngine.validate(layer: outside, canvasSize: VSize(width: 200, height: 200))
                    .contains { $0.code == .pathOutsideCanvas })
    }

    print("VUACheck: \(c.passed) passed, \(c.failures) failed")
    exit(c.failures == 0 ? 0 : 1)
}

await runChecks()
