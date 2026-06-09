// This file mirrors the exact shape of code produced by the SwiftUI generator
// for plugin controls. It exists so `swift build` fails if the VUAControls API
// ever drifts from what the code generator emits. Keep it in sync with
// SwiftUIGenerator.controlConstructor.

import SwiftUI
import VUAControls

struct GeneratedSynthPanel: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            // MARK: Cutoff [Knob]
            // AU param: cutoff — 20…20000 Hz, default 1000 Hz
            Group {
                KnobView(value: .constant(1000), in: 20...20000, label: "cutoff")
            }
            .frame(width: 64, height: 64)
            .position(x: 60, y: 60)
            .accessibilityIdentifier("cutoff")

            // MARK: Level [Fader]
            Group {
                FaderView(value: .constant(0), in: -60...6, label: "level")
            }
            .frame(width: 40, height: 180)
            .position(x: 140, y: 110)
            .accessibilityIdentifier("level")

            // MARK: Output [Meter]
            Group {
                MeterView(value: .constant(-12), in: -60...0)
            }
            .frame(width: 24, height: 120)
            .position(x: 200, y: 90)
            .accessibilityIdentifier("output")

            // MARK: Generic [Control]
            Group {
                ControlView(value: .constant(0.5), in: 0...1)
            }
            .frame(width: 100, height: 60)
            .position(x: 280, y: 90)
            .accessibilityIdentifier("generic")
        }
        .frame(width: 360, height: 200, alignment: .topLeading)
    }
}
