import Foundation
import VUACore

/// Generates a React component from the layer tree using absolute positioning.
public struct ReactGenerator: CodeGenerator {
    public let target: CodeGenTarget = .react
    public var componentName: String

    public init(componentName: String = "GeneratedView") {
        self.componentName = componentName
    }

    public func generate(document: Document) throws -> GeneratedSource {
        var b = SourceBuilder(indentUnit: "  ")
        b.line("import React from 'react';")
        b.line()
        b.block("export default function \(Gen.safeType(componentName))({ viewModel = {} }) {") { b in
            b.line("return (")
            b.indented { b in
                b.line("<div data-vua-root=\(Gen.jsxString(document.name)) style={\(Gen.reactRootStyle(document))}>")
                b.indented { b in
                    for layer in document.roots where layer.isVisible {
                        ReactMarkup.emit(layer, into: &b, document: document)
                    }
                }
                b.line("</div>")
            }
            b.line(");")
        }
        b.line("}")
        return GeneratedSource(fileName: "\(Gen.safeType(componentName)).jsx", contents: b.text)
    }
}

/// Generates a React Native component from the layer tree. Native controls are
/// used where React Native has built-ins; richer controls carry VUA metadata.
public struct ReactNativeGenerator: CodeGenerator {
    public let target: CodeGenTarget = .reactNative
    public var componentName: String

    public init(componentName: String = "GeneratedView") {
        self.componentName = componentName
    }

    public func generate(document: Document) throws -> GeneratedSource {
        var b = SourceBuilder(indentUnit: "  ")
        b.line("import React from 'react';")
        b.line("import { Image, Pressable, StyleSheet, Switch, Text, View } from 'react-native';")
        b.line()
        b.block("export default function \(Gen.safeType(componentName))({ viewModel = {} }) {") { b in
            b.line("return (")
            b.indented { b in
                b.line("<View style={styles.root}>")
                b.indented { b in
                    for layer in document.roots where layer.isVisible {
                        ReactNativeMarkup.emit(layer, into: &b, document: document)
                    }
                }
                b.line("</View>")
            }
            b.line(");")
        }
        b.line("}")
        b.line()
        b.block("const styles = StyleSheet.create({") { b in
            b.line("root: \(Gen.reactNativeRootStyle(document)),")
        }
        b.line("});")
        return GeneratedSource(fileName: "\(Gen.safeType(componentName)).native.jsx", contents: b.text)
    }
}

/// Generates a self-contained HTML/CSS document from the layer tree.
public struct HTMLCSSGenerator: CodeGenerator {
    public let target: CodeGenTarget = .htmlCSS
    public var fileName: String

    public init(fileName: String = "index.html") {
        self.fileName = fileName
    }

    public func generate(document: Document) throws -> GeneratedSource {
        var b = SourceBuilder(indentUnit: "  ")
        b.line("<!doctype html>")
        b.line("<html lang=\"en\">")
        b.indented { b in
            b.line("<head>")
            b.indented { b in
                b.line("<meta charset=\"utf-8\">")
                b.line("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">")
                b.line("<title>\(Gen.html(document.name))</title>")
                b.line("<style>")
                b.indented { b in
                    b.line(":root { color-scheme: light dark; }")
                    b.line("body { margin: 0; font-family: system-ui, -apple-system, BlinkMacSystemFont, sans-serif; }")
                    b.line(".vua-root { position: relative; overflow: hidden; }")
                    b.line(".vua-layer { box-sizing: border-box; }")
                }
                b.line("</style>")
            }
            b.line("</head>")
            b.line("<body>")
            b.indented { b in
                b.line("<main class=\"vua-root\" data-vua-root=\"\(Gen.htmlAttribute(document.name))\" style=\"\(Gen.webRootStyle(document))\">")
                b.indented { b in
                    for layer in document.roots where layer.isVisible {
                        HTMLMarkup.emit(layer, into: &b, document: document)
                    }
                }
                b.line("</main>")
            }
            b.line("</body>")
        }
        b.line("</html>")
        return GeneratedSource(fileName: fileName, contents: b.text)
    }
}

/// Generates an Electron renderer HTML file. The DOM is the same absolute
/// layer export as HTML/CSS, with a small binding bridge hook for preload code.
public struct ElectronRendererGenerator: CodeGenerator {
    public let target: CodeGenTarget = .electronRenderer

    public init() {}

    public func generate(document: Document) throws -> GeneratedSource {
        let html = try HTMLCSSGenerator(fileName: "renderer.html").generate(document: document).contents
        let bridge = """

        <script>
          window.vuaBindings = window.vuaBindings || {};
          document.documentElement.setAttribute('data-vua-target', 'electron-renderer');
        </script>
        """
        return GeneratedSource(
            fileName: "renderer.html",
            contents: html.replacingOccurrences(of: "</body>", with: "\(bridge)\n</body>")
        )
    }
}

/// Generates a Flutter widget using a Stack of Positioned widgets.
public struct FlutterGenerator: CodeGenerator {
    public let target: CodeGenTarget = .flutter
    public var widgetName: String

    public init(widgetName: String = "GeneratedView") {
        self.widgetName = widgetName
    }

    public func generate(document: Document) throws -> GeneratedSource {
        var b = SourceBuilder(indentUnit: "  ")
        b.line("import 'package:flutter/material.dart';")
        b.line()
        b.block("class \(Gen.safeType(widgetName)) extends StatelessWidget {") { b in
            b.line("const \(Gen.safeType(widgetName))({super.key});")
            b.line()
            b.line("@override")
            b.block("Widget build(BuildContext context) {") { b in
                b.line("return SizedBox(")
                b.indented { b in
                    b.line("width: \(Gen.fmt(document.canvasSize.width)),")
                    b.line("height: \(Gen.fmt(document.canvasSize.height)),")
                    b.line("child: Stack(")
                    b.indented { b in
                        b.line("children: [")
                        b.indented { b in
                            for layer in document.roots where layer.isVisible {
                                FlutterMarkup.emitPositioned(layer, into: &b, document: document)
                            }
                        }
                        b.line("],")
                    }
                    b.line("),")
                }
                b.line(");")
            }
        }
        b.line("}")
        return GeneratedSource(fileName: "\(Gen.safeType(widgetName)).dart", contents: b.text)
    }
}

/// Generates an imperative UIKit view controller using frames and real controls.
public struct UIKitGenerator: CodeGenerator {
    public let target: CodeGenTarget = .uiKit
    public var className: String

    public init(className: String = "GeneratedViewController") {
        self.className = className
    }

    public func generate(document: Document) throws -> GeneratedSource {
        AppleImperativeGenerator(platform: .uiKit, className: className).generate(document)
    }
}

/// Generates an imperative AppKit view controller using frames and real controls.
public struct AppKitGenerator: CodeGenerator {
    public let target: CodeGenTarget = .appKit
    public var className: String

    public init(className: String = "GeneratedViewController") {
        self.className = className
    }

    public func generate(document: Document) throws -> GeneratedSource {
        AppleImperativeGenerator(platform: .appKit, className: className).generate(document)
    }
}

// MARK: - React

private enum ReactMarkup {
    static func emit(_ layer: Layer, into b: inout SourceBuilder, document: Document) {
        let anchor = Gen.anchor(layer)
        let style = Gen.reactLayerStyle(layer)
        let data = "data-vua-anchor=\(Gen.jsxString(anchor))"
        switch layer.kind {
        case .container, .panel, .background, .group, .shape, .polygon, .gradient, .mask, .line, .vectorPath:
            b.line("<div \(data) style={\(style)}>")
            b.indented { b in
                for child in layer.children where child.isVisible {
                    emit(child, into: &b, document: document)
                }
            }
            b.line("</div>")
        case .button:
            let action = Gen.actionName(layer)
            b.line("<button \(data) style={\(style)} onClick={viewModel.\(action) ?? (() => {})}>\(Gen.html(layer.text ?? layer.name))</button>")
        case .label, .text:
            b.line("<span \(data) style={\(style)}>\(Gen.html(layer.text ?? layer.name))</span>")
        case .image:
            let src = Gen.assetName(layer, document: document) ?? layer.name
            b.line("<img \(data) src={\(Gen.jsxString(src))} alt={\(Gen.jsxString(layer.name))} style={\(style)} />")
        case .slider, .knob, .fader, .control:
            let binding = Gen.bindingName(layer)
            let value = Gen.controlDefault(layer)
            b.line("<input \(data) data-vua-control-kind={\(Gen.jsxString(layer.kind.displayName))} type=\"range\" min={\(Gen.controlMin(layer))} max={\(Gen.controlMax(layer))} value={viewModel.\(binding) ?? \(value)} onChange={(event) => viewModel.set\(Gen.safeType(binding))?.(Number(event.target.value))} style={\(style)} />")
        case .meter:
            let binding = Gen.bindingName(layer)
            b.line("<progress \(data) value={viewModel.\(binding) ?? \(Gen.controlDefault(layer))} max={\(Gen.controlMax(layer))} style={\(style)} />")
        case .toggle:
            let binding = Gen.bindingName(layer)
            let checked = (layer.control?.defaultValue ?? 1) >= 0.5 ? "true" : "false"
            b.line("<label \(data) style={\(style)}><input type=\"checkbox\" checked={viewModel.\(binding) ?? \(checked)} onChange={(event) => viewModel.set\(Gen.safeType(binding))?.(event.target.checked)} /> \(Gen.html(layer.text ?? layer.name))</label>")
        case .custom(let typeName):
            b.line("<\(Gen.safeType(typeName)) \(data) style={\(style)} />")
        }
    }
}

// MARK: - React Native

private enum ReactNativeMarkup {
    static func emit(_ layer: Layer, into b: inout SourceBuilder, document: Document) {
        let anchor = Gen.anchor(layer)
        let style = Gen.reactNativeLayerStyle(layer)
        let nativeID = "nativeID=\(Gen.jsxString(anchor))"
        switch layer.kind {
        case .container, .panel, .background, .group, .shape, .polygon, .gradient, .mask, .line, .vectorPath:
            b.line("<View \(nativeID) style={\(style)}>")
            b.indented { b in
                for child in layer.children where child.isVisible {
                    emit(child, into: &b, document: document)
                }
            }
            b.line("</View>")
        case .button:
            let action = Gen.actionName(layer)
            b.line("<Pressable \(nativeID) accessibilityRole=\"button\" onPress={viewModel.\(action) ?? (() => {})} style={\(style)}>")
            b.indented { $0.line("<Text>\(Gen.html(layer.text ?? layer.name))</Text>") }
            b.line("</Pressable>")
        case .label, .text:
            b.line("<Text \(nativeID) style={\(style)}>\(Gen.html(layer.text ?? layer.name))</Text>")
        case .image:
            let src = Gen.assetName(layer, document: document) ?? layer.name
            b.line("<Image \(nativeID) source={{ uri: \(Gen.jsxString(src)) }} style={\(style)} resizeMode=\"cover\" />")
        case .toggle:
            let binding = Gen.bindingName(layer)
            let value = (layer.control?.defaultValue ?? 1) >= 0.5 ? "true" : "false"
            b.line("<Switch \(nativeID) value={viewModel.\(binding) ?? \(value)} onValueChange={(nextValue) => viewModel.set\(Gen.safeType(binding))?.(nextValue)} style={\(style)} />")
        case .slider, .knob, .fader, .meter, .control:
            let binding = Gen.bindingName(layer)
            b.line("{/* \(layer.kind.displayName) binding: \(binding), range \(Gen.controlMin(layer))...\(Gen.controlMax(layer)) */}")
            b.line("<View \(nativeID) accessibilityRole=\"adjustable\" style={\(style)} />")
        case .custom(let typeName):
            b.line("<\(Gen.safeType(typeName)) \(nativeID) style={\(style)} />")
        }
    }
}

// MARK: - HTML

private enum HTMLMarkup {
    static func emit(_ layer: Layer, into b: inout SourceBuilder, document: Document) {
        let anchor = Gen.htmlAttribute(Gen.anchor(layer))
        let style = Gen.webLayerStyle(layer)
        switch layer.kind {
        case .container, .panel, .background, .group, .shape, .polygon, .gradient, .mask, .line, .vectorPath:
            b.line("<div class=\"vua-layer\" data-vua-anchor=\"\(anchor)\" style=\"\(style)\">")
            b.indented { b in
                for child in layer.children where child.isVisible {
                    emit(child, into: &b, document: document)
                }
            }
            b.line("</div>")
        case .button:
            b.line("<button class=\"vua-layer\" data-vua-anchor=\"\(anchor)\" data-vua-action=\"\(Gen.htmlAttribute(Gen.actionName(layer)))\" style=\"\(style)\">\(Gen.html(layer.text ?? layer.name))</button>")
        case .label, .text:
            b.line("<span class=\"vua-layer\" data-vua-anchor=\"\(anchor)\" style=\"\(style)\">\(Gen.html(layer.text ?? layer.name))</span>")
        case .image:
            let src = Gen.assetName(layer, document: document) ?? layer.name
            b.line("<img class=\"vua-layer\" data-vua-anchor=\"\(anchor)\" src=\"\(Gen.htmlAttribute(src))\" alt=\"\(Gen.htmlAttribute(layer.name))\" style=\"\(style)\">")
        case .slider, .knob, .fader, .control:
            let binding = Gen.bindingName(layer)
            b.line("<input class=\"vua-layer\" data-vua-anchor=\"\(anchor)\" data-vua-binding=\"\(Gen.htmlAttribute(binding))\" data-vua-control-kind=\"\(Gen.htmlAttribute(layer.kind.displayName))\" type=\"range\" min=\"\(Gen.controlMin(layer))\" max=\"\(Gen.controlMax(layer))\" value=\"\(Gen.controlDefault(layer))\" style=\"\(style)\">")
        case .meter:
            b.line("<progress class=\"vua-layer\" data-vua-anchor=\"\(anchor)\" value=\"\(Gen.controlDefault(layer))\" max=\"\(Gen.controlMax(layer))\" style=\"\(style)\"></progress>")
        case .toggle:
            let binding = Gen.bindingName(layer)
            let checked = (layer.control?.defaultValue ?? 1) >= 0.5 ? " checked" : ""
            b.line("<label class=\"vua-layer\" data-vua-anchor=\"\(anchor)\" data-vua-binding=\"\(Gen.htmlAttribute(binding))\" style=\"\(style)\"><input type=\"checkbox\"\(checked)> \(Gen.html(layer.text ?? layer.name))</label>")
        case .custom(let typeName):
            b.line("<div class=\"vua-layer\" data-vua-anchor=\"\(anchor)\" data-vua-custom=\"\(Gen.htmlAttribute(typeName))\" style=\"\(style)\"></div>")
        }
    }
}

// MARK: - Flutter

private enum FlutterMarkup {
    static func emitPositioned(_ layer: Layer, into b: inout SourceBuilder, document: Document) {
        b.line("Positioned(")
        b.indented { b in
            b.line("left: \(Gen.fmt(layer.frame.minX)),")
            b.line("top: \(Gen.fmt(layer.frame.minY)),")
            b.line("width: \(Gen.fmt(layer.frame.width)),")
            b.line("height: \(Gen.fmt(layer.frame.height)),")
            b.line("child:")
            b.indented { b in emitWidget(layer, into: &b, document: document) }
        }
        b.line("),")
    }

    private static func emitWidget(_ layer: Layer, into b: inout SourceBuilder, document: Document) {
        switch layer.kind {
        case .container, .panel, .background, .group, .shape, .polygon, .gradient, .mask, .line, .vectorPath:
            b.line("Container(")
            b.indented { b in
                emitDecoration(layer, into: &b)
                b.line("child: Stack(")
                b.indented { b in
                    b.line("children: [")
                    b.indented { b in
                        for child in layer.children where child.isVisible {
                            emitPositioned(child, into: &b, document: document)
                        }
                    }
                    b.line("],")
                }
                b.line("),")
            }
            b.line("),")
        case .button:
            b.line("ElevatedButton(onPressed: () {}, child: Text(\(Gen.dartString(layer.text ?? layer.name)))),")
        case .label, .text:
            b.line("Text(\(Gen.dartString(layer.text ?? layer.name)), style: \(Gen.flutterTextStyle(layer))),")
        case .image:
            let src = Gen.assetName(layer, document: document) ?? layer.name
            b.line("Image.asset(\(Gen.dartString(src)), fit: BoxFit.cover),")
        case .slider, .knob, .fader, .control:
            b.line("Slider(value: \(Gen.controlNormalized(layer)), min: 0, max: 1, onChanged: (_) {}),")
        case .meter:
            b.line("LinearProgressIndicator(value: \(Gen.controlNormalized(layer))),")
        case .toggle:
            let value = (layer.control?.defaultValue ?? 1) >= 0.5 ? "true" : "false"
            b.line("Switch(value: \(value), onChanged: (_) {}),")
        case .custom(let typeName):
            b.line("\(Gen.safeType(typeName))(),")
        }
    }

    private static func emitDecoration(_ layer: Layer, into b: inout SourceBuilder) {
        var fields: [String] = []
        if let bg = layer.style.backgroundColor {
            fields.append("color: \(Gen.flutterColor(bg))")
        }
        if layer.style.cornerRadius > 0 {
            fields.append("borderRadius: BorderRadius.circular(\(Gen.fmt(layer.style.cornerRadius)))")
        }
        if let border = layer.style.borderColor, layer.style.borderWidth > 0 {
            fields.append("border: Border.all(color: \(Gen.flutterColor(border)), width: \(Gen.fmt(layer.style.borderWidth)))")
        }
        if let shadow = layer.style.shadow {
            fields.append("boxShadow: [BoxShadow(color: \(Gen.flutterColor(shadow.color)), blurRadius: \(Gen.fmt(shadow.radius)), offset: Offset(\(Gen.fmt(shadow.x)), \(Gen.fmt(shadow.y))))]")
        }
        if !fields.isEmpty {
            b.line("decoration: BoxDecoration(\(fields.joined(separator: ", "))),")
        }
    }
}

// MARK: - UIKit / AppKit

private struct AppleImperativeGenerator {
    enum Platform { case uiKit, appKit }

    var platform: Platform
    var className: String

    func generate(_ document: Document) -> GeneratedSource {
        var b = SourceBuilder()
        b.line("import \(platform == .uiKit ? "UIKit" : "AppKit")")
        b.line()
        b.block("final class \(Gen.safeType(className)): \(platform == .uiKit ? "UIViewController" : "NSViewController") {") { b in
            switch platform {
            case .uiKit:
                b.line("override func viewDidLoad() {")
                b.indented { b in
                    b.line("super.viewDidLoad()")
                    b.line("view.backgroundColor = .clear")
                    for layer in document.roots where layer.isVisible {
                        emitLayer(layer, parent: "view", into: &b, document: document, counter: Counter())
                    }
                }
                b.line("}")
            case .appKit:
                b.line("override func loadView() {")
                b.indented { b in
                    b.line("view = NSView(frame: NSRect(x: 0, y: 0, width: \(Gen.fmt(document.canvasSize.width)), height: \(Gen.fmt(document.canvasSize.height))))")
                    b.line("view.wantsLayer = true")
                    for layer in document.roots where layer.isVisible {
                        emitLayer(layer, parent: "view", into: &b, document: document, counter: Counter())
                    }
                }
                b.line("}")
            }
        }
        b.line("}")
        return GeneratedSource(fileName: "\(Gen.safeType(className)).swift", contents: b.text)
    }

    private func emitLayer(_ layer: Layer, parent: String, into b: inout SourceBuilder, document: Document, counter: Counter) {
        let name = "\(Gen.safeVar(layer.name))\(counter.next())"
        b.line("// \(layer.name) [\(layer.kind.displayName)]")
        b.line("let \(name) = \(constructor(for: layer, document: document))")
        b.line("\(name).frame = \(rect(layer.frame))")
        applyStyle(layer, variable: name, into: &b)
        applyIdentifier(layer, variable: name, into: &b)
        b.line("\(parent).addSubview(\(name))")
        for child in layer.children where child.isVisible {
            emitLayer(child, parent: name, into: &b, document: document, counter: counter)
        }
    }

    private func constructor(for layer: Layer, document: Document) -> String {
        switch (platform, layer.kind) {
        case (.uiKit, .button):
            return "UIButton(type: .system)"
        case (.appKit, .button):
            return "NSButton(title: \(Gen.swiftString(layer.text ?? layer.name)), target: nil, action: nil)"
        case (.uiKit, .label), (.uiKit, .text):
            return "UILabel()"
        case (.appKit, .label), (.appKit, .text):
            return "NSTextField(labelWithString: \(Gen.swiftString(layer.text ?? layer.name)))"
        case (.uiKit, .image):
            let image = Gen.assetName(layer, document: document) ?? layer.name
            return "UIImageView(image: UIImage(named: \(Gen.swiftString(image))))"
        case (.appKit, .image):
            let image = Gen.assetName(layer, document: document) ?? layer.name
            return "NSImageView(image: NSImage(named: \(Gen.swiftString(image))) ?? NSImage())"
        case (.uiKit, .slider), (.uiKit, .knob), (.uiKit, .fader), (.uiKit, .control):
            return "UISlider()"
        case (.appKit, .slider), (.appKit, .knob), (.appKit, .fader), (.appKit, .control):
            return "NSSlider(value: \(Gen.controlDefault(layer)), minValue: \(Gen.controlMin(layer)), maxValue: \(Gen.controlMax(layer)), target: nil, action: nil)"
        case (.uiKit, .toggle):
            return "UISwitch()"
        case (.appKit, .toggle):
            return "NSButton(checkboxWithTitle: \(Gen.swiftString(layer.text ?? layer.name)), target: nil, action: nil)"
        case (.uiKit, .meter):
            return "UIProgressView(progressViewStyle: .default)"
        case (.appKit, .meter):
            return "NSProgressIndicator()"
        case (.uiKit, _):
            return "UIView()"
        case (.appKit, _):
            return "NSView()"
        }
    }

    private func applyStyle(_ layer: Layer, variable: String, into b: inout SourceBuilder) {
        switch platform {
        case .uiKit:
            if let text = layer.text, layer.kind == .label || layer.kind == .text {
                b.line("\(variable).text = \(Gen.swiftString(text))")
            }
            if let buttonText = layer.text, layer.kind == .button {
                b.line("\(variable).setTitle(\(Gen.swiftString(buttonText)), for: .normal)")
            }
            if let bg = layer.style.backgroundColor {
                b.line("\(variable).backgroundColor = \(Gen.uiColor(bg))")
            }
            if let fg = layer.style.foregroundColor {
                if layer.kind == .label || layer.kind == .text {
                    b.line("\(variable).textColor = \(Gen.uiColor(fg))")
                }
            }
            if layer.style.cornerRadius > 0 {
                b.line("\(variable).layer.cornerRadius = \(Gen.fmt(layer.style.cornerRadius))")
                b.line("\(variable).clipsToBounds = true")
            }
            b.line("\(variable).alpha = \(Gen.fmt(layer.style.opacity))")
        case .appKit:
            b.line("\(variable).wantsLayer = true")
            if let bg = layer.style.backgroundColor {
                b.line("\(variable).layer?.backgroundColor = \(Gen.nsColor(bg)).cgColor")
            }
            if layer.style.cornerRadius > 0 {
                b.line("\(variable).layer?.cornerRadius = \(Gen.fmt(layer.style.cornerRadius))")
            }
            b.line("\(variable).alphaValue = \(Gen.fmt(layer.style.opacity))")
        }
    }

    private func applyIdentifier(_ layer: Layer, variable: String, into b: inout SourceBuilder) {
        let anchor = Gen.swiftString(Gen.anchor(layer))
        switch platform {
        case .uiKit:
            b.line("\(variable).accessibilityIdentifier = \(anchor)")
        case .appKit:
            b.line("\(variable).identifier = NSUserInterfaceItemIdentifier(\(anchor))")
        }
    }

    private func rect(_ frame: VRect) -> String {
        switch platform {
        case .uiKit:
            return "CGRect(x: \(Gen.fmt(frame.minX)), y: \(Gen.fmt(frame.minY)), width: \(Gen.fmt(frame.width)), height: \(Gen.fmt(frame.height)))"
        case .appKit:
            return "NSRect(x: \(Gen.fmt(frame.minX)), y: \(Gen.fmt(frame.minY)), width: \(Gen.fmt(frame.width)), height: \(Gen.fmt(frame.height)))"
        }
    }
}

private final class Counter {
    private var value = 0
    func next() -> Int {
        defer { value += 1 }
        return value
    }
}

// MARK: - Formatting

private enum Gen {
    static func anchor(_ layer: Layer) -> String {
        layer.binding?.anchorID ?? layer.id.uuidString
    }

    static func assetName(_ layer: Layer, document: Document) -> String? {
        guard let id = layer.assetID else { return nil }
        return document.asset(id: id)?.name
    }

    static func bindingName(_ layer: Layer) -> String {
        let raw = layer.control?.bindingName?.nilIfBlank
            ?? layer.control?.parameterID.nilIfBlank
            ?? anchor(layer)
        return safeVar(raw)
    }

    static func actionName(_ layer: Layer) -> String {
        safeVar(bindingName(layer) + "Action")
    }

    static func controlMin(_ layer: Layer) -> String {
        fmt(layer.control?.minValue ?? 0)
    }

    static func controlMax(_ layer: Layer) -> String {
        fmt(layer.control?.maxValue ?? 1)
    }

    static func controlDefault(_ layer: Layer) -> String {
        fmt(layer.control?.defaultValue ?? 0.5)
    }

    static func controlNormalized(_ layer: Layer) -> String {
        fmt(layer.control?.normalizedDefault ?? 0.5)
    }

    static func webRootStyle(_ document: Document) -> String {
        "width: \(fmt(document.canvasSize.width))px; height: \(fmt(document.canvasSize.height))px;"
    }

    static func webLayerStyle(_ layer: Layer) -> String {
        var parts = [
            "position: absolute",
            "left: \(fmt(layer.frame.minX))px",
            "top: \(fmt(layer.frame.minY))px",
            "width: \(fmt(layer.frame.width))px",
            "height: \(fmt(layer.frame.height))px"
        ]
        if let bg = layer.style.backgroundColor { parts.append("background: \(cssColor(bg))") }
        if let fg = layer.style.foregroundColor { parts.append("color: \(cssColor(fg))") }
        if layer.style.cornerRadius > 0 { parts.append("border-radius: \(fmt(layer.style.cornerRadius))px") }
        if let border = layer.style.borderColor, layer.style.borderWidth > 0 {
            parts.append("border: \(fmt(layer.style.borderWidth))px solid \(cssColor(border))")
        }
        if let shadow = layer.style.shadow {
            parts.append("box-shadow: \(fmt(shadow.x))px \(fmt(shadow.y))px \(fmt(shadow.radius))px \(cssColor(shadow.color))")
        }
        if layer.style.blurRadius > 0 { parts.append("filter: blur(\(fmt(layer.style.blurRadius))px)") }
        if layer.style.rotationDegrees != 0 { parts.append("transform: rotate(\(fmt(layer.style.rotationDegrees))deg)") }
        if layer.style.opacity < 1 { parts.append("opacity: \(fmt(layer.style.opacity))") }
        if layer.kind == .shape(.ellipse) || layer.kind == .shape(.capsule) {
            parts.append("border-radius: 9999px")
        }
        parts.append("overflow: hidden")
        return parts.joined(separator: "; ") + ";"
    }

    static func reactRootStyle(_ document: Document) -> String {
        "{ position: 'relative', overflow: 'hidden', width: \(fmt(document.canvasSize.width)), height: \(fmt(document.canvasSize.height)) }"
    }

    static func reactLayerStyle(_ layer: Layer) -> String {
        "{ \(reactStyleEntries(layer, native: false).joined(separator: ", ")) }"
    }

    static func reactNativeRootStyle(_ document: Document) -> String {
        "{ position: 'relative', overflow: 'hidden', width: \(fmt(document.canvasSize.width)), height: \(fmt(document.canvasSize.height)) }"
    }

    static func reactNativeLayerStyle(_ layer: Layer) -> String {
        "{ \(reactStyleEntries(layer, native: true).joined(separator: ", ")) }"
    }

    private static func reactStyleEntries(_ layer: Layer, native: Bool) -> [String] {
        var entries = [
            "position: 'absolute'",
            "left: \(fmt(layer.frame.minX))",
            "top: \(fmt(layer.frame.minY))",
            "width: \(fmt(layer.frame.width))",
            "height: \(fmt(layer.frame.height))"
        ]
        if let bg = layer.style.backgroundColor { entries.append("backgroundColor: \(jsxString(cssColor(bg)))") }
        if let fg = layer.style.foregroundColor { entries.append("color: \(jsxString(cssColor(fg)))") }
        if layer.style.cornerRadius > 0 { entries.append("borderRadius: \(fmt(layer.style.cornerRadius))") }
        if let border = layer.style.borderColor, layer.style.borderWidth > 0 {
            entries.append("borderWidth: \(fmt(layer.style.borderWidth))")
            entries.append("borderColor: \(jsxString(cssColor(border)))")
            if !native { entries.append("borderStyle: 'solid'") }
        }
        if layer.style.opacity < 1 { entries.append("opacity: \(fmt(layer.style.opacity))") }
        if layer.style.rotationDegrees != 0 {
            entries.append(native
                ? "transform: [{ rotate: \(jsxString(fmt(layer.style.rotationDegrees) + "deg")) }]"
                : "transform: \(jsxString("rotate(\(fmt(layer.style.rotationDegrees))deg)"))")
        }
        return entries
    }

    static func flutterTextStyle(_ layer: Layer) -> String {
        var fields: [String] = []
        if let fg = layer.style.foregroundColor { fields.append("color: \(flutterColor(fg))") }
        if let size = layer.style.fontSize { fields.append("fontSize: \(fmt(size))") }
        return fields.isEmpty ? "const TextStyle()" : "TextStyle(\(fields.joined(separator: ", ")))"
    }

    static func cssColor(_ color: VColor) -> String {
        let r = Int((color.red * 255).rounded())
        let g = Int((color.green * 255).rounded())
        let b = Int((color.blue * 255).rounded())
        return "rgba(\(r), \(g), \(b), \(fmt(color.alpha)))"
    }

    static func flutterColor(_ color: VColor) -> String {
        let a = Int((color.alpha * 255).rounded())
        let r = Int((color.red * 255).rounded())
        let g = Int((color.green * 255).rounded())
        let b = Int((color.blue * 255).rounded())
        return String(format: "Color(0x%02X%02X%02X%02X)", a, r, g, b)
    }

    static func uiColor(_ color: VColor) -> String {
        "UIColor(red: \(fmt(color.red)), green: \(fmt(color.green)), blue: \(fmt(color.blue)), alpha: \(fmt(color.alpha)))"
    }

    static func nsColor(_ color: VColor) -> String {
        "NSColor(red: \(fmt(color.red)), green: \(fmt(color.green)), blue: \(fmt(color.blue)), alpha: \(fmt(color.alpha)))"
    }

    static func html(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func htmlAttribute(_ text: String) -> String {
        html(text).replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func jsxString(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'"))'"
    }

    static func dartString(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'"))'"
    }

    static func swiftString(_ text: String) -> String {
        "\"\(text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    static func safeType(_ raw: String) -> String {
        let cleaned = raw.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            .map { part in part.prefix(1).uppercased() + part.dropFirst() }
            .joined()
        let fallback = cleaned.isEmpty ? "GeneratedView" : cleaned
        return fallback.first?.isNumber == true ? "VUA\(fallback)" : fallback
    }

    static func safeVar(_ raw: String) -> String {
        let type = safeType(raw)
        guard let first = type.first else { return "vuaValue" }
        return first.lowercased() + type.dropFirst()
    }

    static func fmt(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.000_001 { return String(Int(value.rounded())) }
        return String(format: "%.3f", value).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
