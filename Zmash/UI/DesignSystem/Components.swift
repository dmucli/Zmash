import SwiftUI

// The Zmash Design System's components (D114): pills for every button, chip and nav item; 16-pt cards with a
// hairline and a bib index; sunk tiles inside them; mono labels over bib numerals.

/// Press = scale .97, 140 ms ease-out. No bounce.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Design.Motion.fast, value: configuration.isPressed)
    }
}

/// A pill button in one of the system's four looks.
struct PillButton: View {
    enum Style { case primary, secondary, invert, glass, tarmac }

    let title: String
    var icon: String? = nil
    var style: Style = .secondary
    var compact = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Icon(icon, size: compact ? 14 : 15) }
                Text(title).font(Design.Font.sans(compact ? 13 : 14, weight: style == .primary || style == .invert ? 700 : 600))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 14 : 18)
            .frame(minHeight: compact ? 36 : 44)
            .background { background }
            .contentShape(Capsule())
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
    }

    private var foreground: Color {
        switch style {
        case .primary: Design.Palette.onAccent
        case .secondary: Design.Palette.fg1
        case .invert: Design.Palette.invertFg
        case .glass: Design.Tarmac.bone
        case .tarmac: Design.Tarmac.t900
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .primary: Capsule().fill(Design.Accent.vermilion)
        case .secondary:
            Capsule().fill(Design.Palette.surfaceGlass)
            Capsule().strokeBorder(Design.Palette.borderStrong, lineWidth: 1)
        case .invert: Capsule().fill(Design.Palette.invertBg)
        case .glass: Capsule().fill(Design.Tarmac.glass)
        case .tarmac: Capsule().fill(Design.Tarmac.bone)
        }
    }
}

/// A filter or choice chip: a hairline pill, inverted when on.
struct Chip: View {
    let title: String
    var icon: String? = nil
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Icon(icon, size: 13) }
                Text(title).font(Design.Font.sans(13, weight: 600)).lineLimit(1)
            }
            .foregroundStyle(selected ? Design.Palette.invertFg : Design.Palette.fg2)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background {
                if selected {
                    Capsule().fill(Design.Palette.invertBg)
                } else {
                    Capsule().strokeBorder(Design.Palette.borderStrong, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A small static tag (no action): "YOU'RE ON IT", "DONE", a jersey.
struct Tag: View {
    let title: String
    var color: Color = Design.Palette.fg2
    var fill: Color? = nil

    var body: some View {
        Text(title)
            .monoLabel(10)
            .foregroundStyle(fill == nil ? color : Design.Palette.onAccent)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background {
                if let fill { Capsule().fill(fill) } else { Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1) }
            }
    }
}

/// The two-digit bib index a card carries ("01", "02"…).
struct BibIndex: View {
    let n: Int
    var size: CGFloat = 44
    var lit = false
    var hero = false

    var body: some View {
        Text(String(format: "%02d", n))
            .font(Design.Font.bib(size))
            .foregroundStyle(lit || hero ? Design.Accent.vermilion : Design.Palette.fgGhost)
            .accessibilityHidden(true)
    }
}

/// Card background: 16 radius, 1-pt border, no shadow; selected = 2-pt vermilion ring; hero = bar-tape hatch.
struct CardBackground: View {
    var selected = false
    var hero = false
    var radius: CGFloat = Design.Radius.lg

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if hero {
                HatchFill().clipShape(shape)
            } else {
                shape.fill(Design.Palette.surface)
                shape.strokeBorder(Design.Palette.border, lineWidth: 1)
            }
            if selected { shape.strokeBorder(Design.Accent.vermilion, lineWidth: 2) }
        }
    }
}

extension View {
    /// Wraps content as a system card.
    func card(padding: CGFloat = 20, selected: Bool = false, hero: Bool = false, radius: CGFloat = Design.Radius.lg) -> some View {
        self.padding(padding)
            .background(CardBackground(selected: selected, hero: hero, radius: radius))
            .environment(\.onHero, hero)
    }

    /// A sunk tile inside a card: 12 radius, surface-sunk.
    func sunkTile(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous).fill(Design.Palette.surfaceSunk))
    }

    /// Bone text and fills on a hero card.
    func heroText(_ on: Bool) -> some View { environment(\.onHero, on) }
}

extension EnvironmentValues {
    /// Inside a hero (hatch) card: text is bone whatever the theme.
    @Entry var onHero = false
}

/// A mono label over a bib value with a small unit: "HOURS / 6.4 h".
struct StatTile: View {
    let label: String
    let value: String
    var unit: String = ""
    var size: CGFloat = 40
    @Environment(\.onHero) private var onHero
    @Environment(\.onTarmac) private var onTarmac

    var body: some View {
        let dark = onHero || onTarmac
        VStack(alignment: .leading, spacing: 4) {
            Text(label).monoLabel()
                .foregroundStyle(dark ? Design.Palette.fgOnHero2 : Design.Palette.fg3)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(Design.Font.bib(size))
                    .foregroundStyle(dark ? Design.Palette.fgOnHero : Design.Palette.fg1)
                if !unit.isEmpty {
                    Text(unit).font(Design.Font.sans(14, weight: 500))
                        .foregroundStyle(dark ? Design.Palette.fgOnHero2 : Design.Palette.fg3)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A row of stats split by hairlines, inside one card (the summary's six-stat strip, home's THIS WEEK).
struct StatStrip: View {
    let stats: [(label: String, value: String, unit: String)]
    var size: CGFloat = 40
    var columns: Int? = nil

    var body: some View {
        let cols = columns ?? stats.count
        let rows = stride(from: 0, to: stats.count, by: max(cols, 1)).map { Array(stats[$0..<min($0 + cols, stats.count)]) }
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                if r > 0 { Rectangle().fill(Design.Palette.border).frame(height: 1) }
                HStack(spacing: 0) {
                    ForEach(rows[r].indices, id: \.self) { i in
                        if i > 0 { Rectangle().fill(Design.Palette.border).frame(width: 1) }
                        let s = rows[r][i]
                        StatTile(label: s.label, value: s.value, unit: s.unit, size: size)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20).padding(.vertical, 16)
                    }
                    ForEach(0..<(cols - rows[r].count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(CardBackground())
    }
}

/// The system's switch: a pill track in vermilion when on.
struct PillToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(Design.Motion.fast) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: 12) {
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? Design.Accent.vermilion : Design.Palette.surfaceSunk)
                    Capsule().strokeBorder(configuration.isOn ? .clear : Design.Palette.borderStrong, lineWidth: 1)
                    Circle().fill(configuration.isOn ? Design.Palette.onAccent : Design.Palette.fg3)
                        .frame(width: 20, height: 20).padding(4)
                }
                .frame(width: 48, height: 28)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A settings row: title and quiet note on the left, a control on the right.
struct SettingRow<Trailing: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Design.Font.label).foregroundStyle(Design.Palette.fg1)
                if let note {
                    Text(note).font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 12)
    }
}

/// A key cap (controller buttons, keyboard hints): mono on a sunk 4-pt square.
struct KeyCap: View {
    let label: String
    @Environment(\.onTarmac) private var onTarmac

    var body: some View {
        Text(label)
            .font(Design.Font.mono(12, weight: 700))
            .foregroundStyle(onTarmac ? Design.Tarmac.bone : Design.Palette.fg1)
            .padding(.horizontal, 7).frame(minWidth: 26, minHeight: 24)
            .background {
                RoundedRectangle(cornerRadius: Design.Radius.xs).fill(onTarmac ? Design.Tarmac.t800 : Design.Palette.surfaceSunk)
                RoundedRectangle(cornerRadius: Design.Radius.xs)
                    .strokeBorder(onTarmac ? Design.Tarmac.t700 : Design.Palette.borderStrong, lineWidth: 1)
            }
    }
}

/// A HUD chip on the ride: tarmac glass, 12 radius, blur.
struct HUDChip<Content: View>: View {
    var horizontal: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, horizontal).padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous).fill(Design.Tarmac.glass)
            }
            .environment(\.colorScheme, .dark)
            .foregroundStyle(Design.Tarmac.bone)
    }
}

/// "ZMASH": Archivo at 80 % width, 900, italic. There is no logo mark.
struct Wordmark: View {
    var size: CGFloat = 22
    var color: Color = Design.Palette.fg1

    var body: some View {
        Text("ZMASH")
            .font(FaceFont.font(.archivoItalic, size, weight: 900, width: 80))
            .tracking(size * -0.01)
            .foregroundStyle(color)
            .accessibilityLabel("Zmash")
    }
}

extension View {
    /// Sheet corners and shadow (22 radius, shadow-sheet).
    func zmashSheet() -> some View {
        self.presentationCornerRadius(Design.Radius.xl)
            .presentationBackground(Design.Palette.bg)
    }
}
