import XCTest
import VUACore
@testable import ControlBehaviourEngine

final class BehaviourBindingPlannerTests: XCTestCase {
    func testPlannerCreatesViewModelBindingsForControlsAndActions() {
        let cutoff = Layer(
            name: "Cutoff",
            kind: .knob,
            control: ControlMetadata(
                parameterID: "cutoff",
                displayName: "Cutoff",
                minValue: 20,
                maxValue: 20_000,
                defaultValue: 1_000,
                unit: .hertz,
                behaviourType: ControlBehaviourType.rotaryKnob.rawValue,
                bindingName: "synth.cutoff",
                midiCC: 74,
                auParameterID: "filter.cutoff",
                automationEnabled: true))
        let amount = Layer(
            name: "Amount",
            kind: .slider,
            control: ControlMetadata(
                parameterID: "amount",
                minValue: 0,
                maxValue: 1,
                defaultValue: 0.25,
                behaviourType: ControlBehaviourType.horizontalSlider.rawValue,
                bindingName: "amount"))
        let bypass = Layer(
            name: "Bypass",
            kind: .toggle,
            control: ControlMetadata(
                parameterID: "bypass",
                minValue: 0,
                maxValue: 1,
                defaultValue: 1,
                isContinuous: false,
                behaviourType: ControlBehaviourType.toggleSwitch.rawValue,
                bindingName: "isBypassed"))
        let trigger = Layer(
            name: "Trigger",
            kind: .button,
            control: ControlMetadata(
                parameterID: "trigger",
                isContinuous: false,
                behaviourType: ControlBehaviourType.buttonPress.rawValue,
                bindingName: "trigger"))
        let meter = Layer(
            name: "Output",
            kind: .meter,
            control: ControlMetadata(
                parameterID: "output",
                minValue: -60,
                maxValue: 0,
                defaultValue: -18,
                unit: .decibels,
                behaviourType: ControlBehaviourType.meterReadout.rawValue,
                bindingName: "outputLevel"))
        let nav = Layer(
            name: "Settings",
            kind: .button,
            control: ControlMetadata(
                parameterID: "settings",
                isContinuous: false,
                behaviourType: ControlBehaviourType.buttonPress.rawValue,
                bindingName: "settings"),
            role: .navigation)
        let modal = Layer(
            name: "Preset Sheet",
            kind: .button,
            control: ControlMetadata(
                parameterID: "presets",
                isContinuous: false,
                behaviourType: ControlBehaviourType.buttonPress.rawValue,
                bindingName: "presets"),
            tags: ["modal"])

        let plan = BehaviourBindingPlanner.plan(
            for: Document(name: "Synth Panel", roots: [cutoff, amount, bypass, trigger, meter, nav, modal]))

        XCTAssertEqual(plan.viewModelName, "SynthPanelViewModel")
        XCTAssertTrue(plan.bindings.contains { $0.layerName == "Cutoff" && $0.kind == .value && $0.propertyName == "synthCutoff" })
        XCTAssertTrue(plan.bindings.contains { $0.layerName == "Amount" && $0.kind == .value && $0.propertyName == "amount" })
        XCTAssertTrue(plan.bindings.contains { $0.layerName == "Bypass" && $0.kind == .toggle && $0.valueType == .bool && $0.propertyName == "isBypassed" })
        XCTAssertTrue(plan.bindings.contains { $0.layerName == "Trigger" && $0.kind == .action && $0.actionName == "triggerAction" })
        XCTAssertTrue(plan.bindings.contains { $0.layerName == "Output" && $0.kind == .readOnly && $0.propertyName == "outputLevel" })
        XCTAssertTrue(plan.bindings.contains { $0.layerName == "Settings" && $0.kind == .navigation && $0.actionName == "navigateSettings" })
        XCTAssertTrue(plan.bindings.contains { $0.layerName == "Preset Sheet" && $0.kind == .modal && $0.actionName == "presentPresets" })
        XCTAssertEqual(plan.midiBindings.first?.midiCC, 74)
        XCTAssertEqual(plan.auParameterBindings.first?.auParameterID, "filter.cutoff")

        let source = BehaviourViewModelGenerator.generateSwiftObservableObject(plan: plan)
        XCTAssertTrue(source.contains("final class SynthPanelViewModel: ObservableObject"))
        XCTAssertTrue(source.contains("@Published var synthCutoff: Double = 1000"))
        XCTAssertTrue(source.contains("@Published var isBypassed: Bool = true"))
        XCTAssertTrue(source.contains("func triggerAction()"))
        XCTAssertTrue(source.contains("struct BindingDescriptor: Identifiable, Hashable"))
        XCTAssertTrue(source.contains("let bindingDescriptors: [BindingDescriptor]"))
        XCTAssertTrue(source.contains("BindingDescriptor(id: \""))
        XCTAssertTrue(source.contains("parameterID: \"cutoff\""))
        XCTAssertTrue(source.contains("auParameterID: \"filter.cutoff\""))
        XCTAssertTrue(source.contains("midiCC: 74"))
        XCTAssertTrue(source.contains("automationEnabled: true"))
        XCTAssertTrue(source.contains("var automationParameterIDs: [String]"))
        XCTAssertTrue(source.contains("func binding(forParameterID parameterID: String) -> BindingDescriptor?"))
        XCTAssertTrue(source.contains("func binding(forMIDI cc: Int) -> BindingDescriptor?"))
        XCTAssertTrue(source.contains("func binding(forAUParameterID auParameterID: String) -> BindingDescriptor?"))
        XCTAssertTrue(source.contains("func setDouble(_ propertyName: String, value: Double)"))
        XCTAssertTrue(source.contains("case \"synthCutoff\":"))
        XCTAssertTrue(source.contains("synthCutoff = min(20000, max(20, value))"))
        XCTAssertTrue(source.contains("func setBool(_ propertyName: String, value: Bool)"))
        XCTAssertTrue(source.contains("case \"isBypassed\":"))
        XCTAssertTrue(source.contains("func perform(action actionName: String)"))
        XCTAssertTrue(source.contains("case \"triggerAction\":"))
        XCTAssertTrue(source.contains("triggerAction()"))
        XCTAssertTrue(source.contains("\"cutoff\": 74"))
        XCTAssertTrue(source.contains("\"cutoff\": \"filter.cutoff\""))
    }
}
