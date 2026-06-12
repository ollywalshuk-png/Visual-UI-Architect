import SwiftUI
import VUACore
import ControlBehaviourEngine

/// Inspector for the selected layer: identity, geometry, and style. Edits flow
/// through the store so they participate in undo/redo and validation.
struct InspectorView: View {
    @EnvironmentObject var store: DocumentStore

    var body: some View {
        if let layer = store.canSelectSingle {
            Form {
                Section("Identity") {
                    LabeledContent("Name") {
                        TextField("Name", text: nameBinding(layer))
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Kind") { Text(layer.kind.displayName).foregroundStyle(.secondary) }
                    if isTextBearing(layer.kind) {
                        LabeledContent("Text") {
                            TextField("Text", text: textBinding(layer))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                componentVariantSection(layer)

                importProvenanceSection

                Section("Geometry") {
                    numberRow("X", \.frame.origin.x, layer)
                    numberRow("Y", \.frame.origin.y, layer)
                    numberRow("Width", \.frame.size.width, layer)
                    numberRow("Height", \.frame.size.height, layer)
                }

                Section("Appearance") {
                    colorRow("Background", background(layer))
                    colorRow("Foreground", foreground(layer))
                    numberRow("Corner Radius", \.style.cornerRadius, layer)
                    sliderRow("Opacity", \.style.opacity, layer, range: 0...1)
                }

                tokenSection(layer)

                effectsSection(layer)

                if layer.kind == .gradient || layer.style.gradient != nil {
                    gradientSection(layer)
                }

                if layer.kind == .line {
                    lineSection(layer)
                }

                if layer.kind == .vectorPath {
                    vectorPathSection(layer)
                }

                organisationSection(layer)

                constraintsSection(layer)

                if layer.kind.isPluginControl || InteractionPreviewEngine.supportsInteraction(layer.kind) {
                    controlSection(layer)
                    behaviourSection(layer)
                }

                if layer.kind == .image || layer.kind == .background {
                    transformSection(layer)
                    paintSection(layer)
                    assetSection(layer)
                }
            }
            .formStyle(.grouped)
        } else if store.selection.count > 1 {
            VStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up").font(.largeTitle).foregroundStyle(.secondary)
                Text("\(store.selection.count) layers selected")
                AlignmentControls()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            ContentUnavailableViewCompat(
                title: "No Selection",
                systemImage: "cursorarrow.rays",
                description: "Select a layer to edit its properties.")
        }
    }

    @ViewBuilder
    private func componentVariantSection(_ layer: Layer) -> some View {
        if let componentID = layer.componentID,
           let component = store.components.first(where: { $0.id == componentID }) {
            Section("Component Variant") {
                LabeledContent("Component") { Text(component.name) }
                Picker("Variant", selection: Binding(
                    get: { layer.componentVariantID },
                    set: { store.switchSelectedComponentVariant(to: $0) })) {
                    Text("Base").tag(Optional<UUID>.none)
                    ForEach(component.variants) { variant in
                        Text(variant.name).tag(Optional(variant.id))
                    }
                }
                .pickerStyle(.menu)
                LabeledContent("Overrides") { Text("\(layer.componentOverrides.count)") }
                LabeledContent("Locked") { Text("\(layer.lockedComponentProperties.count)") }
                HStack {
                    Button("Override Size") {
                        store.addOverrideToSelectedComponent(property: "frame.size",
                                                             value: "\(Int(layer.frame.width))x\(Int(layer.frame.height))")
                    }
                    Button("Lock Size") { store.lockSelectedComponentProperty("frame.size") }
                }
                if !layer.componentOverrides.isEmpty {
                    ForEach(layer.componentOverrides) { override in
                        Label("\(override.property): \(override.valueDescription)", systemImage: "slider.horizontal.3")
                            .font(.caption)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tokenSection(_ layer: Layer) -> some View {
        if !store.designTokens.isEmpty || !layer.style.tokens.isEmpty {
            Section("Design Tokens") {
                if layer.style.tokens.isEmpty {
                    Text("No token references").foregroundStyle(.secondary)
                } else {
                    ForEach(tokenLabels(for: layer), id: \.self) { label in
                        Label(label, systemImage: "tag")
                            .font(.caption)
                    }
                }
                Menu("Apply Token") {
                    ForEach(store.designTokens) { token in
                        Button(token.name) { store.applyTokenToSelection(token) }
                    }
                }
                .disabled(store.designTokens.isEmpty)
            }
        }
    }

    private func tokenLabels(for layer: Layer) -> [String] {
        let refs = layer.style.tokens
        let pairs: [(String, UUID?)] = [
            ("Background", refs.backgroundColor),
            ("Foreground", refs.foregroundColor),
            ("Type", refs.typography),
            ("Spacing", refs.spacing),
            ("Radius", refs.cornerRadius),
            ("Shadow", refs.shadow),
            ("Gradient", refs.gradient),
            ("Material", refs.material)
        ]
        return pairs.compactMap { label, id in
            guard let id, let token = store.document.designToken(id: id) else { return nil }
            return "\(label): \(token.name)"
        }
    }

    @ViewBuilder
    private var importProvenanceSection: some View {
        if let path = store.importedSourcePath {
            Section("Source Provenance") {
                LabeledContent("View") { Text(store.importedViewName ?? "Imported UI") }
                LabeledContent("Source") {
                    Text(path).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                }
                LabeledContent("Anchors") {
                    Text(store.importedSourceHasAnchors == false ? "Missing" : "Present")
                        .foregroundStyle(store.importedSourceHasAnchors == false ? .orange : .secondary)
                }
                if let date = store.importedAt {
                    LabeledContent("Imported") { Text(date.formatted(date: .abbreviated, time: .shortened)) }
                }
            }
        }
    }

    // MARK: - Line section

    @ViewBuilder
    private func lineSection(_ layer: Layer) -> some View {
        let line = layer.line ?? LineSpec(start: VPoint(x: 0, y: layer.frame.height / 2),
                                          end: VPoint(x: layer.frame.width, y: layer.frame.height / 2))
        Section("Line") {
            LabeledContent("Start X") {
                TextField("0", value: Binding(
                    get: { line.start.x },
                    set: { v in store.updateSelectedLine { $0.start.x = v } }),
                    format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 80)
            }
            LabeledContent("Start Y") {
                TextField("0", value: Binding(
                    get: { line.start.y },
                    set: { v in store.updateSelectedLine { $0.start.y = v } }),
                    format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 80)
            }
            LabeledContent("End X") {
                TextField("0", value: Binding(
                    get: { line.end.x },
                    set: { v in store.updateSelectedLine { $0.end.x = v } }),
                    format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 80)
            }
            LabeledContent("End Y") {
                TextField("0", value: Binding(
                    get: { line.end.y },
                    set: { v in store.updateSelectedLine { $0.end.y = v } }),
                    format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 80)
            }
            Toggle("Dashed", isOn: Binding(
                get: { line.dashed },
                set: { v in store.updateSelectedLine { $0.dashed = v; if v { $0.dotted = false } } }))
            Toggle("Dotted", isOn: Binding(
                get: { line.isDotted },
                set: { v in store.updateSelectedLine { $0.dotted = v; if v { $0.dashed = false } } }))
            LabeledContent("Cap") {
                Picker("", selection: Binding(
                    get: { line.effectiveCap },
                    set: { v in store.updateSelectedLine { $0.lineCap = v } })) {
                    ForEach(LineCapStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.labelsHidden()
            }
            LabeledContent("Join") {
                Picker("", selection: Binding(
                    get: { line.effectiveJoin },
                    set: { v in store.updateSelectedLine { $0.lineJoin = v } })) {
                    ForEach(LineJoinStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.labelsHidden()
            }
            Toggle("Arrow Start", isOn: Binding(
                get: { line.arrowStart },
                set: { v in store.updateSelectedLine { $0.arrowStart = v } }))
            Toggle("Arrow End", isOn: Binding(
                get: { line.arrowEnd },
                set: { v in store.updateSelectedLine { $0.arrowEnd = v } }))
            Toggle("Divider Mode", isOn: Binding(
                get: { line.isDivider },
                set: { v in store.updateSelectedLine { $0.dividerMode = v } }))
            LabeledContent("Connector") {
                Picker("", selection: Binding(
                    get: { line.effectiveConnector },
                    set: { v in store.updateSelectedLine { $0.connectorMode = v } })) {
                    ForEach(LineConnectorMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.labelsHidden()
            }
            LabeledContent("Snap") {
                Picker("", selection: Binding(
                    get: { line.effectiveSnap },
                    set: { v in store.updateSelectedLine { $0.snapMode = v } })) {
                    ForEach(LineSnapMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func vectorPathSection(_ layer: Layer) -> some View {
        let path = layer.vectorPath ?? VectorPathSpec()
        Section("Vector Path") {
            Toggle("Closed Path", isOn: Binding(
                get: { path.isClosed },
                set: { v in store.updateSelectedLayer { $0.vectorPath = path.with(isClosed: v) } }))
            LabeledContent("Anchors") { Text("\(path.anchors.count)") }
            LabeledContent("Stroke Width") {
                TextField("1", value: Binding(
                    get: { path.strokeWidth },
                    set: { v in store.updateSelectedLayer { $0.vectorPath = path.with(strokeWidth: max(0, v)) } }),
                    format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 80)
            }
            colorRow("Stroke", Binding(
                get: { path.strokeColor?.swiftUI ?? .primary },
                set: { v in store.updateSelectedLayer { $0.vectorPath = path.with(strokeColor: v.vColor) } }))
            Toggle("Fill Enabled", isOn: Binding(
                get: { path.fillColor != nil },
                set: { v in store.updateSelectedLayer { $0.vectorPath = path.with(fillColor: v ? .some(path.fillColor ?? .white) : .some(nil)) } }))
            if path.fillColor != nil {
                colorRow("Fill", Binding(
                    get: { path.fillColor?.swiftUI ?? .clear },
                    set: { v in store.updateSelectedLayer { $0.vectorPath = path.with(fillColor: v.vColor) } }))
            }
        }
    }

    // MARK: - Bindings

    private func nameBinding(_ layer: Layer) -> Binding<String> {
        Binding(get: { layer.name }, set: { v in store.updateSelectedLayer { $0.name = v } })
    }

    private func textBinding(_ layer: Layer) -> Binding<String> {
        Binding(get: { layer.text ?? "" }, set: { v in store.updateSelectedLayer { $0.text = v } })
    }

    private func numberRow(_ title: String, _ keyPath: WritableKeyPath<Layer, Double>, _ layer: Layer) -> some View {
        LabeledContent(title) {
            TextField(title, value: Binding(
                get: { layer[keyPath: keyPath] },
                set: { v in store.updateSelectedLayer { $0[keyPath: keyPath] = v } }
            ), format: .number.precision(.fractionLength(0...1)))
            .textFieldStyle(.roundedBorder)
            .frame(width: 90)
        }
    }

    private func sliderRow(_ title: String, _ keyPath: WritableKeyPath<Layer, Double>, _ layer: Layer, range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            Slider(value: Binding(
                get: { layer[keyPath: keyPath] },
                set: { v in store.updateSelectedLayer { $0[keyPath: keyPath] = v } }
            ), in: range)
            .frame(width: 120)
        }
    }

    private func background(_ layer: Layer) -> Binding<Color> {
        Binding(
            get: { layer.style.backgroundColor?.swiftUI ?? .clear },
            set: { v in store.updateSelectedLayer { $0.style.backgroundColor = v.vColor } })
    }

    private func foreground(_ layer: Layer) -> Binding<Color> {
        Binding(
            get: { layer.style.foregroundColor?.swiftUI ?? .primary },
            set: { v in store.updateSelectedLayer { $0.style.foregroundColor = v.vColor } })
    }

    private func colorRow(_ title: String, _ binding: Binding<Color>) -> some View {
        LabeledContent(title) { ColorPicker("", selection: binding, supportsOpacity: true).labelsHidden() }
    }

    private func isTextBearing(_ kind: LayerKind) -> Bool {
        switch kind { case .label, .text, .button, .toggle: return true; default: return false }
    }

    // MARK: - Asset transform section

    @ViewBuilder
    private func transformSection(_ layer: Layer) -> some View {
        let transform = layer.assetTransform ?? AssetTransformSpec()
        let crop = transform.crop ?? CropSpec()
        Section("Asset Transform") {
            LabeledContent("Scale X") {
                TextField("1", value: Binding(
                    get: { transform.scaleX },
                    set: { v in updateAssetTransform { $0.scaleX = max(0.01, v) } }),
                    format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder).frame(width: 80)
            }
            LabeledContent("Scale Y") {
                TextField("1", value: Binding(
                    get: { transform.scaleY },
                    set: { v in updateAssetTransform { $0.scaleY = max(0.01, v) } }),
                    format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder).frame(width: 80)
            }
            Toggle("Flip Horizontal", isOn: Binding(
                get: { transform.flipHorizontal },
                set: { v in updateAssetTransform { $0.flipHorizontal = v } }))
            Toggle("Flip Vertical", isOn: Binding(
                get: { transform.flipVertical },
                set: { v in updateAssetTransform { $0.flipVertical = v } }))
            LabeledContent("Blend") {
                Picker("", selection: Binding(
                    get: { transform.blendMode },
                    set: { v in updateAssetTransform { $0.blendMode = v } })) {
                    ForEach(LayerBlendMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.labelsHidden()
            }
            Toggle("Crop Enabled", isOn: Binding(
                get: { transform.crop != nil },
                set: { enabled in updateAssetTransform { $0.crop = enabled ? CropSpec() : nil } }))
            if transform.crop != nil {
                LabeledContent("Crop X") { cropField(crop.x) { v in updateAssetTransform { $0.crop = crop.with(x: v) } } }
                LabeledContent("Crop Y") { cropField(crop.y) { v in updateAssetTransform { $0.crop = crop.with(y: v) } } }
                LabeledContent("Crop W") { cropField(crop.width) { v in updateAssetTransform { $0.crop = crop.with(width: v) } } }
                LabeledContent("Crop H") { cropField(crop.height) { v in updateAssetTransform { $0.crop = crop.with(height: v) } } }
            }
            LabeledContent("Texture Hook") {
                TextField("texture id", text: Binding(
                    get: { transform.textureOverlayID ?? "" },
                    set: { v in updateAssetTransform { $0.textureOverlayID = v.isEmpty ? nil : v } }))
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func updateAssetTransform(_ change: @escaping (inout AssetTransformSpec) -> Void) {
        store.updateSelectedLayer { layer in
            var transform = layer.assetTransform ?? AssetTransformSpec()
            change(&transform)
            layer.assetTransform = transform.isIdentity ? nil : transform
        }
    }

    private func cropField(_ value: Double, set: @escaping (Double) -> Void) -> some View {
        TextField("0...1", value: Binding(get: { value }, set: { set(min(1, max(0, $0))) }),
                  format: .number.precision(.fractionLength(0...2)))
        .textFieldStyle(.roundedBorder).frame(width: 80)
    }

    // MARK: - Raster paint section

    @ViewBuilder
    private func paintSection(_ layer: Layer) -> some View {
        let paint = layer.rasterPaint ?? RasterPaintSpec()
        Section("Raster Paint") {
            Toggle("Paint Mode", isOn: Binding(
                get: { paint.isPaintModeEnabled },
                set: { v in updateRasterPaint { $0.isPaintModeEnabled = v } }))
            LabeledContent("Tool") {
                Picker("", selection: Binding(
                    get: { paint.activeBrush.tool },
                    set: { v in updateRasterPaint { $0.activeBrush.tool = v } })) {
                    ForEach(RasterPaintTool.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.labelsHidden()
            }
            LabeledContent("Size") {
                TextField("12", value: Binding(
                    get: { paint.activeBrush.size },
                    set: { v in updateRasterPaint { $0.activeBrush.size = max(1, v) } }),
                    format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 80)
            }
            LabeledContent("Opacity") {
                Slider(value: Binding(
                    get: { paint.activeBrush.opacity },
                    set: { v in updateRasterPaint { $0.activeBrush.opacity = v } }), in: 0...1)
                .frame(width: 120)
            }
            LabeledContent("Hardness") {
                Slider(value: Binding(
                    get: { paint.activeBrush.hardness },
                    set: { v in updateRasterPaint { $0.activeBrush.hardness = v } }), in: 0...1)
                .frame(width: 120)
            }
            colorRow("Brush Color", Binding(
                get: { paint.activeBrush.color.swiftUI },
                set: { v in updateRasterPaint { $0.activeBrush.color = v.vColor } }))
            Text("\(paint.strokes.count) stroke\(paint.strokes.count == 1 ? "" : "s") · original asset preserved")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func updateRasterPaint(_ change: @escaping (inout RasterPaintSpec) -> Void) {
        store.updateSelectedLayer { layer in
            var paint = layer.rasterPaint ?? RasterPaintSpec()
            change(&paint)
            layer.rasterPaint = paint
        }
    }

    // MARK: - AU parameter (plugin control) section

    @ViewBuilder
    private func controlSection(_ layer: Layer) -> some View {
        let c = layer.control ?? ControlMetadata(parameterID: layer.name.lowercased())
        Section("AU Parameter") {
            LabeledContent("Param ID") {
                TextField("id", text: Binding(
                    get: { c.parameterID },
                    set: { v in store.updateSelectedControl { $0.parameterID = v } }))
                .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Display") {
                TextField("name", text: Binding(
                    get: { c.displayName },
                    set: { v in store.updateSelectedControl { $0.displayName = v } }))
                .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Min") {
                TextField("Min", value: Binding(
                    get: { c.minValue },
                    set: { v in store.updateSelectedControl { $0.minValue = v } }),
                    format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder).frame(width: 90)
            }
            LabeledContent("Max") {
                TextField("Max", value: Binding(
                    get: { c.maxValue },
                    set: { v in store.updateSelectedControl { $0.maxValue = v } }),
                    format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder).frame(width: 90)
            }
            LabeledContent("Default") {
                TextField("Default", value: Binding(
                    get: { c.defaultValue },
                    set: { v in store.updateSelectedControl { $0.defaultValue = $0.clamp(v) } }),
                    format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder).frame(width: 90)
            }
            LabeledContent("Unit") {
                Picker("", selection: Binding(
                    get: { c.unit },
                    set: { v in store.updateSelectedControl { $0.unit = v } })) {
                    ForEach(ControlUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
            }
            Toggle("Continuous", isOn: Binding(
                get: { c.isContinuous },
                set: { v in store.updateSelectedControl { $0.isContinuous = v } }))
            if !c.isContinuous {
                LabeledContent("Steps") {
                    TextField("steps", value: Binding(
                        get: { c.stepCount ?? 2 },
                        set: { v in store.updateSelectedControl { $0.stepCount = v } }), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 60)
                }
            }
        }
    }

    // MARK: - Behaviour section

    @ViewBuilder
    private func behaviourSection(_ layer: Layer) -> some View {
        let c = layer.control ?? ControlBehaviourResolver.defaultMetadata(for: layer.kind, name: layer.name)
            ?? ControlMetadata(parameterID: layer.name.lowercased())
        let behaviour = ControlBehaviourResolver.profile(for: layer)
        let preview = store.previewResult(for: layer)
        let status = InteractionPreviewEngine.status(for: layer)
        Section("Behaviour") {
            LabeledContent("Status") {
                Text(status.displayName)
                    .foregroundStyle(statusColor(status))
            }
            if let preview {
                LabeledContent(store.isTestMode ? "Current Preview" : "Default Preview") {
                    Text(preview.displayText).monospacedDigit()
                }
                if store.isTestMode {
                    HStack {
                        Button("Reset Preview") { store.resetPreviewValue(for: layer) }
                        Button("Apply Preview Value") { store.applyPreviewValueToSelectedDefault() }
                            .disabled(store.previewState.values[layer.id] == nil)
                    }
                }
            }
            if let behaviour {
                LabeledContent("Drag Axis") { Text(behaviour.dragAxis.rawValue.capitalized) }
                LabeledContent("Snap") { Text(behaviour.snapBehaviour.rawValue.capitalized) }
            }
            LabeledContent("Type") {
                Picker("", selection: Binding(
                    get: { ControlBehaviourType(rawValue: c.behaviourType ?? "") ?? behaviour?.type ?? .horizontalSlider },
                    set: { v in store.updateSelectedControl { meta in
                        meta.behaviourType = v.rawValue
                        applyBehaviourDefaults(v, to: &meta)
                    } })) {
                    ForEach(ControlBehaviourType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
            }
            LabeledContent("Interaction") {
                Picker("", selection: Binding(
                    get: { ControlInteractionMode(rawValue: c.interactionMode ?? "") ?? behaviour?.interactionMode ?? .linearDrag },
                    set: { v in store.updateSelectedControl { $0.interactionMode = v.rawValue } })) {
                    ForEach(ControlInteractionMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
            }
            LabeledContent("Response") {
                Picker("", selection: Binding(
                    get: { ControlResponseCurve(rawValue: c.responseCurve ?? "") ?? behaviour?.responseCurve ?? .linear },
                    set: { v in store.updateSelectedControl { $0.responseCurve = v.rawValue } })) {
                    ForEach(ControlResponseCurve.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .labelsHidden()
            }
            if c.behaviourType == ControlBehaviourType.rotaryKnob.rawValue ||
                c.behaviourType == ControlBehaviourType.steppedKnob.rawValue ||
                c.behaviourType == ControlBehaviourType.bipolarKnob.rawValue ||
                c.behaviourType == ControlBehaviourType.endlessEncoder.rawValue ||
                layer.kind == .knob {
                LabeledContent("Start Angle") {
                    TextField("-135", value: Binding(
                        get: { c.rotationStartDegrees ?? -135 },
                        set: { v in store.updateSelectedControl { $0.rotationStartDegrees = v } }),
                        format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder).frame(width: 80)
                }
                LabeledContent("End Angle") {
                    TextField("135", value: Binding(
                        get: { c.rotationEndDegrees ?? 135 },
                        set: { v in store.updateSelectedControl { $0.rotationEndDegrees = v } }),
                        format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder).frame(width: 80)
                }
            }
            LabeledContent("Binding") {
                TextField("state or AU binding", text: Binding(
                    get: { c.bindingName ?? "" },
                    set: { v in store.updateSelectedControl { $0.bindingName = v.isEmpty ? nil : v } }))
                .textFieldStyle(.roundedBorder)
            }
            LabeledContent("AU ID") {
                TextField("au parameter id", text: Binding(
                    get: { c.auParameterID ?? "" },
                    set: { v in store.updateSelectedControl { $0.auParameterID = v.isEmpty ? nil : v } }))
                .textFieldStyle(.roundedBorder)
            }
            LabeledContent("MIDI CC") {
                TextField("0...127", text: Binding(
                    get: { c.midiCC.map(String.init) ?? "" },
                    set: { v in store.updateSelectedControl { $0.midiCC = Int(v.trimmingCharacters(in: .whitespacesAndNewlines)) } }))
                .textFieldStyle(.roundedBorder).frame(width: 80)
            }
            Toggle("Automation Enabled", isOn: Binding(
                get: { c.automationEnabled ?? false },
                set: { v in store.updateSelectedControl { $0.automationEnabled = v } }))

            let issues = store.isTestMode
                ? ControlBehaviourDiagnostics.validatePreview(layer)
                : ControlBehaviourDiagnostics.validate(layer)
            ForEach(issues) { issue in
                Label(issue.message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func applyBehaviourDefaults(_ type: ControlBehaviourType, to meta: inout ControlMetadata) {
        meta.interactionMode = nil
        switch type {
        case .rotaryKnob:
            meta.isContinuous = true; meta.stepCount = nil
            meta.rotationStartDegrees = meta.rotationStartDegrees ?? -135
            meta.rotationEndDegrees = meta.rotationEndDegrees ?? 135
        case .endlessEncoder:
            meta.isContinuous = true; meta.stepCount = nil
            meta.rotationStartDegrees = -180; meta.rotationEndDegrees = 180
            meta.interactionMode = ControlInteractionMode.relative.rawValue
        case .steppedKnob:
            meta.isContinuous = false; meta.stepCount = meta.stepCount ?? 12
            meta.interactionMode = ControlInteractionMode.steppedSelector.rawValue
        case .bipolarKnob:
            meta.isContinuous = true; meta.responseCurve = ControlResponseCurve.bipolar.rawValue
            if meta.minValue >= 0 { meta.minValue = -abs(meta.maxValue) }
            if meta.defaultValue < meta.minValue || meta.defaultValue > meta.maxValue { meta.defaultValue = 0 }
        case .verticalFader, .horizontalSlider:
            meta.isContinuous = true; meta.stepCount = nil
            meta.interactionMode = ControlInteractionMode.linearDrag.rawValue
        case .buttonPress:
            meta.minValue = 0; meta.maxValue = 1; meta.defaultValue = 0
            meta.isContinuous = false; meta.stepCount = 2
            meta.interactionMode = ControlInteractionMode.press.rawValue
        case .toggleSwitch:
            meta.minValue = 0; meta.maxValue = 1; meta.defaultValue = 1
            meta.isContinuous = false; meta.stepCount = 2
            meta.interactionMode = ControlInteractionMode.toggle.rawValue
        case .meterReadout:
            meta.isContinuous = true; meta.stepCount = nil
            meta.interactionMode = ControlInteractionMode.readOnly.rawValue
        }
    }

    private func statusColor(_ status: InteractionFunctionalStatus) -> Color {
        switch status {
        case .functional: return .green
        case .partiallyFunctional: return .orange
        case .visualOnly: return .secondary
        case .missingBehaviour: return .red
        }
    }

    // MARK: - Effects section (rotation / shadow / blur)

    @ViewBuilder
    private func effectsSection(_ layer: Layer) -> some View {
        Section("Effects") {
            LabeledContent("Rotation°") {
                TextField("0", value: Binding(
                    get: { layer.style.rotationDegrees },
                    set: { v in store.updateSelectedStyle { $0.rotationDegrees = v } }),
                    format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 80)
            }
            LabeledContent("Blur") {
                Slider(value: Binding(
                    get: { layer.style.blurRadius },
                    set: { v in store.updateSelectedStyle { $0.blurRadius = v } }), in: 0...40)
                .frame(width: 130)
            }
            Toggle("Drop Shadow", isOn: Binding(
                get: { layer.style.shadow != nil },
                set: { on in store.updateSelectedStyle { $0.shadow = on ? ShadowSpec() : nil } }))
            if let stroke = layer.style.borderColor {
                LabeledContent("Stroke") {
                    ColorPicker("", selection: Binding(
                        get: { stroke.swiftUI },
                        set: { v in store.updateSelectedStyle { $0.borderColor = v.vColor } }), supportsOpacity: true)
                    .labelsHidden()
                }
            }
            LabeledContent("Stroke Width") {
                TextField("0", value: Binding(
                    get: { layer.style.borderWidth },
                    set: { v in store.updateSelectedStyle { $0.borderWidth = v; if $0.borderColor == nil && v > 0 { $0.borderColor = .white } } }),
                    format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 80)
            }
        }
    }

    // MARK: - Gradient section

    @ViewBuilder
    private func gradientSection(_ layer: Layer) -> some View {
        let g = layer.style.gradient ?? GradientSpec()
        Section("Gradient") {
            LabeledContent("Type") {
                Picker("", selection: Binding(
                    get: { g.kind },
                    set: { v in store.updateSelectedStyle { $0.gradient = GradientSpec(kind: v, stops: g.stops, startPoint: g.startPoint, endPoint: g.endPoint) } })) {
                    ForEach(GradientSpec.Kind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.labelsHidden()
            }
            ForEach(Array(g.stops.enumerated()), id: \.offset) { idx, stop in
                LabeledContent("Stop \(idx + 1)") {
                    ColorPicker("", selection: Binding(
                        get: { stop.color.swiftUI },
                        set: { v in
                            var stops = g.stops
                            stops[idx] = GradientStop(color: v.vColor, location: stop.location)
                            store.updateSelectedStyle { $0.gradient = GradientSpec(kind: g.kind, stops: stops, startPoint: g.startPoint, endPoint: g.endPoint) }
                        }), supportsOpacity: true).labelsHidden()
                }
            }
        }
    }

    // MARK: - Organisation (role / notes / tags)

    @ViewBuilder
    private func organisationSection(_ layer: Layer) -> some View {
        Section("Organisation") {
            LabeledContent("Role") {
                Picker("", selection: Binding(
                    get: { layer.role },
                    set: { store.setSelectedRole($0) })) {
                    Text("None").tag(LayerRole?.none)
                    ForEach(LayerRole.allCases, id: \.self) { Text($0.displayName).tag(LayerRole?.some($0)) }
                }.labelsHidden()
            }
            Toggle("Accessibility Hidden", isOn: Binding(
                get: { layer.isAccessibilityHidden },
                set: { v in store.updateSelectedLayer { $0.isAccessibilityHidden = v } }))
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes").font(.caption).foregroundStyle(.secondary)
                TextField("Notes", text: Binding(
                    get: { layer.notes ?? "" },
                    set: { store.setSelectedNotes($0) }), axis: .vertical)
                .lineLimit(1...4).textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Constraints section

    @ViewBuilder
    private func constraintsSection(_ layer: Layer) -> some View {
        Section("Constraints") {
            // Pin edges (Auto Layout style).
            HStack(spacing: 6) {
                pinButton("Leading", "arrow.left.to.line", .leading)
                pinButton("Top", "arrow.up.to.line", .top)
                pinButton("Trailing", "arrow.right.to.line", .trailing)
                pinButton("Bottom", "arrow.down.to.line", .bottom)
            }
            HStack(spacing: 6) {
                pinButton("Center X", "arrow.left.and.right", .centerX)
                pinButton("Center Y", "arrow.up.and.down", .centerY)
                pinButton("Width", "arrow.left.and.right.square", .width)
                pinButton("Height", "arrow.up.and.down.square", .height)
            }
            HStack {
                Button("Resolve") { store.resolveSelectedConstraints() }
                    .disabled(layer.constraints.isEmpty)
                    .help("Re-lay this layer from its constraints for the current size")
                Spacer()
                Button("Clear", role: .destructive) { store.clearConstraints() }
                    .disabled(layer.constraints.isEmpty)
            }
            if !layer.constraints.isEmpty {
                Text(layer.constraints.map { describe($0) }.joined(separator: ", "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func pinButton(_ help: String, _ icon: String, _ edge: LayerEdge) -> some View {
        let active = store.isPinned(edge)
        return Button { store.togglePin(edge) } label: {
            Image(systemName: icon)
                .frame(width: 22, height: 22)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func describe(_ c: LayerConstraint) -> String {
        switch c.edge {
        case .width, .height: return "\(c.edge.rawValue) \(Int(c.constant))"
        case .centerX, .centerY: return c.edge.rawValue
        default: return "\(c.edge.rawValue) \(Int(c.constant))"
        }
    }

    // MARK: - Asset section

    @ViewBuilder
    private func assetSection(_ layer: Layer) -> some View {
        Section("Asset") {
            Picker("Asset", selection: Binding(
                get: { layer.assetID },
                set: { id in store.updateSelectedLayer { $0.assetID = id } })) {
                Text("None").tag(UUID?.none)
                ForEach(store.document.assets) { asset in
                    Text(asset.name).tag(UUID?.some(asset.id))
                }
            }
        }
    }
}

/// Alignment/distribute controls for multi-selection.
struct AlignmentControls: View {
    @EnvironmentObject var store: DocumentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Align").font(.headline)
            HStack {
                button("Left", "align.horizontal.left") { store.alignSelection(.left) }
                button("Center", "align.horizontal.center") { store.alignSelection(.hCenter) }
                button("Right", "align.horizontal.right") { store.alignSelection(.right) }
            }
            HStack {
                button("Top", "align.vertical.top") { store.alignSelection(.top) }
                button("Middle", "align.vertical.center") { store.alignSelection(.vCenter) }
                button("Bottom", "align.vertical.bottom") { store.alignSelection(.bottom) }
            }
            Text("Distribute").font(.headline)
            HStack {
                button("Horizontally", "distribute.horizontal") { store.distributeSelection(.horizontal) }
                button("Vertically", "distribute.vertical") { store.distributeSelection(.vertical) }
            }
        }
    }

    private func button(_ help: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }
            .buttonStyle(.bordered)
            .help(help)
    }
}

private extension CropSpec {
    func with(x: Double? = nil, y: Double? = nil, width: Double? = nil, height: Double? = nil) -> CropSpec {
        CropSpec(x: x ?? self.x, y: y ?? self.y, width: width ?? self.width, height: height ?? self.height)
    }
}

private extension VectorPathSpec {
    func with(isClosed: Bool? = nil, strokeWidth: Double? = nil,
              strokeColor: VColor? = nil, fillColor: VColor?? = nil) -> VectorPathSpec {
        var copy = self
        if let isClosed { copy.isClosed = isClosed }
        if let strokeWidth { copy.strokeWidth = strokeWidth }
        if let strokeColor { copy.strokeColor = strokeColor }
        if let fillColor { copy.fillColor = fillColor }
        return copy
    }
}

/// Minimal stand-in for ContentUnavailableView to keep a wide deployment range.
struct ContentUnavailableViewCompat: View {
    let title: String
    let systemImage: String
    let description: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 34)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(description).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
