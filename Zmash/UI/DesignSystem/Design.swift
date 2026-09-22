import SwiftUI

/// Design tokens (brief §10): two backgrounds, two text contrasts, one grade-driven accent. Nothing else.
enum Design {
    enum Palette {
        static let background = Color(light: 0xF5F5F2, dark: 0x0B0B0C)
        static let surface = Color(light: 0xEBEBE6, dark: 0x161618)
        static let primary = Color(light: 0x111112, dark: 0xF2F2EF)
        static let secondary = Color(light: 0x111112, dark: 0xF2F2EF).opacity(0.45)
        static let hairline = Color(light: 0x111112, dark: 0xF2F2EF).opacity(0.12)
    }

    /// The only colour in the UI: text ink on the flat, shifting towards warm amber on climbs
    /// and cool blue on descents (full hue from ±8 %).
    static func accent(forGrade grade: Double) -> Color {
        let t = min(max(grade / 8, -1), 1)
        let hue = t >= 0 ? Color(red: 0.93, green: 0.55, blue: 0.20) : Color(red: 0.25, green: 0.52, blue: 0.90)
        return Palette.primary.mix(with: hue, by: abs(t))
    }

    enum Font {
        static func number(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded).monospacedDigit()
        }
        static let unit = SwiftUI.Font.system(size: 15, weight: .medium, design: .rounded)
        static let label = SwiftUI.Font.system(size: 15, weight: .medium)
        static let small = SwiftUI.Font.system(size: 13, weight: .medium)
    }

    enum Space {
        static let gutter: CGFloat = 16
        static let block: CGFloat = 32
        /// Widest a page's content gets on a landscape iPad; beyond this lines get too long to scan.
        static let column: CGFloat = 1100
    }
}

/// Small uppercase heading that names a group of controls ("CONNECTIONS", "YOUR RIDE").
struct SectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .tracking(12 * 0.12)
            .textCase(.uppercase)
            .foregroundStyle(Design.Palette.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

extension Color {
    /// Light/dark pair from hex.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
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

/// Minimal segmented control: text only, active item on a soft surface.
struct Segmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, title in
                let active = value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = value }
                } label: {
                    Text(title)
                        .font(Design.Font.label)
                        .foregroundStyle(active ? Design.Palette.primary : Design.Palette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 10).fill(Design.Palette.background)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
    }
}

/// Large, quiet circular icon button used on the ride screen.
struct RoundIconButton: View {
    let icon: String
    var size: CGFloat = 64
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, size: size * 0.4)
                .foregroundStyle(Design.Palette.primary)
                .frame(width: size, height: size)
                .background(Circle().fill(Design.Palette.surface))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Filled primary action.
struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Design.Palette.background)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 16).fill(Design.Palette.primary.opacity(enabled ? 1 : 0.25)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Elevation silhouette from a grade series (each sample = equal time step).
struct ElevationStrip: View {
    let grades: [Double]
    var color: Color = Design.Palette.primary
    var marker: Bool = false

    var body: some View {
        Canvas { context, size in
            guard grades.count > 1 else { return }
            var heights: [Double] = [0]
            for g in grades.dropFirst() { heights.append(heights.last! + g) }
            let lo = heights.min()!, hi = heights.max()!
            let span = max(hi - lo, 20) // keep gentle terrain looking gentle
            let step = size.width / CGFloat(heights.count - 1)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            for (i, h) in heights.enumerated() {
                let y = size.height - CGFloat((h - lo) / span) * size.height * 0.9 - size.height * 0.05
                path.addLine(to: CGPoint(x: CGFloat(i) * step, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .color(color.opacity(0.18)))
            if marker {
                let first = size.height - CGFloat((heights[0] - lo) / span) * size.height * 0.9 - size.height * 0.05
                context.fill(Path(ellipseIn: CGRect(x: -4, y: first - 4, width: 8, height: 8)), with: .color(color))
            }
        }
    }
}
