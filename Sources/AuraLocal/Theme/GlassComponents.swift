import SwiftUI
import AppKit

// MARK: - Native vibrancy material

/// Wraps NSVisualEffectView so panes pick up the desktop wallpaper behind the
/// window (the "Mica" effect the design system calls for).
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        v.isEmphasized = emphasized
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
        v.isEmphasized = emphasized
    }
}

// MARK: - Glass pane

/// A floating glass pane: vibrancy material, indigo-tinted fill, 0.5pt inner
/// stroke and a soft glow shadow. Matches `.glass-pane` in the reference.
struct GlassPane: ViewModifier {
    var radius: CGFloat = Theme.Radius.lg
    var material: NSVisualEffectView.Material = .hudWindow
    var tint: Color = Theme.paneTint
    var stroke: Color = Theme.glassBorder
    var glow: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    VisualEffectView(material: material)
                    tint
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(glow ? 0.35 : 0.18),
                    radius: glow ? 28 : 14, x: 0, y: glow ? 0 : 4)
    }
}

extension View {
    func glassPane(radius: CGFloat = Theme.Radius.lg,
                   material: NSVisualEffectView.Material = .hudWindow,
                   tint: Color = Theme.paneTint,
                   stroke: Color = Theme.glassBorder,
                   glow: Bool = false) -> some View {
        modifier(GlassPane(radius: radius, material: material, tint: tint, stroke: stroke, glow: glow))
    }

    /// A subtler "stacked glass" fill for cards living inside a pane.
    func glassCard(radius: CGFloat = Theme.Radius.md, selected: Bool = false) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(selected ? Theme.Palette.cardFillSelected : Theme.Palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(selected ? Theme.Palette.primary.opacity(0.55) : Theme.glassBorderSoft,
                                  lineWidth: selected ? 1 : 0.5)
            )
    }
}

// MARK: - Micro label (label-caps)

struct MicroLabel: View {
    let text: String
    var color: Color = Theme.Palette.outline
    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.labelCaps())
            .tracking(0.6)
            .foregroundStyle(color)
    }
}

// MARK: - Status dot + chip

/// Status dot. The pulse animates opacity only — animating shadows forces an
/// offscreen render pass every frame and many of these are on screen at once.
struct StatusDot: View {
    var color: Color
    var pulse: Bool = false
    @State private var on = false
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.6), radius: 2)
            .opacity(pulse ? (on ? 1 : 0.45) : 1)
            .onAppear {
                guard pulse else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { on = true }
            }
            .onDisappear { on = false }
    }
}

struct StatusChip: View {
    let text: String
    var color: Color = Theme.Palette.success
    var body: some View {
        HStack(spacing: 5) {
            StatusDot(color: color)
            Text(text)
                .font(Theme.Font.bodySm().weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(color.opacity(0.12))
        )
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
    }
}

// MARK: - Buttons

struct PrimaryGlassButtonStyle: ButtonStyle {
    var fullWidth: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.body().weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Theme.Palette.primaryVivid.opacity(0.95),
                                                Theme.Palette.primaryVivid.opacity(0.78)],
                                       startPoint: .top, endPoint: .bottom)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom))
            )
            .shadow(color: Theme.Palette.primaryVivid.opacity(0.35), radius: 10, y: 2)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct GhostGlassButtonStyle: ButtonStyle {
    var fullWidth: Bool = false
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.body().weight(.medium))
            .foregroundStyle(Theme.Palette.onSurface)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(hover ? Theme.Palette.hoverFill : Theme.Palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(Theme.glassBorderSoft, lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .onHover { hover = $0 }
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Font.displayLg())
                .foregroundStyle(Theme.Palette.onSurface)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Palette.onSurfaceVariant)
                    .frame(maxWidth: 560, alignment: .leading)
            }
        }
    }
}

// MARK: - Mini sparkline / bar helpers (used by telemetry)

struct BarMeter: View {
    var value: Double            // 0...1
    var tint: Color
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.trackFill)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
    }
}
