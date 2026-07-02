import SwiftUI

/// Central design tokens. Colors are resolved live from `ThemeManager` so the
/// whole app re-themes (light/dark/contrast/accent/custom) without touching the
/// ~200 `Theme.Palette.*` call sites. Fonts honor the user's font-scale; the
/// larger spacing tokens honor the density setting.
enum Theme {

    // MARK: - Palette (dynamic — reads the active theme)

    enum Palette {
        private static var p: ThemePalette { ThemeManager.palette }

        static var surface: Color { p.surface }
        static var surfaceContainerLowest: Color { p.surfaceContainerLowest }
        static var surfaceContainerLow: Color { p.surfaceContainerLow }
        static var surfaceContainer: Color { p.surfaceContainer }
        static var surfaceContainerHigh: Color { p.surfaceContainerHigh }
        static var surfaceContainerHighest: Color { p.surfaceContainerHighest }
        static var surfaceBright: Color { p.surfaceBright }

        static var onSurface: Color { p.onSurface }
        static var onSurfaceVariant: Color { p.onSurfaceVariant }
        static var outline: Color { p.outline }
        static var outlineVariant: Color { p.outlineVariant }

        static var primary: Color { p.primary }
        static var primaryVivid: Color { p.primaryVivid }
        static var onPrimary: Color { p.onPrimary }
        static var onPrimaryReadable: Color { p.onPrimaryReadable }
        static var primaryFixed: Color { p.primaryFixed }

        static var secondary: Color { p.secondary }
        static var secondaryContainer: Color { p.secondaryContainer }

        static var success: Color { p.success }
        static var successContainer: Color { p.successContainer }
        static var warning: Color { p.warning }
        static var error: Color { p.error }
        static var errorContainer: Color { p.errorContainer }

        // Adaptive fills (flip white↔black between light & dark).
        static var cardFill: Color { p.cardFill }
        static var cardFillSelected: Color { p.cardFillSelected }
        static var hoverFill: Color { p.hoverFill }
        static var fieldFill: Color { p.fieldFill }
        static var trackFill: Color { p.trackFill }
    }

    // MARK: - Radii (continuous curves)

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let pill: CGFloat = 999
    }

    // MARK: - Spacing (8px rhythm; larger tokens honor density)

    enum Space {
        private static var d: CGFloat { ThemeManager.densityValue.scale }
        static let unit: CGFloat = 4
        static let tight: CGFloat = 8
        static var card: CGFloat { 16 * d }
        static var gutter: CGFloat { 20 * d }
        static var page: CGFloat { 24 * d }
        static let windowInset: CGFloat = 12
    }

    // MARK: - Glass strokes (dynamic)

    static var glassBorder: Color { ThemeManager.palette.glassBorder }
    static var glassBorderSoft: Color { ThemeManager.palette.glassBorderSoft }

    /// Pane fill over the vibrancy material. Driven by the user's Transparency
    /// setting: 0 = nearly solid surface, 1 = mostly the blurred wallpaper.
    static var paneTint: Color {
        let t = ThemeManager.glassValue                     // 0 solid … 1 clear
        let dark = ThemeManager.palette.isDark
        let maxO: Double = dark ? 0.90 : 0.96
        let minO: Double = dark ? 0.28 : 0.42
        return Palette.surface.opacity(maxO - (maxO - minO) * Double(t))
    }

    // MARK: - Typography (scaled by the user's font-scale)

    /// Every text style multiplies its base size by the user's font-scale. Call
    /// sites must use these tokens (or `scaled`) rather than a raw `.system(size:)`
    /// so the Text Size slider affects *all* text uniformly. Icon glyph sizes may
    /// still use a fixed `.system(size:)` — they intentionally don't track text.
    enum Font {
        static var s: CGFloat { ThemeManager.fontScaleValue }

        // Named roles.
        static func displayLg() -> SwiftUI.Font { .system(size: 30 * s, weight: .bold, design: .default) }
        static func statLg() -> SwiftUI.Font { .system(size: 22 * s, weight: .bold, design: .default) }
        static func stat() -> SwiftUI.Font { .system(size: 20 * s, weight: .bold, design: .default) }
        static func headline() -> SwiftUI.Font { .system(size: 22 * s, weight: .semibold, design: .default) }
        static func titleSm() -> SwiftUI.Font { .system(size: 16 * s, weight: .semibold, design: .default) }
        static func body() -> SwiftUI.Font { .system(size: 13 * s, weight: .regular, design: .default) }
        static func bodySm() -> SwiftUI.Font { .system(size: 11.5 * s, weight: .regular, design: .default) }
        static func code() -> SwiftUI.Font { .system(size: 12.5 * s, weight: .regular, design: .monospaced) }
        static func labelCaps() -> SwiftUI.Font { .system(size: 10.5 * s, weight: .bold, design: .default) }
        static func tag() -> SwiftUI.Font { .system(size: 10.5 * s, weight: .medium, design: .default) }
        static func micro() -> SwiftUI.Font { .system(size: 9.5 * s, weight: .regular, design: .default) }

        /// Markdown heading size (h1…h6) that tracks the font-scale.
        static func mdHeading(_ level: Int) -> SwiftUI.Font {
            let base: CGFloat = level <= 1 ? 18 : level == 2 ? 16 : 14
            return .system(size: base * s, weight: .semibold, design: .default)
        }

        /// Escape hatch for one-off text sizes — still honors the font-scale.
        static func scaled(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular,
                           design: SwiftUI.Font.Design = .default) -> SwiftUI.Font {
            .system(size: size * s, weight: weight, design: design)
        }
    }

    // MARK: - Ambient background gradient (accent / emerald corner glows)

    static var ambientBackground: some View {
        ZStack {
            Palette.surfaceContainerLowest
            RadialGradient(
                colors: [Palette.primaryVivid.opacity(0.10), .clear],
                center: .topLeading, startRadius: 0, endRadius: 720
            )
            RadialGradient(
                colors: [Palette.success.opacity(0.05), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 720
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Color hex helper

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
