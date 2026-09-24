import SwiftUI

/// Design tokens from the Zmash Design System (`design/Zmash Design System/tokens`, D113): a warm bone → tarmac ramp,
/// vermilion for effort and team blue for terrain, Archivo with 62 %-width "bib" numerals, JetBrains Mono labels.
/// OKLCH values are converted to sRGB once and written here as hex.
enum Design {
    /// The semantic colours, light and dark.
    enum Palette {
        static let bg = Color(light: 0xF4F1EC, dark: 0x121110)
        static let surface = Color(light: 0xFFFFFF, dark: 0x1C1B19)
        static let surfaceSunk = Color(light: 0xE9E5DD, dark: 0x0C0B0A)
        static let surfaceGlass = Color(light: 0xFFFFFF, lightAlpha: 0.55, dark: 0x121110, darkAlpha: 0.78)
        static let border = Color(light: 0xE3DED4, dark: 0x2E2C28)
        static let borderStrong = Color(light: 0xD9D4CA, dark: 0x3A3732)
        static let fg1 = Color(light: 0x16140F, dark: 0xF4F1EC)
        static let fg2 = Color(light: 0x4A463E, dark: 0xC9C4B8)
        static let fg3 = Color(light: 0x6B665C, dark: 0x8E897D)
        static let fgGhost = Color(light: 0xD9D4CA, dark: 0x3A3732)
        static let fgOnHero = Color(hex: 0xF4F1EC)
        static let fgOnHero2 = Color(hex: 0xA8A396)
        static let accent = Accent.vermilion
        static let onAccent = Color(hex: 0x16140F)
        static let terrain = Accent.teamBlue
        static let terrainFill = Color(light: 0x008EF9, lightAlpha: 0.16, dark: 0x008EF9, darkAlpha: 0.35)
        static let stripeMid = Color(light: 0x16140F, dark: 0xF4F1EC)
        static let invertBg = Color(light: 0x16140F, dark: 0xF4F1EC)
        static let invertFg = Color(light: 0xF4F1EC, dark: 0x121110)
        static let blockRest = Color(light: 0xC9C3B7, dark: 0x4A4740)

        // The names the app grew up with, pointing at their system equivalents.
        static let background = bg
        static let primary = fg1
        static let secondary = fg3
        static let hairline = border
    }

    /// The ride screen and HUD chips: always tarmac, whatever the theme.
    enum Tarmac {
        static let t900 = Color(hex: 0x121110)
        static let t850 = Color(hex: 0x1C1B19)
        static let t800 = Color(hex: 0x2A2825)
        static let t750 = Color(hex: 0x2E2C28)
        static let t700 = Color(hex: 0x3A3732)
        static let bone = Color(hex: 0xF4F1EC)
        static let bone2 = Color(hex: 0xA8A396)
        static let stone = Color(hex: 0x8E897D)
        static let glass = Color(hex: 0x121110, opacity: 0.78)
    }

    /// Two accents with equal lightness and chroma: vermilion is effort, team blue is terrain.
    enum Accent {
        static let vermilion = Color(hex: 0xE85433) // oklch(0.64 0.19 34)
        static let vermilionDeep = Color(hex: 0xC52D1F) // oklch(0.54 0.19 30)
        static let teamBlue = Color(hex: 0x008EF9) // oklch(0.64 0.19 250), just outside sRGB
    }

    /// Status colours, always with a label beside them.
    enum Status {
        static let go = Color(light: 0x36A558, dark: 0x53BE70)
        static let caution = Color(hex: 0xE9AB2B)
        static let stop = Color(hex: 0xD73337)
    }

    /// Power zones: stone → blue (aerobic) → vermilion (hard). Not a rainbow.
    enum Zone {
        static let z1 = Color(hex: 0xB8B2A6)
        static let z2 = Color(hex: 0x7FB6EE)
        static let z3 = Accent.teamBlue
        static let z4 = Color(hex: 0xF48A64)
        static let z5 = Accent.vermilion
        static let z6 = Accent.vermilionDeep

        /// The zone colour for a target as a fraction of FTP (Coggan's bands).
        static func color(forFTPFraction f: Double) -> Color {
            switch f {
            case ..<0.56: z1
            case ..<0.76: z2
            case ..<0.91: z3
            case ..<1.06: z4
            case ..<1.21: z5
            default: z6
            }
        }
    }

    /// Climbing turns vermilion, descending team blue (full from ±8 %); ink on the flat.
    static func accent(forGrade grade: Double, base: Color = Palette.fg1) -> Color {
        let t = min(max(grade / 8, -1), 1)
        return base.mix(with: t >= 0 ? Accent.vermilion : Accent.teamBlue, by: abs(t))
    }

    @MainActor
    enum Font {
        /// Race-bib numerals: Archivo at 62 % width, 800.
        static func bib(_ size: CGFloat, weight: Double = 800) -> SwiftUI.Font {
            FaceFont.font(.archivo, size, weight: weight, width: 62)
        }

        /// Archivo text at 100 % width.
        static func sans(_ size: CGFloat, weight: Double = 400) -> SwiftUI.Font {
            FaceFont.font(.archivo, size, weight: weight, width: 100)
        }

        /// JetBrains Mono, for labels and clocks.
        static func mono(_ size: CGFloat, weight: Double = 500) -> SwiftUI.Font {
            FaceFont.font(.mono, size, weight: weight)
        }

        /// A number: bib numerals from 20 pt up, tabular Archivo below (table cells).
        static func number(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            let w: Double = switch weight {
            case .ultraLight, .thin, .light: 400
            case .regular: 500
            case .medium: 600
            default: 800
            }
            return size >= 20 ? bib(size, weight: w) : sans(size, weight: w)
        }

        static let display = sans(42, weight: 700)
        static let h1 = sans(30, weight: 700)
        static let h2 = sans(21, weight: 700)
        static let body = sans(15)
        /// Row titles and buttons.
        static let label = sans(15, weight: 600)
        static let small = sans(13, weight: 500)
        static let unit = sans(14, weight: 500)
        static func wordmark(_ size: CGFloat = 22) -> SwiftUI.Font { FaceFont.font(.archivoItalic, size, weight: 900, width: 80) }
    }

    enum Space {
        static let gutter: CGFloat = 16
        static let block: CGFloat = 32
        /// The screen gutter on a tablet (phones keep `gutter`).
        static let screen: CGFloat = 32
        /// Between cards.
        static let gap: CGFloat = 14
        /// Widest a page's content gets on a landscape iPad; beyond this lines get too long to scan.
        static let column: CGFloat = 1100
    }

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 22
    }

    enum Motion {
        /// ease-out cubic-bezier(.2,.7,.2,1); no bounces.
        static let fast = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.14)
        static let base = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.22)
    }
}

extension Design {
    /// Navigation bars in Archivo (inline titles 17/700, large titles 34/700 at -0.02 em), set once at launch.
    @MainActor static func applyAppearance() {
        let bar = UINavigationBar.appearance()
        bar.titleTextAttributes = [.font: FaceFont.uiFont(.archivo, 17, weight: 700, width: 100)]
        bar.largeTitleTextAttributes = [.font: FaceFont.uiFont(.archivo, 34, weight: 700, width: 100), .kern: -0.68]
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: FaceFont.uiFont(.archivo, 17, weight: 600, width: 100)], for: .normal)
    }
}

/// The type scale's tracking and leading, which a `Font` can't carry.
enum TextStyle {
    case display, h1, h2, body, small

    @MainActor var font: Font {
        switch self {
        case .display: Design.Font.display
        case .h1: Design.Font.h1
        case .h2: Design.Font.h2
        case .body: Design.Font.body
        case .small: Design.Font.small
        }
    }

    var size: CGFloat {
        switch self {
        case .display: 42
        case .h1: 30
        case .h2: 21
        case .body: 15
        case .small: 13
        }
    }

    var trackingEm: CGFloat {
        switch self {
        case .display: -0.025
        case .h1: -0.02
        case .h2: -0.01
        case .body, .small: 0
        }
    }

    var leading: CGFloat {
        switch self {
        case .display: 1.05
        case .h1: 1.1
        case .h2: 1.2
        case .body: 1.5
        case .small: 1.4
        }
    }
}

extension View {
    /// Text in one of the system's styles (font, tracking and line height).
    func textStyle(_ style: TextStyle, size: CGFloat? = nil) -> some View {
        let s = size ?? style.size
        let font: Font = MainActor.assumeIsolated {
            size == nil ? style.font : Design.Font.sans(s, weight: style == .body || style == .small ? 400 : 700)
        }
        return self.font(font)
            .tracking(s * style.trackingEm)
            .lineSpacing(max(0, s * (style.leading - 1.2)))
    }

    /// The mono label: JetBrains Mono 11, uppercase, +0.14 em.
    func monoLabel(_ size: CGFloat = 11) -> some View {
        let font = MainActor.assumeIsolated { Design.Font.mono(size) }
        return self.font(font).tracking(size * 0.14).textCase(.uppercase)
    }
}

/// Mono uppercase heading that names a group ("CONNECTIONS", "YOUR RIDE").
struct SectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .monoLabel()
            .foregroundStyle(Design.Palette.fg3)
            .accessibilityAddTraits(.isHeader)
    }
}

extension Color {
    /// Light/dark pair from hex.
    init(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark).withAlphaComponent(darkAlpha)
                : UIColor(hex: light).withAlphaComponent(lightAlpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Lucide icon from the asset catalog, rendered as a template.
struct Icon: View {
    let name: String
    var size: CGFloat = 22

    init(_ name: String, size: CGFloat = 22) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image("lucide-\(name)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Segmented control as a row of pills: the active one inverted (ink on light, bone on dark).
struct Segmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, title in
                let active = value == selection
                Button {
                    withAnimation(Design.Motion.fast) { selection = value }
                } label: {
                    Text(title)
                        .font(Design.Font.sans(14, weight: 600))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(active ? Design.Palette.invertFg : Design.Palette.fg2)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if active { Capsule().fill(Design.Palette.invertBg) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Design.Palette.surfaceSunk))
    }
}

/// Circular icon button: a hairline ring on the page, or filled in vermilion for the action that moves you on.
struct RoundIconButton: View {
    let icon: String
    var size: CGFloat?
    var accent = false
    let action: () -> Void
    @Environment(\.roundButtonSize) private var defaultSize
    @Environment(\.onTarmac) private var onTarmac

    init(icon: String, size: CGFloat? = nil, accent: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.size = size
        self.accent = accent
        self.action = action
    }

    var body: some View {
        let size = size ?? defaultSize
        Button(action: action) {
            Icon(icon, size: size * 0.38)
                .foregroundStyle(accent ? Design.Palette.onAccent : onTarmac ? Design.Tarmac.bone : Design.Palette.fg1)
                .frame(width: size, height: size)
                .background {
                    if accent {
                        Circle().fill(Design.Accent.vermilion)
                    } else if onTarmac {
                        Circle().fill(Design.Tarmac.glass)
                        Circle().strokeBorder(Design.Tarmac.t700, lineWidth: 1)
                    } else {
                        Circle().fill(Design.Palette.surfaceGlass)
                        Circle().strokeBorder(Design.Palette.borderStrong, lineWidth: 1)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
    }
}

/// The primary action: a vermilion pill with ink text.
struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Icon(icon, size: 16) }
                Text(title).font(Design.Font.sans(17, weight: 700))
            }
            .foregroundStyle(Design.Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Capsule().fill(Design.Accent.vermilion.opacity(enabled ? 1 : 0.3)))
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
    }
}

/// Elevation silhouette from a grade series (each sample = equal time step): a line over a terrain-blue fill.
struct ElevationStrip: View {
    let grades: [Double]
    var color: Color = Design.Palette.fg1
    var marker: Bool = false
    var fill: Color = Design.Palette.terrainFill

    var body: some View {
        Canvas { context, size in
            guard grades.count > 1 else { return }
            var heights: [Double] = [0]
            for g in grades.dropFirst() { heights.append(heights.last! + g) }
            let lo = heights.min()!, hi = heights.max()!
            let span = max(hi - lo, 20) // keep gentle terrain looking gentle
            let step = size.width / CGFloat(heights.count - 1)
            var line = Path()
            for (i, h) in heights.enumerated() {
                let p = CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat((h - lo) / span) * size.height * 0.9 - size.height * 0.05)
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(fill))
            context.stroke(line, with: .color(color), lineWidth: 1.5)
            if marker, let first = line.currentPoint.map({ _ in heights[0] }) {
                let y = size.height - CGFloat((first - lo) / span) * size.height * 0.9 - size.height * 0.05
                context.fill(Path(ellipseIn: CGRect(x: -7, y: y - 7, width: 14, height: 14)), with: .color(Design.Tarmac.t900))
                context.fill(Path(ellipseIn: CGRect(x: -5, y: y - 5, width: 10, height: 10)), with: .color(color))
            }
        }
    }
}

extension EnvironmentValues {
    /// The size of `RoundIconButton`s that don't set their own (smaller on a phone).
    @Entry var roundButtonSize: CGFloat = 64
    /// Inside the ride: controls take the always-tarmac look whatever the theme.
    @Entry var onTarmac = false
}

extension View {
    func buttonSize(_ size: CGFloat) -> some View { environment(\.roundButtonSize, size) }
}
