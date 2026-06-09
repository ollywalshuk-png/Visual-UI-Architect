import Foundation
import VUACore

/// The built-in preset catalog. Each entry builds a real, code-generatable
/// layer subtree — not a placeholder. Covers app screens, panels, cards,
/// navigation, forms, dashboards, plugin controls, mobile, watch, and modals.
public enum PresetLibrary {
    public static var all: [Preset] { catalog }

    public static func presets(in category: Preset.Category) -> [Preset] {
        catalog.filter { $0.category == category }
    }

    public static func preset(id: String) -> Preset? {
        catalog.first { $0.id == id }
    }

    private static let catalog: [Preset] = [
        // MARK: App screens
        Preset(id: "macos.sidebar", name: "macOS Sidebar Layout", category: .appScreens) { o in
            PresetBuild.group("Sidebar Layout", VSize(width: 640, height: 400), role: .navigation, at: o, [
                PresetBuild.panel("Sidebar", VRect(x: 0, y: 0, width: 180, height: 400), color: "#161618", radius: 0),
                PresetBuild.label("Library", VRect(x: 16, y: 16, width: 140, height: 20), size: 13, weight: .semibold, color: "#9A9A9F"),
                PresetBuild.label("All Items", VRect(x: 16, y: 48, width: 140, height: 20)),
                PresetBuild.label("Favourites", VRect(x: 16, y: 76, width: 140, height: 20)),
                PresetBuild.panel("Content", VRect(x: 180, y: 0, width: 460, height: 400), color: "#1C1C1E", radius: 0),
            ])
        },
        Preset(id: "macos.inspector", name: "macOS Inspector Layout", category: .appScreens) { o in
            PresetBuild.group("Inspector", VSize(width: 280, height: 360), role: .panel, at: o, [
                PresetBuild.panel("Inspector BG", VRect(x: 0, y: 0, width: 280, height: 360), color: "#1C1C1E", radius: 0),
                PresetBuild.label("Inspector", VRect(x: 16, y: 14, width: 200, height: 20), size: 13, weight: .bold),
                PresetBuild.divider(VRect(x: 0, y: 44, width: 280, height: 1)),
                PresetBuild.label("Position", VRect(x: 16, y: 60, width: 120, height: 18), size: 12, color: "#9A9A9F"),
                PresetBuild.toggle("Locked", VRect(x: 16, y: 120, width: 240, height: 28)),
            ])
        },
        Preset(id: "ios.settings", name: "iPhone Settings Screen", category: .mobile) { o in
            PresetBuild.group("Settings", VSize(width: 360, height: 480), role: .navigation, at: o, [
                PresetBuild.panel("BG", VRect(x: 0, y: 0, width: 360, height: 480), color: "#000000", radius: 0),
                PresetBuild.label("Settings", VRect(x: 16, y: 20, width: 240, height: 34), size: 28, weight: .bold),
                PresetBuild.card("General", VRect(x: 12, y: 70, width: 336, height: 50)),
                PresetBuild.label("General", VRect(x: 28, y: 86, width: 200, height: 20)),
                PresetBuild.card("Privacy", VRect(x: 12, y: 128, width: 336, height: 50)),
                PresetBuild.label("Privacy & Security", VRect(x: 28, y: 144, width: 240, height: 20)),
            ])
        },
        Preset(id: "ipad.split", name: "iPad Split-View Layout", category: .appScreens) { o in
            PresetBuild.group("Split View", VSize(width: 720, height: 460), role: .navigation, at: o, [
                PresetBuild.panel("Primary", VRect(x: 0, y: 0, width: 240, height: 460), color: "#161618", radius: 0),
                PresetBuild.panel("Detail", VRect(x: 240, y: 0, width: 480, height: 460), color: "#1C1C1E", radius: 0),
                PresetBuild.label("Items", VRect(x: 16, y: 16, width: 200, height: 20), weight: .semibold),
            ])
        },
        Preset(id: "watch.panel", name: "watchOS Compact Control Panel", category: .watch) { o in
            PresetBuild.group("Watch Panel", VSize(width: 184, height: 224), role: .control, at: o, [
                PresetBuild.panel("BG", VRect(x: 0, y: 0, width: 184, height: 224), color: "#000000", radius: 24),
                PresetBuild.knob("Volume", VRect(x: 52, y: 40, width: 80, height: 80), param: "volume"),
                PresetBuild.button("Play", VRect(x: 42, y: 150, width: 100, height: 40)),
            ])
        },

        // MARK: Cards & dashboards
        Preset(id: "dashboard.grid", name: "Dashboard Card Grid", category: .dashboards) { o in
            PresetBuild.group("Card Grid", VSize(width: 480, height: 320), role: .dataVisualisation, at: o, [
                PresetBuild.card("Card 1", VRect(x: 0, y: 0, width: 230, height: 150)),
                PresetBuild.card("Card 2", VRect(x: 250, y: 0, width: 230, height: 150)),
                PresetBuild.card("Card 3", VRect(x: 0, y: 170, width: 230, height: 150)),
                PresetBuild.card("Card 4", VRect(x: 250, y: 170, width: 230, height: 150)),
            ])
        },
        Preset(id: "finance.summary", name: "Finance Summary Card", category: .cards) { o in
            PresetBuild.group("Finance Card", VSize(width: 300, height: 160), role: .dataVisualisation, at: o, [
                PresetBuild.card("BG", VRect(x: 0, y: 0, width: 300, height: 160)),
                PresetBuild.label("Balance", VRect(x: 20, y: 18, width: 200, height: 18), size: 13, color: "#9A9A9F"),
                PresetBuild.label("$12,480.50", VRect(x: 20, y: 40, width: 260, height: 36), size: 30, weight: .bold),
                PresetBuild.label("+2.4% this month", VRect(x: 20, y: 110, width: 240, height: 20), size: 13, color: "#34C759"),
            ])
        },
        Preset(id: "writing.chapter", name: "Writing App Chapter Card", category: .cards) { o in
            PresetBuild.group("Chapter Card", VSize(width: 280, height: 120), role: .panel, at: o, [
                PresetBuild.card("BG", VRect(x: 0, y: 0, width: 280, height: 120), color: "#1E1E20"),
                PresetBuild.label("Chapter 1", VRect(x: 18, y: 16, width: 240, height: 22), size: 17, weight: .semibold),
                PresetBuild.label("The Beginning", VRect(x: 18, y: 44, width: 240, height: 18), size: 13, color: "#9A9A9F"),
            ])
        },
        Preset(id: "media.strip", name: "Media Control Strip", category: .toolbars) { o in
            PresetBuild.group("Transport", VSize(width: 320, height: 64), role: .control, at: o, [
                PresetBuild.panel("BG", VRect(x: 0, y: 0, width: 320, height: 64), color: "#1C1C1E", radius: 12),
                PresetBuild.button("◀︎", VRect(x: 60, y: 16, width: 40, height: 32)),
                PresetBuild.button("⏵", VRect(x: 140, y: 16, width: 40, height: 32)),
                PresetBuild.button("▶︎", VRect(x: 220, y: 16, width: 40, height: 32)),
            ])
        },

        // MARK: Plugin controls
        Preset(id: "plugin.oscillator", name: "Plugin Oscillator Block", category: .pluginControls) { o in
            PresetBuild.group("Oscillator", VSize(width: 240, height: 140), role: .control, at: o, [
                PresetBuild.panel("BG", VRect(x: 0, y: 0, width: 240, height: 140), color: "#1C1C1E", radius: 12),
                PresetBuild.label("OSC", VRect(x: 16, y: 10, width: 100, height: 18), size: 12, weight: .bold, color: "#9A9A9F"),
                PresetBuild.knob("Pitch", VRect(x: 24, y: 40, width: 60, height: 60), param: "osc_pitch"),
                PresetBuild.knob("Shape", VRect(x: 100, y: 40, width: 60, height: 60), param: "osc_shape"),
                PresetBuild.knob("Level", VRect(x: 176, y: 40, width: 60, height: 60), param: "osc_level"),
            ])
        },
        Preset(id: "plugin.filter", name: "Plugin Filter Block", category: .pluginControls) { o in
            PresetBuild.group("Filter", VSize(width: 180, height: 140), role: .control, at: o, [
                PresetBuild.panel("BG", VRect(x: 0, y: 0, width: 180, height: 140), color: "#1C1C1E", radius: 12),
                PresetBuild.label("FILTER", VRect(x: 16, y: 10, width: 120, height: 18), size: 12, weight: .bold, color: "#9A9A9F"),
                PresetBuild.knob("Cutoff", VRect(x: 24, y: 40, width: 60, height: 60), param: "filter_cutoff"),
                PresetBuild.knob("Reso", VRect(x: 100, y: 40, width: 60, height: 60), param: "filter_resonance"),
            ])
        },
        Preset(id: "plugin.adsr", name: "Plugin ADSR Block", category: .pluginControls) { o in
            PresetBuild.group("ADSR", VSize(width: 240, height: 200), role: .control, at: o, [
                PresetBuild.panel("BG", VRect(x: 0, y: 0, width: 240, height: 200), color: "#1C1C1E", radius: 12),
                PresetBuild.label("ENV", VRect(x: 16, y: 10, width: 120, height: 18), size: 12, weight: .bold, color: "#9A9A9F"),
                PresetBuild.fader("A", VRect(x: 24, y: 36, width: 36, height: 150), param: "env_attack"),
                PresetBuild.fader("D", VRect(x: 76, y: 36, width: 36, height: 150), param: "env_decay"),
                PresetBuild.fader("S", VRect(x: 128, y: 36, width: 36, height: 150), param: "env_sustain"),
                PresetBuild.fader("R", VRect(x: 180, y: 36, width: 36, height: 150), param: "env_release"),
            ])
        },
        Preset(id: "plugin.mixer", name: "Mixer Channel Strip", category: .pluginControls) { o in
            PresetBuild.group("Channel", VSize(width: 90, height: 280), role: .control, at: o, [
                PresetBuild.panel("BG", VRect(x: 0, y: 0, width: 90, height: 280), color: "#1C1C1E", radius: 10),
                PresetBuild.knob("Pan", VRect(x: 25, y: 14, width: 40, height: 40), param: "ch_pan"),
                PresetBuild.fader("Level", VRect(x: 35, y: 70, width: 20, height: 170), param: "ch_level"),
                PresetBuild.label("CH 1", VRect(x: 10, y: 250, width: 70, height: 18), size: 12, color: "#9A9A9F"),
            ])
        },
        Preset(id: "transport", name: "Transport Controls", category: .toolbars) { o in
            PresetBuild.group("Transport", VSize(width: 260, height: 56), role: .control, at: o, [
                PresetBuild.panel("BG", VRect(x: 0, y: 0, width: 260, height: 56), color: "#1C1C1E", radius: 10),
                PresetBuild.button("⏮", VRect(x: 16, y: 12, width: 44, height: 32)),
                PresetBuild.button("⏯", VRect(x: 108, y: 12, width: 44, height: 32)),
                PresetBuild.button("⏭", VRect(x: 200, y: 12, width: 44, height: 32)),
            ])
        },

        // MARK: Forms & modals
        Preset(id: "login.form", name: "Login Form", category: .forms) { o in
            PresetBuild.group("Login", VSize(width: 300, height: 220), role: .panel, at: o, [
                PresetBuild.card("BG", VRect(x: 0, y: 0, width: 300, height: 220)),
                PresetBuild.label("Sign In", VRect(x: 20, y: 18, width: 200, height: 26), size: 20, weight: .bold),
                PresetBuild.card("Email", VRect(x: 20, y: 60, width: 260, height: 36), color: "#3A3A3C"),
                PresetBuild.card("Password", VRect(x: 20, y: 106, width: 260, height: 36), color: "#3A3A3C"),
                PresetBuild.button("Continue", VRect(x: 20, y: 160, width: 260, height: 40)),
            ])
        },
        Preset(id: "onboarding", name: "Onboarding Panel", category: .modals) { o in
            PresetBuild.group("Onboarding", VSize(width: 320, height: 360), role: .panel, at: o, [
                PresetBuild.gradientHeader(VRect(x: 0, y: 0, width: 320, height: 140), from: "#0A84FF", to: "#5E5CE6"),
                PresetBuild.label("Welcome", VRect(x: 24, y: 160, width: 280, height: 30), size: 24, weight: .bold),
                PresetBuild.label("Let's get you set up.", VRect(x: 24, y: 196, width: 280, height: 20), size: 15, color: "#9A9A9F"),
                PresetBuild.button("Get Started", VRect(x: 24, y: 300, width: 272, height: 44)),
            ])
        },
        Preset(id: "alert.modal", name: "Alert Modal", category: .modals) { o in
            PresetBuild.group("Alert", VSize(width: 260, height: 160), role: .panel, at: o, [
                PresetBuild.card("BG", VRect(x: 0, y: 0, width: 260, height: 160), color: "#2C2C2E"),
                PresetBuild.label("Are you sure?", VRect(x: 20, y: 22, width: 220, height: 22), size: 17, weight: .semibold),
                PresetBuild.label("This can't be undone.", VRect(x: 20, y: 50, width: 220, height: 18), size: 13, color: "#9A9A9F"),
                PresetBuild.button("Cancel", VRect(x: 20, y: 104, width: 105, height: 38), color: "#3A3A3C"),
                PresetBuild.button("Delete", VRect(x: 135, y: 104, width: 105, height: 38), color: "#FF3B30"),
            ])
        },
        Preset(id: "settings.toggle", name: "Settings Toggle Row", category: .forms) { o in
            PresetBuild.group("Toggle Row", VSize(width: 320, height: 44), role: .control, at: o, [
                PresetBuild.card("BG", VRect(x: 0, y: 0, width: 320, height: 44), color: "#1E1E20"),
                PresetBuild.toggle("Enable Notifications", VRect(x: 16, y: 8, width: 288, height: 28)),
            ])
        },
        Preset(id: "gradient.header", name: "Gradient Header", category: .panels) { o in
            PresetBuild.gradientHeader(VRect(x: o.x, y: o.y, width: 360, height: 160), from: "#FF2D55", to: "#FF9500")
        },
        Preset(id: "glass.panel", name: "Glass-Style Panel", category: .panels) { o in
            Layer(name: "Glass Panel", kind: .shape(.glassPanel),
                  frame: VRect(x: o.x, y: o.y, width: 280, height: 180),
                  style: LayerStyle(cornerRadius: 18), role: .panel)
        },
        Preset(id: "toolbar.cluster", name: "Toolbar Button Cluster", category: .toolbars) { o in
            PresetBuild.group("Toolbar", VSize(width: 220, height: 44), role: .navigation, at: o, [
                PresetBuild.panel("BG", VRect(x: 0, y: 0, width: 220, height: 44), color: "#1C1C1E", radius: 10),
                PresetBuild.button("A", VRect(x: 8, y: 8, width: 60, height: 28), color: "#3A3A3C"),
                PresetBuild.button("B", VRect(x: 80, y: 8, width: 60, height: 28), color: "#3A3A3C"),
                PresetBuild.button("C", VRect(x: 152, y: 8, width: 60, height: 28), color: "#0A84FF"),
            ])
        },
    ]
}
