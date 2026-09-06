//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import SwiftUI
import AppKit

/// Central design tokens. Colors are resolved live from `ThemeManager` so the
/// whole app re-themes (light/dark/contrast/accent/custom) without touching the
/// ~200 `Theme.Palette.*` call sites. Fonts honor the user's font-scale; the
/// larger spacing tokens honor the density setting.
enum Theme {

    // MARK: - Palette (dynamic — reads the active theme)

    /// Every token is a *dynamic* color that resolves light/dark by the drawing
    /// appearance (see `ThemeManager.dynamic`). So a light↔dark switch — whether the
    /// system toggles or the user picks a Mode — recolors the whole app in place,
    /// with no view needing to observe the theme and no `.id` rebuild (scroll
    /// positions are preserved). Cached as `static let` since each dynamic color
    /// reads the live palettes lazily and never needs rebuilding.
    enum Palette {
        static let surface = ThemeManager.dynamic(\.surface)
        static let surfaceContainerLowest = ThemeManager.dynamic(\.surfaceContainerLowest)
        static let surfaceContainerLow = ThemeManager.dynamic(\.surfaceContainerLow)
        static let surfaceContainer = ThemeManager.dynamic(\.surfaceContainer)
        static let surfaceContainerHigh = ThemeManager.dynamic(\.surfaceContainerHigh)
        static let surfaceContainerHighest = ThemeManager.dynamic(\.surfaceContainerHighest)
        static let surfaceBright = ThemeManager.dynamic(\.surfaceBright)

        static let onSurface = ThemeManager.dynamic(\.onSurface)
        static let onSurfaceVariant = ThemeManager.dynamic(\.onSurfaceVariant)
        static let outline = ThemeManager.dynamic(\.outline)
        static let outlineVariant = ThemeManager.dynamic(\.outlineVariant)

        static let primary = ThemeManager.dynamic(\.primary)
        static let primaryVivid = ThemeManager.dynamic(\.primaryVivid)
        static let onPrimary = ThemeManager.dynamic(\.onPrimary)
        static let onPrimaryReadable = ThemeManager.dynamic(\.onPrimaryReadable)
        static let primaryFixed = ThemeManager.dynamic(\.primaryFixed)

        static let secondary = ThemeManager.dynamic(\.secondary)
        static let secondaryContainer = ThemeManager.dynamic(\.secondaryContainer)

        static let success = ThemeManager.dynamic(\.success)
        static let successContainer = ThemeManager.dynamic(\.successContainer)
        static let warning = ThemeManager.dynamic(\.warning)
        static let error = ThemeManager.dynamic(\.error)
        static let errorContainer = ThemeManager.dynamic(\.errorContainer)

        // Adaptive fills (flip white↔black between light & dark).
        static let cardFill = ThemeManager.dynamic(\.cardFill)
        static let cardFillSelected = ThemeManager.dynamic(\.cardFillSelected)
        static let hoverFill = ThemeManager.dynamic(\.hoverFill)
        static let fieldFill = ThemeManager.dynamic(\.fieldFill)
        static let trackFill = ThemeManager.dynamic(\.trackFill)
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

    // MARK: - Glass strokes (dynamic — resolve light/dark by appearance)

    static let glassBorder = ThemeManager.dynamic(\.glassBorder)
    static let glassBorderSoft = ThemeManager.dynamic(\.glassBorderSoft)

    /// Pane fill over the vibrancy material. Driven by the user's Transparency
    /// setting: 0 = nearly solid surface, 1 = mostly the blurred wallpaper. Dynamic,
    /// so it also flips its base surface with the appearance; the transparency level
    /// is read live so a preset change re-tints every pane (`GlassPane` observes the
    /// theme and redraws).
    static var paneTint: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let pal = dark ? ThemeManager.dynDark : ThemeManager.dynLight
            let t = Double(ThemeManager.glassValue)         // 0 solid … 1 clear
            let maxO: Double = dark ? 0.90 : 0.96
            let minO: Double = dark ? 0.28 : 0.42
            return NSColor(pal.surface).withAlphaComponent(maxO - (maxO - minO) * t)
        })
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
