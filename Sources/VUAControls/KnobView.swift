import SwiftUI

/// A rotary knob control. Vertical drag changes the value; the indicator and
/// arc sweep from −135° to +135°.
public struct KnobView: View {
    @Binding private var value: Double
    private let range: ControlRange
    private let label: String?
    @Environment(\.controlTheme) private var theme
    @State private var dragStartValue: Double?

    public init(value: Binding<Double>, in range: ControlRange = ControlRange(), label: String? = nil) {
        self._value = value
        self.range = range
        self.label = label
    }

    /// Convenience for `ClosedRange` call sites (used by generated code).
    public init(value: Binding<Double>, in range: ClosedRange<Double>, label: String? = nil) {
        self.init(value: value, in: ControlRange(range.lowerBound, range.upperBound), label: label)
    }

    private var position: Double { range.normalize(value) }
    private var angle: Angle { .degrees(-135 + position * 270) }

    public var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ZStack {
                    Circle().fill(theme.track)
                    Circle().trim(from: 0, to: 0.75)
                        .stroke(theme.track.opacity(0.6), style: .init(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(135))
                    Circle().trim(from: 0, to: 0.75 * position)
                        .stroke(theme.accent, style: .init(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(135))
                    Capsule().fill(theme.indicator)
                        .frame(width: 2.5, height: side * 0.32)
                        .offset(y: -side * 0.18)
                        .rotationEffect(angle)
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(drag(side: side))
            }
            if let label { Text(label).font(.caption2).foregroundStyle(.secondary) }
        }
        .accessibilityElement()
        .accessibilityLabel(label ?? "Knob")
        .accessibilityValue(Text(String(format: "%.2f", value)))
    }

    private func drag(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if dragStartValue == nil { dragStartValue = value }
                // Up = increase. One knob height of travel sweeps the full range.
                let delta = Double(-g.translation.height) / Double(max(60, side * 2))
                let newPos = range.normalize(dragStartValue ?? value) + delta
                value = range.denormalize(newPos)
            }
            .onEnded { _ in dragStartValue = nil }
    }
}
