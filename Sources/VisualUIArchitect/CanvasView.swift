import SwiftUI
import VUACore
import LayerEngine
import CanvasEngine
import PreviewEngine

/// The visual editing surface. Renders the document's render model and hosts
/// selection, drag-to-move (with snapping), and resize-handle interactions.
struct CanvasView: View {
    @EnvironmentObject var store: DocumentStore
    @EnvironmentObject var theme: ThemeSettings
    @State private var zoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var viewportSize: CGSize = .zero

    @AppStorage("vua.grid.enabled") private var gridEnabled = false
    @AppStorage("vua.grid.snap") private var snapToGrid = false
    @AppStorage("vua.grid.size") private var gridSize = 8.0
    @AppStorage("vua.guides.show") private var showGuides = true
    @AppStorage("vua.rulers.show") private var showRulers = true

    var body: some View {
        let model = store.renderModel
        ScrollView([.horizontal, .vertical]) {
            canvas(model)
                .frame(width: model.canvasSize.width * zoom + 200,
                       height: model.canvasSize.height * zoom + 200)
        }
        .background(
            theme.canvasBackground
                .overlay(GeometryReader { geo in
                    Color.clear.onAppear { viewportSize = geo.size }
                        .onChange(of: geo.size) { _, newValue in viewportSize = newValue }
                })
        )
        .overlay(alignment: .top) { canvasToolbar.padding(8) }
        .overlay(alignment: .bottomTrailing) { zoomControls.padding(12) }
        .gesture(MagnificationGesture()
            .onChanged { scale in zoom = CanvasViewport.clampZoom(Double(lastZoom * scale)) }
            .onEnded { _ in lastZoom = zoom })
    }

    private func canvas(_ model: RenderModel) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.25))
                .frame(width: model.canvasSize.width, height: model.canvasSize.height)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15)))

            if gridEnabled { gridOverlay(model.canvasSize) }
            if showRulers { rulersOverlay(model.canvasSize) }

            ForEach(model.nodes, id: \.id) { node in
                nodeView(node)
            }

            if showGuides { guidesLayer(model.canvasSize) }

            ForEach(Array(store.snapGuides.enumerated()), id: \.offset) { _, guide in
                guideView(guide, canvasSize: model.canvasSize)
            }

            if let layer = store.canSelectSingle,
               let frame = LayerTree.absoluteFrame(of: layer.id, in: store.document.roots) {
                SelectionOverlay(frame: frame, zoom: zoom)
                    .environmentObject(store)
            }
        }
        // Attached before scaleEffect so `location` is in canvas coordinates.
        .dropDestination(for: String.self) { items, location in
            guard let idString = items.first, let assetID = UUID(uuidString: idString) else { return false }
            store.dropAsset(assetID, at: VPoint(x: Double(location.x), y: Double(location.y)))
            return true
        }
        .scaleEffect(zoom, anchor: .topLeading)
        .padding(40)
        .contentShape(Rectangle())
        .onTapGesture { store.selection = [] }
    }

    // MARK: - Grid & guides

    private func gridOverlay(_ size: VSize) -> some View {
        Path { path in
            var x = gridSize
            while x < size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += gridSize }
            var y = gridSize
            while y < size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += gridSize }
        }
        .stroke(Color.white.opacity(0.06), lineWidth: 1 / zoom)
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    /// Tick marks + labels along the top and left edges of the canvas, spaced
    /// via `CanvasRuler` so they never crowd at any zoom.
    private func rulersOverlay(_ size: VSize) -> some View {
        let xs = CanvasRuler.ticks(lengthPoints: size.width, zoom: Double(zoom))
        let ys = CanvasRuler.ticks(lengthPoints: size.height, zoom: Double(zoom))
        return ZStack(alignment: .topLeading) {
            ForEach(Array(xs.enumerated()), id: \.offset) { _, x in
                VStack(spacing: 1) {
                    Text("\(Int(x))").font(.system(size: 7)).foregroundStyle(.secondary)
                    Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 1 / zoom, height: 5)
                }
                .fixedSize()
                .position(x: x, y: -12)
            }
            ForEach(Array(ys.enumerated()), id: \.offset) { _, y in
                HStack(spacing: 1) {
                    Text("\(Int(y))").font(.system(size: 7)).foregroundStyle(.secondary)
                    Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 5, height: 1 / zoom)
                }
                .fixedSize()
                .position(x: -16, y: y)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func guidesLayer(_ size: VSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(store.verticalGuides.enumerated()), id: \.offset) { idx, x in
                Rectangle().fill(Color.pink.opacity(0.7)).frame(width: 1 / zoom, height: size.height)
                    .position(x: x, y: size.height / 2)
                    .gesture(DragGesture().onChanged { v in
                        store.verticalGuides[idx] = Double(v.location.x)
                    })
                    .onTapGesture(count: 2) { store.verticalGuides.remove(at: idx) }
            }
            ForEach(Array(store.horizontalGuides.enumerated()), id: \.offset) { idx, y in
                Rectangle().fill(Color.pink.opacity(0.7)).frame(width: size.width, height: 1 / zoom)
                    .position(x: size.width / 2, y: y)
                    .gesture(DragGesture().onChanged { v in
                        store.horizontalGuides[idx] = Double(v.location.y)
                    })
                    .onTapGesture(count: 2) { store.horizontalGuides.remove(at: idx) }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var canvasToolbar: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $gridEnabled) { Image(systemName: "grid") }.toggleStyle(.button)
                .help("Show grid")
            Toggle(isOn: $snapToGrid) { Image(systemName: "dot.squareshape.split.2x2") }.toggleStyle(.button)
                .help("Snap to grid")
            Stepper("Grid \(Int(gridSize))", value: $gridSize, in: 2...64, step: 2)
                .fixedSize()
            Divider().frame(height: 16)
            Toggle(isOn: $showGuides) { Image(systemName: "ruler") }.toggleStyle(.button)
                .help("Show guides")
            Button { store.addVerticalGuide(store.document.canvasSize.width / 2) } label: { Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down") }
                .help("Add vertical guide")
            Button { store.addHorizontalGuide(store.document.canvasSize.height / 2) } label: { Image(systemName: "arrow.left.and.right") }
                .help("Add horizontal guide")
            Button { store.clearGuides() } label: { Image(systemName: "xmark") }
                .help("Clear guides").disabled(store.verticalGuides.isEmpty && store.horizontalGuides.isEmpty)
        }
        .font(.caption)
        .padding(6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .buttonStyle(.borderless)
    }

    private func nodeView(_ node: RenderModel.Node) -> some View {
        let isSelected = store.selection.contains(node.id)
        let asset = node.layer.assetID.flatMap { store.document.asset(id: $0) }
        let resolution = asset.map { AssetResolver.shared.resolve($0, in: store.assetsDirectory) }
        return LayerRenderView(layer: node.layer, asset: asset, resolution: resolution)
            .overlay(isSelected ? Rectangle().stroke(theme.accent, lineWidth: 1.5) : nil)
            .position(x: node.absoluteFrame.midX, y: node.absoluteFrame.midY)
            .gesture(dragGesture(for: node))
            .simultaneousGesture(TapGesture().onEnded { toggleSelection(node.id) })
            .allowsHitTesting(!node.layer.isLocked)
    }

    private func dragGesture(for node: RenderModel.Node) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !store.selection.contains(node.id) { store.selection = [node.id] }
                store.beginInteractionIfNeeded()
                moveSelected(node, translation: value.translation)
            }
            .onEnded { _ in store.endInteraction() }
    }

    private func moveSelected(_ node: RenderModel.Node, translation: CGSize) {
        guard let base = store.baselineFrame(node.id) else { return }
        let delta = VPoint(x: Double(translation.width) / Double(zoom),
                           y: Double(translation.height) / Double(zoom))
        // Parent absolute origin (constant during the drag).
        let parentOffset = VPoint(x: node.absoluteFrame.origin.x - node.layer.frame.origin.x,
                                  y: node.absoluteFrame.origin.y - node.layer.frame.origin.y)
        let proposedAbs = VRect(
            x: parentOffset.x + base.origin.x + delta.x,
            y: parentOffset.y + base.origin.y + delta.y,
            width: base.width, height: base.height)
        let siblings = store.renderModel.nodes
            .filter { $0.id != node.id && $0.depth == node.depth }
            .map { $0.absoluteFrame }
        let snapped = Snapping.snap(proposedAbs, to: siblings)
        store.snapGuides = snapped.guides
        var frame = snapped.frame

        // Snap to grid (origin) when enabled.
        if snapToGrid {
            frame = CanvasGrid.snap(frame, spacing: gridSize)
        }
        // Snap edges to nearby guides.
        frame.origin = snapToGuides(frame)

        let effectiveDelta = VPoint(
            x: frame.origin.x - (parentOffset.x + base.origin.x),
            y: frame.origin.y - (parentOffset.y + base.origin.y))
        store.moveSelected(byCanvasDelta: effectiveDelta)
    }

    /// Snaps a frame's edges/center to nearby ruler guides (within 6pt).
    private func snapToGuides(_ frame: VRect, threshold: Double = 6) -> VPoint {
        var origin = frame.origin
        for gx in store.verticalGuides {
            for edge in [frame.minX, frame.midX, frame.maxX] where abs(gx - edge) <= threshold {
                origin.x += gx - edge
                break
            }
        }
        for gy in store.horizontalGuides {
            for edge in [frame.minY, frame.midY, frame.maxY] where abs(gy - edge) <= threshold {
                origin.y += gy - edge
                break
            }
        }
        return origin
    }

    private func toggleSelection(_ id: UUID) {
        if NSEvent.modifierFlags.contains(.shift) {
            if store.selection.contains(id) { store.selection.remove(id) }
            else { store.selection.insert(id) }
        } else {
            store.selection = [id]
        }
    }

    private func guideView(_ guide: Snapping.Guide, canvasSize: VSize) -> some View {
        Group {
            switch guide.orientation {
            case .vertical:
                Rectangle().fill(theme.accent).frame(width: 1, height: canvasSize.height)
                    .position(x: guide.position, y: canvasSize.height / 2)
            case .horizontal:
                Rectangle().fill(theme.accent).frame(width: canvasSize.width, height: 1)
                    .position(x: canvasSize.width / 2, y: guide.position)
            }
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            Button { setZoom(CanvasViewport.clampZoom(Double(zoom) - 0.25)) } label: { Image(systemName: "minus.magnifyingglass") }
            Text("\(Int(zoom * 100))%").monospacedDigit().frame(width: 44)
            Button { setZoom(CanvasViewport.clampZoom(Double(zoom) + 0.25)) } label: { Image(systemName: "plus.magnifyingglass") }
            Divider().frame(height: 16)
            Button { setZoom(1) } label: { Text("100%").font(.caption) }.help("Actual size (⌘0… )")
            Button { zoomToFit() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("Zoom to fit")
            Button { zoomToSelection() } label: { Image(systemName: "scope") }
                .help("Zoom to selection").disabled(store.selection.isEmpty)
        }
        .padding(8)
        .background(.thinMaterial, in: Capsule())
        .buttonStyle(.borderless)
    }

    private func setZoom(_ z: Double) { zoom = CGFloat(z); lastZoom = zoom }

    private func zoomToFit() {
        guard viewportSize != .zero else { return }
        setZoom(CanvasViewport.fitZoom(
            content: store.document.canvasSize,
            viewport: VSize(width: Double(viewportSize.width), height: Double(viewportSize.height))))
    }

    private func zoomToSelection() {
        let frames = store.selection.compactMap { LayerTree.absoluteFrame(of: $0, in: store.document.roots) }
        guard let box = CanvasInteraction.boundingBox(of: frames), viewportSize != .zero else { return }
        setZoom(CanvasViewport.zoomToFit(
            box, viewport: VSize(width: Double(viewportSize.width), height: Double(viewportSize.height))))
    }
}

/// Eight-handle resize overlay for the selected layer.
struct SelectionOverlay: View {
    @EnvironmentObject var store: DocumentStore
    let frame: VRect
    let zoom: CGFloat

    var body: some View {
        ZStack {
            ForEach(Array(ResizeHandle.allCases.enumerated()), id: \.offset) { _, handle in
                handleView(handle)
            }
        }
    }

    private func handleView(_ handle: ResizeHandle) -> some View {
        let pos = position(for: handle)
        return Circle()
            .fill(.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
            .frame(width: 9, height: 9)
            .position(x: pos.x, y: pos.y)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        store.beginInteractionIfNeeded()
                        let delta = VPoint(x: Double(value.translation.width) / Double(zoom),
                                           y: Double(value.translation.height) / Double(zoom))
                        store.resizeSelected { base in
                            CanvasInteraction.resize(base, handle: handle, by: delta)
                        }
                    }
                    .onEnded { _ in store.endInteraction() }
            )
    }

    private func position(for handle: ResizeHandle) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: frame.minX, y: frame.minY)
        case .top: return CGPoint(x: frame.midX, y: frame.minY)
        case .topRight: return CGPoint(x: frame.maxX, y: frame.minY)
        case .left: return CGPoint(x: frame.minX, y: frame.midY)
        case .right: return CGPoint(x: frame.maxX, y: frame.midY)
        case .bottomLeft: return CGPoint(x: frame.minX, y: frame.maxY)
        case .bottom: return CGPoint(x: frame.midX, y: frame.maxY)
        case .bottomRight: return CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }
}
