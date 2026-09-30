import SwiftUI

// The system's textures (D114): grain on every screen, bar-tape hatch on hero cards, lane dashes for distance, the
// jersey tri-stripe on each screen's top edge. Never gradients as decoration.

/// Diagonal bar-tape hatch: 135°, 10-pt stripes of #1F1D1A / #191815 (raised in dark: #252320 / #1E1C19).
struct HatchFill: View {
    var raised: Bool? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let up = raised ?? (scheme == .dark)
        let a = Color(hex: up ? 0x252320 : 0x1F1D1A), b = Color(hex: up ? 0x1E1C19 : 0x191815)
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(a))
            // Bands of b 10 pt wide every 20 pt along the diagonal (perpendicular spacing 20/√2 per axis step).
            let period: CGFloat = 20 * 2.squareRoot()
            let band: CGFloat = 10 * 2.squareRoot()
            var x = -size.height
            while x < size.width + size.height {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x + band, y: 0))
                p.addLine(to: CGPoint(x: x + band + size.height, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: size.height))
                p.closeSubpath()
                context.fill(p, with: .color(b))
                x += period
            }
        }
        .accessibilityHidden(true)
    }
}

/// Lane dashes: 20 on, 12 off.
struct LaneDashes: View {
    var color: Color = Design.Palette.fg3
    var thickness: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: (size.height - thickness) / 2, width: min(20, size.width - x), height: thickness)),
                             with: .color(color))
                x += 32
            }
        }
        .frame(height: max(thickness, 2))
        .accessibilityHidden(true)
    }
}

/// The jersey tri-stripe: vermilion 6 : ink/bone 1 : team blue 2, 5 pt tall.
struct TriStripe: View {
    var height: CGFloat = 5
    var mid: Color = Design.Palette.stripeMid

    var body: some View {
        GeometryReader { g in
            HStack(spacing: 0) {
                Design.Accent.vermilion.frame(width: g.size.width * 6 / 9)
                mid.frame(width: g.size.width / 9)
                Design.Accent.teamBlue
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Fine grain: a 200-pt noise tile, multiplied on light and screened on dark.
struct Grain: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Image(uiImage: dark ? Self.darkTile : Self.lightTile)
            .resizable(resizingMode: .tile)
            .blendMode(dark ? .screen : .multiply)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Generated once: warm grey speckle at the design's alpha (.22 light, .07 dark) under the prototype's .55 layer.
    private static let lightTile = tile(r: 0.5, g: 0.45, b: 0.4, alpha: 0.22 * 0.55)
    private static let darkTile = tile(r: 1, g: 0.95, b: 0.9, alpha: 0.07 * 0.55)

    private static func tile(r: Double, g: Double, b: Double, alpha: Double) -> UIImage {
        let side = 200
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        var rng = SystemRandomNumberGenerator()
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let c = ctx.cgContext
            for y in 0..<side {
                for x in 0..<side {
                    let n = Double.random(in: 0...1, using: &rng)
                    c.setFillColor(UIColor(red: r, green: g, blue: b, alpha: alpha * n).cgColor)
                    c.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }
}

extension View {
    /// A screen's background: bg with grain, and the tri-stripe along the top edge (unless the screen draws its own).
    func screenBackground(stripe: Bool = true) -> some View {
        self.background {
            ZStack {
                Design.Palette.bg
                Grain()
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            if stripe { TriStripe().ignoresSafeArea(edges: .top) }
        }
    }
}
