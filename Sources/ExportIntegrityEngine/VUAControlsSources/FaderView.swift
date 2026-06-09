import SwiftUI

/// A vertical fader. Drag the cap to change the value.
public struct FaderView: View {
    @Binding private var value: Double
    private let range: ControlRange
    private let label: String?
    @Environment(\.controlTheme) private var theme

    public init(value: Binding<Double>, in range: ControlRange = ControlRange(), label: String? = nil) {
        self._value = value
        self.range = range
        self.label = label
    }

    public init(value: Binding<Double>, in range: ClosedRange<Double>, label: String? = nil) {
        self.init(value: value, in: ControlRange(range.lowerBound, range.upperBound), label: label)
    }

    private var position: Double { range.normalize(value) }

    public var body: some View {
        GeometryReader { geo in
            let capHeight: CGFloat = 16
            let travel = max(0, geo.size.height - capHeight)
            ZStack(alignment: .bottom) {
                Capsule().fill(theme.track).frame(width: 4).frame(maxWidth: .infinity)
                Capsule().fill(theme.accent)
                    .frame(width: 4, height: travel * position + capHeight / 2)
                    .frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: 3).fill(theme.indicator)
                    .frame(height: capHeight)
                    .shadow(radius: 1, y: 1)
                    .offset(y: -travel * position)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let pos = 1 - Double((g.location.y - capHeight / 2) / max(1, travel))
                    value = range.denormalize(pos)
                }
            )
        }
        .accessibilityElement()
        .accessibilityLabel(label ?? "Fader")
        .accessibilityValue(Text(String(format: "%.2f", value)))
    }
}
