//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import SwiftUI

/// Full theming controls: appearance mode, accent, contrast, density, font scale,
/// and saved custom themes. Edits mutate `settings.theme`; `RootView` observes that
/// and re-applies the palette live (no restart).
struct AppearanceSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore

    private var theme: Binding<ThemeConfig> { $settingsStore.settings.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            appearanceCard
            customThemesCard
        }
    }

    // MARK: Appearance

    private var appearanceCard: some View {
        SettingsCard(title: "Appearance", symbol: "paintpalette") {
            LabeledField(label: "Mode") {
                Picker("", selection: theme.mode) {
                    ForEach(AppearanceMode.allCases) { Text($0.displayName).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }

            LabeledField(label: "Accent") {
                HStack(spacing: 8) {
                    ForEach(ThemePalette.accentChoices, id: \.hex) { choice in
                        accentSwatch(choice.hex)
                    }
                    Divider().frame(height: 22).overlay(Theme.glassBorderSoft)
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: settingsStore.settings.theme.accentHex) },
                        set: { settingsStore.settings.theme.accentHex = $0.hexValue
                               settingsStore.settings.theme.activePresetID = nil }))
                        .labelsHidden().frame(width: 44)
                }
            }

            Toggle("High contrast", isOn: theme.highContrast)
                .toggleStyle(.switch).tint(Theme.Palette.primaryVivid).font(Theme.Font.body())

            LabeledField(label: "Density") {
                Picker("", selection: theme.density) {
                    ForEach(ThemeDensity.allCases) { Text($0.displayName).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }

            LabeledField(label: "Transparency") {
                transparencyPresetPicker
            }
            Text("How much of the desktop shows through the app's glass panels. Text size follows your macOS system setting automatically.")
                .font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline)
        }
    }

    // MARK: Transparency (discrete presets — no dragging, so no live re-tint churn)

    /// Fixed glass levels. A slider fired a change on every pixel of the drag; a few
    /// labelled buttons give the same control in one deliberate tap.
    private static let transparencyPresets: [(label: String, value: Double)] = [
        ("Solid", 0.0), ("Subtle", 0.30), ("Medium", 0.55), ("Heavy", 0.85),
    ]

    private var transparencyPresetPicker: some View {
        let current = settingsStore.settings.theme.glassTransparency
        // Highlight whichever preset the stored value is closest to (so a legacy
        // slider value still lights up exactly one button).
        let activeValue = Self.transparencyPresets
            .min { abs($0.value - current) < abs($1.value - current) }?.value
        return HStack(spacing: 6) {
            ForEach(Self.transparencyPresets, id: \.value) { preset in
                let active = preset.value == activeValue
                Button {
                    settingsStore.settings.theme.glassTransparency = preset.value
                } label: {
                    Text(preset.label)
                        .font(Theme.Font.bodySm().weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .fill(active ? Theme.Palette.primaryVivid : Theme.Palette.cardFill))
                        .foregroundStyle(active ? Color.white : Theme.Palette.onSurfaceVariant)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .strokeBorder(Theme.glassBorderSoft, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func accentSwatch(_ hex: UInt32) -> some View {
        let isActive = settingsStore.settings.theme.activePresetID == nil
            && settingsStore.settings.theme.accentHex == hex
        return Circle()
            .fill(Color(hex: hex))
            .frame(width: 22, height: 22)
            .overlay(Circle().strokeBorder(isActive ? Theme.Palette.onSurface : Theme.glassBorderSoft,
                                           lineWidth: isActive ? 2 : 0.5))
            .contentShape(Circle())
            .onTapGesture {
                settingsStore.settings.theme.accentHex = hex
                settingsStore.settings.theme.activePresetID = nil
            }
    }

    // MARK: Custom themes

    private var customThemesCard: some View {
        SettingsCard(title: "Custom Themes", symbol: "swatchpalette") {
            if settingsStore.settings.theme.customThemes.isEmpty {
                Text("Save the current accent + base as a reusable theme.")
                    .font(Theme.Font.bodySm()).foregroundStyle(Theme.Palette.outline)
            } else {
                ForEach(settingsStore.settings.theme.customThemes) { preset in
                    presetRow(preset)
                }
            }
            HStack {
                Spacer()
                Button { saveCurrentAsPreset() } label: {
                    Label("Save Current as Theme", systemImage: "plus").font(Theme.Font.bodySm())
                }.buttonStyle(GhostGlassButtonStyle())
            }
        }
    }

    private func presetRow(_ preset: ThemePreset) -> some View {
        let active = settingsStore.settings.theme.activePresetID == preset.id
        return HStack(spacing: 10) {
            Circle().fill(Color(hex: preset.accentHex)).frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Theme.glassBorderSoft, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name).font(Theme.Font.body().weight(.semibold)).foregroundStyle(Theme.Palette.onSurface)
                Text(preset.basedOnDark ? "Dark base" : "Light base").font(Theme.Font.micro()).foregroundStyle(Theme.Palette.outline)
            }
            Spacer()
            Button(active ? "Active" : "Apply") {
                if active {
                    settingsStore.settings.theme.activePresetID = nil
                } else {
                    // Apply the preset's accent + snap Mode to its saved base so it
                    // looks as saved. Mode stays the source of truth afterward, so the
                    // Mode switch keeps working while the preset is active.
                    settingsStore.settings.theme.activePresetID = preset.id
                    settingsStore.settings.theme.accentHex = preset.accentHex
                    settingsStore.settings.theme.mode = preset.basedOnDark ? .dark : .light
                }
            }.buttonStyle(GhostGlassButtonStyle()).font(Theme.Font.bodySm())
            Button {
                settingsStore.settings.theme.customThemes.removeAll { $0.id == preset.id }
                if active { settingsStore.settings.theme.activePresetID = nil }
            } label: { Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(Theme.Palette.outline) }
                .buttonStyle(.plain)
        }
        .padding(10)
        .glassCard(radius: Theme.Radius.md, selected: active)
    }

    private func saveCurrentAsPreset() {
        let cfg = settingsStore.settings.theme
        let baseDark = cfg.mode != .light
        let n = cfg.customThemes.count + 1
        let preset = ThemePreset(name: "Theme \(n)", basedOnDark: baseDark, accentHex: cfg.accentHex)
        settingsStore.settings.theme.customThemes.append(preset)
        settingsStore.settings.theme.activePresetID = preset.id
    }
}
