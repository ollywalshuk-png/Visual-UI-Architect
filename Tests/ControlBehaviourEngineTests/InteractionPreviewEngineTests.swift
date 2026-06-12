import XCTest
import VUACore
import CodeGenEngine
@testable import ControlBehaviourEngine

final class InteractionPreviewEngineTests: XCTestCase {
    func testModeSwitchingLocksLayoutAndKeepsPreviewValuesSeparate() throws {
        let layer = knob(defaultValue: 50)
        var state = InteractionPreviewState()
        XCTAssertFalse(state.isLayoutLocked)

        state.switchMode(.test)
        XCTAssertTrue(state.isLayoutLocked)
        InteractionPreviewEngine.setValue(75, for: layer, in: &state)

        XCTAssertEqual(state.values[layer.id], 75)
        XCTAssertEqual(layer.control?.defaultValue, 50)

        state.switchMode(.build)
        XCTAssertFalse(state.isLayoutLocked)
        XCTAssertEqual(state.values[layer.id], 75)
    }

    func testKnobDragClampBipolarCenterAndSteppedSnapping() throws {
        let regular = knob(defaultValue: 50)
        let dragged = try XCTUnwrap(InteractionPreviewEngine.dragValue(
            for: regular,
            startingValue: 50,
            translation: VPoint(x: 0, y: -1_000)))
        XCTAssertEqual(dragged, 100)

        let bipolar = Layer(name: "Pan", kind: .knob,
                            control: ControlMetadata(parameterID: "pan", minValue: -100, maxValue: 100,
                                                     defaultValue: 0, unit: .percent,
                                                     behaviourType: ControlBehaviourType.bipolarKnob.rawValue))
        let bipolarResult = try XCTUnwrap(InteractionPreviewEngine.previewResult(for: bipolar, state: .init(mode: .test)))
        XCTAssertEqual(bipolarResult.normalizedValue, 0.5, accuracy: 0.0001)

        let stepped = Layer(name: "Mode", kind: .knob,
                            control: ControlMetadata(parameterID: "mode", minValue: 0, maxValue: 3,
                                                     defaultValue: 1, isContinuous: false, stepCount: 4,
                                                     behaviourType: ControlBehaviourType.steppedKnob.rawValue))
        let steppedValue = try XCTUnwrap(InteractionPreviewEngine.dragValue(
            for: stepped,
            startingValue: 1,
            translation: VPoint(x: 0, y: -50)))
        XCTAssertEqual(steppedValue.rounded(), steppedValue)
    }

    func testSliderFaderButtonToggleMeterAndDisplayFormatting() throws {
        let slider = Layer(name: "Mix", kind: .slider,
                           frame: VRect(x: 0, y: 0, width: 200, height: 28),
                           control: ControlMetadata(parameterID: "mix", minValue: 0, maxValue: 100,
                                                    defaultValue: 50, unit: .percent,
                                                    behaviourType: ControlBehaviourType.horizontalSlider.rawValue))
        XCTAssertEqual(try XCTUnwrap(InteractionPreviewEngine.linearValue(for: slider, localPoint: VPoint(x: 150, y: 14))), 75)

        let fader = Layer(name: "Level", kind: .fader,
                          frame: VRect(x: 0, y: 0, width: 40, height: 180),
                          control: ControlMetadata(parameterID: "level", minValue: -60, maxValue: 6,
                                                   defaultValue: 0, unit: .decibels,
                                                   behaviourType: ControlBehaviourType.verticalFader.rawValue))
        XCTAssertEqual(try XCTUnwrap(InteractionPreviewEngine.linearValue(for: fader, localPoint: VPoint(x: 20, y: 0))), 6)

        let button = Layer(name: "Fire", kind: .button,
                           control: ControlMetadata(parameterID: "fire", minValue: 0, maxValue: 1,
                                                    defaultValue: 0, isContinuous: false, stepCount: 2,
                                                    behaviourType: ControlBehaviourType.buttonPress.rawValue))
        XCTAssertEqual(InteractionPreviewEngine.pressedValue(for: button, isPressed: true), 1)
        XCTAssertEqual(InteractionPreviewEngine.pressedValue(for: button, isPressed: false), 0)

        let toggle = Layer(name: "Bypass", kind: .toggle,
                           control: ControlMetadata(parameterID: "bypass", minValue: 0, maxValue: 1,
                                                    defaultValue: 0, isContinuous: false, stepCount: 2,
                                                    behaviourType: ControlBehaviourType.toggleSwitch.rawValue))
        XCTAssertEqual(InteractionPreviewEngine.toggledValue(for: toggle, currentValue: 0), 1)

        let meter = Layer(name: "Output", kind: .meter,
                          control: ControlMetadata(parameterID: "out", minValue: -60, maxValue: 0,
                                                   defaultValue: -18, unit: .decibels,
                                                   behaviourType: ControlBehaviourType.meterReadout.rawValue,
                                                   interactionMode: ControlInteractionMode.readOnly.rawValue))
        let demo = try XCTUnwrap(InteractionPreviewEngine.demoMeterValue(for: meter, time: 1.2))
        XCTAssertGreaterThanOrEqual(demo, -60)
        XCTAssertLessThanOrEqual(demo, 0)
        XCTAssertEqual(InteractionPreviewEngine.displayString(-18, profile: try XCTUnwrap(ControlBehaviourResolver.profile(for: meter))), "-18.0 dB")
    }

    func testPreviewDiagnosticsAndGeneratedBindings() throws {
        let invalid = Layer(name: "Bad", kind: .slider,
                            frame: VRect(x: 0, y: 0, width: 20, height: 120),
                            control: ControlMetadata(parameterID: "", minValue: 10, maxValue: 1,
                                                     defaultValue: 20,
                                                     behaviourType: ControlBehaviourType.horizontalSlider.rawValue,
                                                     automationEnabled: true))
        let issues = ControlBehaviourDiagnostics.validatePreview(invalid).map(\.code)
        XCTAssertTrue(issues.contains(.invalidRange))
        XCTAssertTrue(issues.contains(.defaultOutOfRange))
        XCTAssertTrue(issues.contains(.missingBinding))
        XCTAssertTrue(issues.contains(.geometryMismatch))

        var generatedKnob = knob(defaultValue: 1_000)
        generatedKnob.control?.bindingName = "viewModel.cutoff"
        let source = try CodeGenService().generate(Document(name: "Generated", roots: [generatedKnob])).contents
        XCTAssertTrue(source.contains("@State private var vua_viewModel_cutoff_"))
        XCTAssertTrue(source.contains("KnobView(value: $vua_viewModel_cutoff_"))
        XCTAssertTrue(source.contains("// Binding target: viewModel.cutoff"))
    }

    private func knob(defaultValue: Double) -> Layer {
        Layer(name: "Cutoff", kind: .knob,
              frame: VRect(x: 0, y: 0, width: 64, height: 64),
              control: ControlMetadata(parameterID: "cutoff", minValue: 0, maxValue: 100,
                                       defaultValue: defaultValue, unit: .percent,
                                       behaviourType: ControlBehaviourType.rotaryKnob.rawValue,
                                       interactionMode: ControlInteractionMode.verticalDragRotary.rawValue,
                                       rotationStartDegrees: -135, rotationEndDegrees: 135))
    }
}
