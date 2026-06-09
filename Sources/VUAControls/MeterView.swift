import SwiftUI

/// A vertical level meter driven by a read-only value (e.g. output level).
public struct MeterView: View {
    private let value: Double
    private let range: ControlRange
    @Environment(\.controlTheme) private var theme

    public init(value: Double, in range: ControlRange = ControlRange()) {
        self.value = value
        self.range = range
    }

    public init(value: Double, in range: ClosedRange<Double>) {
        self.init(value: value, in: ControlRange(range.lowerBound, range.upperBound))
    }

    /// Binding-based initializer so generated code can use `.constant(_)`.
    public init(value: Binding<Double>, in range: ClosedRange<Double>) {
        self.init(value: value.wrappedValue, in: ControlRange(range.lowerBound, range.upperBound))
    }

    private var level: Double { range.normalize(value) }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3).fill(theme.track)
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [.green, .yellow, .red],
                                         startPoint: .bottom, endPoint: .top))
                    .frame(height: geo.size.height * level)
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Level meter")
        .accessibilityValue(Text(String(format: "%.0f%%", level * 100)))
    }
}

/// Generic control placeholder for `.control`/custom kinds emitted by codegen.
public struct ControlView: View {
    @Binding private var value: Double
    private let range: ControlRange
    @Environment(\.controlTheme) private var theme

    public init(value: Binding<Double>, in range: ControlRange = ControlRange()) {
        self._value = value
        self.range = range
    }

    public init(value: Binding<Double>, in range: ClosedRange<Double>) {
        self.init(value: value, in: ControlRange(range.lowerBound, range.upperBound))
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(theme.track)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.accent.opacity(0.5)))
    }
}
