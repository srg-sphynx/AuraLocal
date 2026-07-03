import SwiftUI
import AppKit

/// The full set of color tokens for one resolved theme. `Theme.Palette.*` reads
/// from `ThemeManager.shared.current`, so swapping this struct re-themes the app.
struct ThemePalette {
    // Surfaces
    var surface: Color
    var surfaceContainerLowest: Color
    var surfaceContainerLow: Color
    var surfaceContainer: Color
    var surfaceContainerHigh: Color
    var surfaceContainerHighest: Color
    var surfaceBright: Color
    // Content
    var onSurface: Color
    var onSurfaceVariant: Color
    var outline: Color
    var outlineVariant: Color
    // Primary (accent-derived)
    var primary: Color
    var primaryVivid: Color
    var onPrimary: Color
    var onPrimaryReadable: Color
    var primaryFixed: Color
    // Secondary
    var secondary: Color
    var secondaryContainer: Color
    // Semantic
    var success: Color
    var successContainer: Color
    var warning: Color
    var error: Color
    var errorContainer: Color
    // Glass / fills (adapt per appearance so light mode reads correctly)
    var glassBorder: Color
    var glassBorderSoft: Color
    var cardFill: Color
    var cardFillSelected: Color
    var hoverFill: Color
    var fieldFill: Color
    var trackFill: Color
    /// Whether this palette is a dark appearance (drives glass tint math).
    var isDark: Bool = true
}

extension ThemePalette {

    /// Build a palette from an appearance, contrast level, and accent color.
    static func make(dark: Bool, highContrast hc: Bool, accent: Color, preset: ThemePreset?) -> ThemePalette {
        var p = dark ? darkBase(hc: hc) : lightBase(hc: hc)
        p.isDark = dark

        // Accent-derived primary tokens. In light mode the primary is used as *text*
        // (slider values, citation headings, links), so it must clear AA against the
        // near-white surface for *any* accent the user picks — a fixed mix leaves
        // bright accents (emerald/amber/cyan) at ~3:1. `readableText` darkens only as
        // much as needed. Dark mode keeps the lighten-toward-white formula (it already
        // passes comfortably and stays vivid).
        p.primaryVivid = accent
        p.primary = dark ? accent.mixed(with: .white, by: hc ? 0.64 : 0.50)
                         : accent.readableText(on: p.surfaceContainer, minRatio: hc ? 5.5 : 4.5)
        p.onPrimary = accent.perceivedBrightness > 0.62 ? Color(hex: 0x101015) : .white
        p.onPrimaryReadable = .white
        p.primaryFixed = accent.mixed(with: .white, by: 0.72)

        if let preset {
            if let s = preset.onSurfaceHex { p.onSurface = Color(hex: s) }
            if let su = preset.successHex { p.success = Color(hex: su) }
        }
        return p
    }

    private static func darkBase(hc: Bool) -> ThemePalette {
        ThemePalette(
            surface: Color(hex: 0x131315),
            surfaceContainerLowest: Color(hex: 0x0E0E10),
            surfaceContainerLow: Color(hex: 0x1B1B1D),
            surfaceContainer: Color(hex: 0x1F1F21),
            surfaceContainerHigh: Color(hex: 0x2A2A2C),
            surfaceContainerHighest: Color(hex: 0x353437),
            surfaceBright: Color(hex: 0x39393B),
            onSurface: Color(hex: hc ? 0xFFFFFF : 0xF2F1F4),
            onSurfaceVariant: Color(hex: hc ? 0xF3F1FB : 0xCFCDDA),
            outline: Color(hex: hc ? 0xE6E4F0 : 0xA6A4B4),
            outlineVariant: Color(hex: hc ? 0x8C8A9A : 0x464554),
            primary: Color(hex: 0xC2C1FF), primaryVivid: Color(hex: 0x5E5CE6),
            onPrimary: .white, onPrimaryReadable: .white, primaryFixed: Color(hex: 0xE2DFFF),
            secondary: Color(hex: 0xB9C8DE), secondaryContainer: Color(hex: 0x39485A),
            success: Color(hex: 0x42E355), successContainer: Color(hex: 0x008122),
            warning: Color(hex: 0xF5C04E), error: Color(hex: 0xFFB4AB), errorContainer: Color(hex: 0x93000A),
            glassBorder: Color.white.opacity(hc ? 0.46 : 0.15),
            glassBorderSoft: Color.white.opacity(hc ? 0.26 : 0.08),
            cardFill: Color.white.opacity(hc ? 0.11 : 0.04),
            cardFillSelected: Color.white.opacity(hc ? 0.16 : 0.09),
            hoverFill: Color.white.opacity(0.10),
            fieldFill: Color.black.opacity(hc ? 0.34 : 0.22),
            trackFill: Color.white.opacity(hc ? 0.12 : 0.07))
    }

    private static func lightBase(hc: Bool) -> ThemePalette {
        ThemePalette(
            surface: Color(hex: 0xFFFFFF),
            surfaceContainerLowest: Color(hex: 0xF6F6FA),
            surfaceContainerLow: Color(hex: 0xF1F1F6),
            surfaceContainer: Color(hex: 0xEBEBF1),
            surfaceContainerHigh: Color(hex: 0xE3E3EB),
            surfaceContainerHighest: Color(hex: 0xDADAE3),
            surfaceBright: Color(hex: 0xFFFFFF),
            onSurface: Color(hex: hc ? 0x000000 : 0x1A1A20),
            onSurfaceVariant: Color(hex: hc ? 0x161520 : 0x45434F),
            outline: Color(hex: hc ? 0x24232D : 0x6B6979),
            outlineVariant: Color(hex: hc ? 0x6E6C7A : 0xC6C4D1),
            primary: Color(hex: hc ? 0x33319E : 0x4F4DD6), primaryVivid: Color(hex: 0x5E5CE6),
            onPrimary: .white, onPrimaryReadable: .white, primaryFixed: Color(hex: 0x3F3DBE),
            secondary: Color(hex: 0x44566B), secondaryContainer: Color(hex: 0xD7E3F7),
            // Darker success/warning so they read as *text* on white (the previous
            // 0x1F9D38 / 0xB8860B sat at ~2.9:1 — well under AA).
            success: Color(hex: hc ? 0x0A5F22 : 0x0E7A2B), successContainer: Color(hex: 0xB6F2BE),
            warning: Color(hex: hc ? 0x5F4600 : 0x835F07), error: Color(hex: hc ? 0xA1000A : 0xC0341E), errorContainer: Color(hex: 0xFFDAD4),
            glassBorder: Color.black.opacity(hc ? 0.46 : 0.15),
            glassBorderSoft: Color.black.opacity(hc ? 0.30 : 0.10),
            // Light mode reads best with bright, white-based cards/fields over the
            // pane (black overlays just stack more gray on gray).
            cardFill: Color.white.opacity(hc ? 0.96 : 0.72),
            cardFillSelected: Color.white.opacity(hc ? 1.0 : 0.95),
            hoverFill: Color.black.opacity(hc ? 0.10 : 0.06),
            fieldFill: Color.white.opacity(hc ? 1.0 : 0.88),
            trackFill: Color.black.opacity(hc ? 0.16 : 0.10))
    }

    /// Five quick accent swatches offered in the picker.
    static let accentChoices: [(name: String, hex: UInt32)] = [
        ("Indigo", 0x5E5CE6), ("Violet", 0x8B5CF6), ("Emerald", 0x10B981),
        ("Amber", 0xF59E0B), ("Rose", 0xF43F5E), ("Cyan", 0x06B6D4),
    ]
}

/// Owns the active theme. A singleton so `Theme.Palette.*` (static, used in ~200
/// call sites) can read the live palette without threading an environment value
/// through every view. Live switching is achieved by publishing `current`
/// (`objectWillChange`): the shell and each screen observe this `ThemeManager`, so
/// they re-render in place and re-read the fresh static palette — no `.id()` tree
/// rebuild, so scroll positions and other transient state survive an appearance
/// change. `revision` is kept as a monotonically increasing change counter.
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published private(set) var current: ThemePalette
    /// Bumps on *every* theme change (including a Transparency drag). Live-observing
    /// chrome (e.g. `GlassPane`) watches this to re-tint in place.
    @Published private(set) var revision: Int = 0
    /// Bumps only on *structural* changes (mode/appearance/accent/contrast/preset/
    /// density/text-size) — never on a Transparency drag. `RootView` keys the pane
    /// tree's `.id` on this so a mode/accent switch fully rebuilds (guaranteeing a
    /// global re-color with no stale "hover to refresh" text), while dragging
    /// Transparency updates live without resetting any scroll positions.
    @Published private(set) var appearanceRevision: Int = 0
    @Published private(set) var fontScale: CGFloat = 1.0
    @Published private(set) var density: ThemeDensity = .comfortable
    @Published private(set) var mode: AppearanceMode = .dark

    /// Nonisolated mirrors so `Theme.Palette.*` / `Theme.Font` (static, called from
    /// view bodies) can read the live values without crossing actor boundaries.
    /// Written only on the main actor in `apply`, read only during view layout.
    nonisolated(unsafe) static var palette: ThemePalette =
        ThemePalette.make(dark: true, highContrast: false, accent: Color(hex: 0x5E5CE6), preset: nil)
    nonisolated(unsafe) static var fontScaleValue: CGFloat = 1.0
    nonisolated(unsafe) static var densityValue: ThemeDensity = .comfortable
    nonisolated(unsafe) static var glassValue: CGFloat = 0.4

    /// Identity of the last applied *structural* configuration (everything but glass
    /// transparency) — lets `apply` skip the palette rebuild + `.id` bump when only
    /// the Transparency slider moved (or nothing changed at all, e.g. the per-
    /// activation text-size re-check).
    private var appliedStructureKey: String?

    private init() {
        current = ThemeManager.palette
    }

    var preferredColorScheme: ColorScheme? {
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The user's system text size (Accessibility → Display → Text Size / preferred
    /// body font), expressed as a multiplier over the 13pt macOS default. The app
    /// tracks this automatically — there is no in-app text-size control.
    static func systemFontScale() -> CGFloat {
        let body = NSFont.preferredFont(forTextStyle: .body).pointSize
        return min(max(body / 13.0, 0.9), 1.4)
    }

    /// Recompute the palette from a config + the current system appearance.
    ///  - A *structural* change (mode/appearance/accent/contrast/preset/density/text
    ///    size) rebuilds the palette and bumps `appearanceRevision` → `RootView`'s
    ///    keyed pane tree rebuilds, so every view re-reads its colors immediately.
    ///  - A Transparency-only change updates the glass tint and bumps `revision`
    ///    (live re-tint) *without* a structural rebuild, so dragging never resets
    ///    scroll positions.
    ///  - No change at all (the per-activation text-size re-check) is a full no-op.
    func apply(_ config: ThemeConfig, systemDark: Bool) {
        let dark: Bool
        switch config.mode {
        case .dark: dark = true
        case .light: dark = false
        case .system: dark = systemDark
        }
        // Mode is the single source of truth for the light/dark base. A custom theme
        // only contributes its accent (always) plus its surface tweaks (only when its
        // saved base matches the resolved appearance — otherwise a dark preset's text
        // color would land on a light surface and break contrast). This keeps the
        // Mode switch fully functional even while a preset is active.
        let preset = config.activePreset
        let baseDark = dark
        let accentHex = preset?.accentHex ?? config.accentHex
        let effectivePreset = (preset?.basedOnDark == baseDark) ? preset : nil
        let newScale = Self.systemFontScale()
        let glass = CGFloat(min(max(config.glassTransparency, 0), 1))

        let structureKey = "\(baseDark)|\(config.highContrast)|\(accentHex)|" +
                           "\(effectivePreset?.id.uuidString ?? "-")|\(config.density.rawValue)|\(newScale)"
        let structureChanged = structureKey != appliedStructureKey
        let glassChanged = glass != ThemeManager.glassValue
        let modeChanged = config.mode != mode
        guard structureChanged || glassChanged || modeChanged else { return }

        // Mode drives `preferredColorScheme`, so track it even when the resolved
        // palette is identical (e.g. System→Dark while the system is already dark).
        mode = config.mode
        ThemeManager.glassValue = glass

        if structureChanged {
            appliedStructureKey = structureKey
            let newPalette = ThemePalette.make(dark: baseDark, highContrast: config.highContrast,
                                               accent: Color(hex: accentHex), preset: effectivePreset)
            current = newPalette
            fontScale = newScale
            density = config.density
            ThemeManager.palette = newPalette
            ThemeManager.fontScaleValue = newScale
            ThemeManager.densityValue = config.density
            appearanceRevision &+= 1

            #if DEBUG
            auditContrast()
            #endif
        }
        // Every code path that got here changed *something* the UI shows — bump the
        // live revision so glass panes re-tint and mode-dependent chrome re-renders.
        revision &+= 1
    }

    #if DEBUG
    /// Logs any text/background token pair that falls below WCAG AA (4.5:1). Runs on
    /// every theme apply in debug builds so contrast regressions surface immediately
    /// in the Diagnostics console.
    private func auditContrast() {
        let p = current
        let pairs: [(String, Color, Color)] = [
            ("onSurface/surface", p.onSurface, p.surface),
            ("onSurfaceVariant/surfaceContainer", p.onSurfaceVariant, p.surfaceContainer),
            ("outline(text)/surfaceContainer", p.outline, p.surfaceContainer),
            ("primary/surfaceContainer", p.primary, p.surfaceContainer),
            ("onPrimary/primaryVivid", p.onPrimary, p.primaryVivid),
            ("success/surfaceContainer", p.success, p.surfaceContainer),
            ("warning/surfaceContainer", p.warning, p.surfaceContainer),
            ("error/surfaceContainer", p.error, p.surfaceContainer),
        ]
        for (name, fg, bg) in pairs {
            let r = fg.contrastRatio(against: bg)
            if r < 4.5 {
                Log.ui.warning("Low contrast (\(mode.rawValue)): \(name) = \(String(format: "%.2f", r)):1 (< AA 4.5)")
            }
        }
    }
    #endif
}

// MARK: - Color utilities

extension Color {
    /// Linear-ish RGB mix toward `other` by fraction `t` (0…1), via sRGB components.
    func mixed(with other: Color, by t: Double) -> Color {
        let a = rgba, b = other.rgba
        let f = max(0, min(1, t))
        return Color(.sRGB,
                     red: a.r + (b.r - a.r) * f,
                     green: a.g + (b.g - a.g) * f,
                     blue: a.b + (b.b - a.b) * f,
                     opacity: a.o + (b.o - a.o) * f)
    }

    /// Nudge this color toward black (on a light background) or white (on a dark
    /// one) just far enough to clear `minRatio` WCAG contrast against `bg`. A color
    /// that already passes is returned unchanged, so vivid accents stay vivid and
    /// only the ones that would be unreadable get darkened/lightened. Binary search
    /// finds the smallest mix that passes (≈8-bit precision in 12 steps).
    func readableText(on bg: Color, minRatio: Double) -> Color {
        guard contrastRatio(against: bg) < minRatio else { return self }
        let toward: Color = bg.wcagLuminance > 0.5 ? .black : .white
        var lo = 0.0, hi = 1.0
        for _ in 0..<12 {
            let mid = (lo + hi) / 2
            if mixed(with: toward, by: mid).contrastRatio(against: bg) >= minRatio { hi = mid }
            else { lo = mid }
        }
        return mixed(with: toward, by: hi)
    }

    /// Perceived brightness (0…1) for choosing readable on-colors.
    var perceivedBrightness: Double {
        let c = rgba
        return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    }

    /// WCAG relative luminance (0…1), with sRGB gamma linearization.
    var wcagLuminance: Double {
        let c = rgba
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    /// WCAG contrast ratio against another color (1…21). ≥4.5 passes AA for body text.
    func contrastRatio(against other: Color) -> Double {
        let l1 = wcagLuminance, l2 = other.wcagLuminance
        let (hi, lo) = l1 > l2 ? (l1, l2) : (l2, l1)
        return (hi + 0.05) / (lo + 0.05)
    }

    private var rgba: (r: Double, g: Double, b: Double, o: Double) {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent), Double(ns.alphaComponent))
    }

    /// 0xRRGGBB packed value (drops alpha) — for persisting picker selections.
    var hexValue: UInt32 {
        let c = rgba
        let r = UInt32((c.r * 255).rounded()), g = UInt32((c.g * 255).rounded()), b = UInt32((c.b * 255).rounded())
        return (r << 16) | (g << 8) | b
    }
}
