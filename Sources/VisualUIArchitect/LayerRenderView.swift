import SwiftUI
import VUACore
import ControlBehaviourEngine

/// Renders the visual appearance of a single layer (kind-specific), sized to
/// fill its frame. Positioning is handled by the canvas.
struct LayerRenderView: View {
    let layer: Layer
    let asset: Asset?
    /// Resolved image for the layer's asset (nil when the layer has no asset).
    var resolution: AssetResolver.Resolution?
    var preview: InteractionPreviewResult? = nil

    var body: some View {
        content
            .frame(width: layer.frame.width, height: layer.frame.height)
            .ifLet(layer.assetTransform) { view, transform in
                view
                    .clipped(transform.crop != nil && !(transform.crop?.isIdentity ?? true))
                    .scaleEffect(x: transform.effectiveScaleX, y: transform.effectiveScaleY)
                    .blendMode(transform.blendMode.swiftUI)
            }
            .opacity(layer.style.opacity)
    }

    @ViewBuilder
    private var content: some View {
        switch layer.kind {
        case .button:
            let pressed = (preview?.normalizedValue ?? 0) >= 0.5 && preview?.isActive == true
            ZStack {
                shape.fill(fillColor.opacity(pressed ? 0.72 : 1))
                Text(layer.text ?? layer.name)
                    .font(textFont)
                    .foregroundStyle(layer.style.foregroundColor?.swiftUI ?? .white)
            }
            .scaleEffect(pressed ? 0.97 : 1)
        case .label, .text:
            Text(layer.text ?? layer.name)
                .font(textFont)
                .foregroundStyle(layer.style.foregroundColor?.swiftUI ?? .primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .slider:
            sliderView
        case .knob:
            knobView
        case .fader:
            faderView
        case .meter:
            meterView
        case .toggle:
            let isOn = (preview?.normalizedValue ?? layer.control?.normalizedDefault ?? 1) >= 0.5
            HStack {
                Text(layer.text ?? "Toggle").font(textFont)
                    .foregroundStyle(layer.style.foregroundColor?.swiftUI ?? .primary)
                Spacer(minLength: 4)
                Capsule().fill(isOn ? Color.green : Color.gray.opacity(0.55)).frame(width: 36, height: 20)
                    .overlay(Circle().fill(.white).padding(2), alignment: isOn ? .trailing : .leading)
            }
        case .image:
            imageView
        case .panel, .container, .background, .group:
            if layer.assetID != nil {
                imageView    // asset-backed backplate/panel
            } else {
                shape.fill(fillStyle).overlay(borderOverlay)
            }
        case .shape(let kind):
            shapeContent(kind)
        case .line:
            lineContent
        case .vectorPath:
            vectorPathContent
        case .polygon:
            polygonContent
        case .gradient:
            shape.fill(fillStyle)
        case .mask:
            shape.fill(fillStyle).opacity(0.6)
        case .control, .custom:
            shape.fill(fillStyle).overlay(borderOverlay)
        }
    }

    /// Fill style honouring a gradient when set, otherwise the background colour.
    private var fillStyle: AnyShapeStyle {
        if let g = layer.style.gradient { return AnyShapeStyle(g.swiftUIFill) }
        return AnyShapeStyle(fillColor)
    }

    @ViewBuilder
    private func shapeContent(_ kind: ShapeKind) -> some View {
        switch kind {
        case .rectangle, .card, .divider:
            Rectangle().fill(fillStyle).overlay(shapeStroke(Rectangle()))
        case .roundedRectangle, .callout:
            RoundedRectangle(cornerRadius: max(2, layer.style.cornerRadius))
                .fill(fillStyle).overlay(shapeStroke(RoundedRectangle(cornerRadius: max(2, layer.style.cornerRadius))))
        case .glassPanel:
            RoundedRectangle(cornerRadius: max(2, layer.style.cornerRadius)).fill(.ultraThinMaterial)
        case .ellipse:
            Ellipse().fill(fillStyle).overlay(shapeStroke(Ellipse()))
        case .capsule:
            Capsule().fill(fillStyle).overlay(shapeStroke(Capsule()))
        case .star:
            PolygonShape(spec: PolygonSpec(sides: 5, rotationDegrees: layer.style.rotationDegrees, starInnerRatio: 0.4))
                .fill(fillStyle)
        }
    }

    @ViewBuilder
    private func shapeStroke<S: Shape>(_ s: S) -> some View {
        if let border = layer.style.borderColor, layer.style.borderWidth > 0 {
            s.stroke(border.swiftUI, lineWidth: layer.style.borderWidth)
        }
    }

    private var lineContent: some View {
        let spec = layer.line ?? LineSpec(start: VPoint(x: 0, y: layer.frame.height / 2),
                                          end: VPoint(x: layer.frame.width, y: layer.frame.height / 2))
        let width = layer.style.borderWidth > 0 ? layer.style.borderWidth : 2
        return Path { p in
            p.move(to: CGPoint(x: spec.start.x, y: spec.start.y))
            switch spec.effectiveConnector {
            case .straight:
                p.addLine(to: CGPoint(x: spec.end.x, y: spec.end.y))
            case .curved:
                let c1 = spec.controlPoint1 ?? VPoint(x: layer.frame.width * 0.33, y: spec.start.y)
                let c2 = spec.controlPoint2 ?? VPoint(x: layer.frame.width * 0.66, y: spec.end.y)
                p.addCurve(to: CGPoint(x: spec.end.x, y: spec.end.y),
                           control1: CGPoint(x: c1.x, y: c1.y),
                           control2: CGPoint(x: c2.x, y: c2.y))
            case .elbow:
                p.addLine(to: CGPoint(x: spec.end.x, y: spec.start.y))
                p.addLine(to: CGPoint(x: spec.end.x, y: spec.end.y))
            }
            if spec.arrowStart { addArrowhead(to: &p, tip: spec.start, from: spec.end) }
            if spec.arrowEnd { addArrowhead(to: &p, tip: spec.end, from: spec.start) }
        }
        .stroke(layer.style.borderColor?.swiftUI ?? layer.style.foregroundColor?.swiftUI ?? .primary,
                style: StrokeStyle(lineWidth: width,
                                   lineCap: spec.effectiveCap.swiftUI,
                                   lineJoin: spec.effectiveJoin.swiftUI,
                                   dash: spec.isDotted ? [1, max(2, width * 2)] : (spec.dashed ? [6, 4] : [])))
    }

    private func addArrowhead(to path: inout Path, tip: VPoint, from: VPoint) {
        let angle = atan2(tip.y - from.y, tip.x - from.x)
        let length = 10.0
        let spread = Double.pi / 7
        let a = VPoint(x: tip.x - cos(angle - spread) * length,
                       y: tip.y - sin(angle - spread) * length)
        let c = VPoint(x: tip.x - cos(angle + spread) * length,
                       y: tip.y - sin(angle + spread) * length)
        path.move(to: CGPoint(x: a.x, y: a.y))
        path.addLine(to: CGPoint(x: tip.x, y: tip.y))
        path.addLine(to: CGPoint(x: c.x, y: c.y))
    }

    private var polygonContent: some View {
        PolygonShape(spec: layer.polygon ?? PolygonSpec()).fill(fillStyle)
            .overlay(PolygonShape(spec: layer.polygon ?? PolygonSpec())
                .stroke(layer.style.borderColor?.swiftUI ?? .clear, lineWidth: layer.style.borderWidth))
    }

    private var vectorPathContent: some View {
        let spec = layer.vectorPath ?? VectorPathSpec()
        return Path { p in
            guard let first = spec.anchors.first else { return }
            p.move(to: CGPoint(x: first.point.x, y: first.point.y))
            for (previous, current) in zip(spec.anchors, spec.anchors.dropFirst()) {
                if let c1 = previous.handleOut, let c2 = current.handleIn {
                    p.addCurve(to: CGPoint(x: current.point.x, y: current.point.y),
                               control1: CGPoint(x: c1.x, y: c1.y),
                               control2: CGPoint(x: c2.x, y: c2.y))
                } else {
                    p.addLine(to: CGPoint(x: current.point.x, y: current.point.y))
                }
            }
            if spec.isClosed { p.closeSubpath() }
        }
        .stroke(spec.strokeColor?.swiftUI ?? layer.style.borderColor?.swiftUI ?? .primary,
                lineWidth: spec.strokeWidth > 0 ? spec.strokeWidth : max(1, layer.style.borderWidth))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: layer.style.cornerRadius)
    }

    private var fillColor: Color {
        layer.style.backgroundColor?.swiftUI ?? Color.gray.opacity(0.25)
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if let border = layer.style.borderColor, layer.style.borderWidth > 0 {
            shape.stroke(border.swiftUI, lineWidth: layer.style.borderWidth)
        }
    }

    private var textFont: Font {
        let size = layer.style.fontSize ?? 15
        if let w = layer.style.fontWeight { return .system(size: size).weight(w.swiftUI) }
        return .system(size: size)
    }

    private var sliderView: some View {
        let pos = preview?.normalizedValue ?? layer.control?.normalizedDefault ?? 0.5
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.4)).frame(height: 4)
                Capsule().fill(layer.style.backgroundColor?.swiftUI ?? .accentColor)
                    .frame(width: geo.size.width * pos, height: 4)
                Circle().fill(.white).frame(width: 18, height: 18)
                    .offset(x: geo.size.width * pos - 9)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var knobView: some View {
        let pos = preview?.normalizedValue ?? layer.control?.normalizedDefault ?? 0.5
        let angle = Angle(degrees: preview?.rotationDegrees ?? (-135 + pos * 270))
        return ZStack {
            Circle().fill(fillColor)
            Circle().stroke(Color.white.opacity(0.6), lineWidth: 2)
            Rectangle().fill(Color.white).frame(width: 2, height: layer.frame.height * 0.35)
                .offset(y: -layer.frame.height * 0.15)
                .rotationEffect(angle)
        }
    }

    private var faderView: some View {
        let pos = preview?.normalizedValue ?? layer.control?.normalizedDefault ?? 0.5
        return GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.black.opacity(0.4))
                    .frame(width: 4).frame(maxWidth: .infinity)
                // Cap positioned by the parameter default.
                RoundedRectangle(cornerRadius: 3).fill(Color.white)
                    .frame(width: geo.size.width, height: 14)
                    .offset(y: -(geo.size.height - 14) * pos)
            }
        }
    }

    private var meterView: some View {
        let pos = preview?.normalizedValue ?? 0.65
        return GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.5))
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .bottom, endPoint: .top))
                    .frame(height: geo.size.height * pos)
            }
        }
    }

    @ViewBuilder
    private var imageView: some View {
        switch resolution {
        case .image(let nsImage):
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: layer.frame.width, height: layer.frame.height)
                .clipShape(shape)
        case .missingFile:
            placeholder("Missing file", systemImage: "exclamationmark.triangle", tint: .orange)
        case .decodeFailed:
            placeholder("Can't decode", systemImage: "questionmark.square.dashed", tint: .orange)
        case .none:
            placeholder(asset?.name ?? "No asset", systemImage: "photo", tint: .secondary)
        }
    }

    private func placeholder(_ message: String, systemImage: String, tint: Color) -> some View {
        ZStack {
            shape.fill(Color.gray.opacity(0.2))
            shape.stroke(Color.gray.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4]))
            VStack(spacing: 4) {
                Image(systemName: systemImage).imageScale(.large).foregroundStyle(tint)
                Text(message).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(2).multilineTextAlignment(.center).padding(.horizontal, 4)
            }
        }
    }
}
