import Foundation
import Observation
import SwiftUI

/// The workouts and routes a rider keeps at hand (D148): ♡ on a row or a preview, listed under Favourites.
/// Per rider, in UserDefaults (so the backup, which copies them all, keeps them). Routes are kept by their whole-route
/// id, not a part of one.
@MainActor @Observable
final class Favourites {
    static let shared = Favourites()

    enum Kind: String { case workouts, routes }

    private let defaults: UserDefaults
    /// Read per rider and kind, then kept.
    private var cache: [String: [String]] = [:]

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(_ kind: Kind, rider: String) -> String { "favourites.\(kind.rawValue).\(rider)" }

    /// Newest first.
    func ids(_ kind: Kind, rider: String = Riders.currentID) -> [String] {
        let k = key(kind, rider: rider)
        if let hit = cache[k] { return hit }
        let list = defaults.stringArray(forKey: k) ?? []
        cache[k] = list
        return list
    }

    func contains(_ id: String, _ kind: Kind, rider: String = Riders.currentID) -> Bool {
        ids(kind, rider: rider).contains(Self.normalised(id, kind))
    }

    func toggle(_ id: String, _ kind: Kind, rider: String = Riders.currentID) {
        let id = Self.normalised(id, kind)
        var list = ids(kind, rider: rider)
        if let i = list.firstIndex(of: id) { list.remove(at: i) } else { list.insert(id, at: 0) }
        let k = key(kind, rider: rider)
        cache[k] = list
        defaults.set(list, forKey: k)
    }

    /// Settings restored from a backup: read them again.
    func reload() { cache = [:] }

    /// A route is kept whole: a part of a stage favourites the stage.
    private static func normalised(_ id: String, _ kind: Kind) -> String {
        kind == .routes ? RouteStore.split(id).base : id
    }
}

/// ♡: outlined, filled vermilion once it's a favourite.
struct FavouriteButton: View {
    let on: Bool
    var size: CGFloat = 20
    let toggle: () -> Void

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { toggle() }
        } label: {
            ZStack {
                if on {
                    HeartShape().fill(Design.Accent.vermilion)
                } else {
                    HeartShape().stroke(Design.Palette.fg3, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                }
            }
            .frame(width: size, height: size * 0.9)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Remove from favourites" : "Add to favourites")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A heart, drawn so it can be filled (the Lucide one is an outline).
struct HeartShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.32),
                   control1: CGPoint(x: r.minX + w * 0.3, y: r.minY + h * 0.78),
                   control2: CGPoint(x: r.minX, y: r.minY + h * 0.55))
        p.addArc(center: CGPoint(x: r.minX + w * 0.25, y: r.minY + h * 0.28), radius: w * 0.25,
                 startAngle: .degrees(170), endAngle: .degrees(-10), clockwise: false)
        p.addArc(center: CGPoint(x: r.minX + w * 0.75, y: r.minY + h * 0.28), radius: w * 0.25,
                 startAngle: .degrees(190), endAngle: .degrees(10), clockwise: false)
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                   control1: CGPoint(x: r.maxX, y: r.minY + h * 0.55),
                   control2: CGPoint(x: r.maxX - w * 0.3, y: r.minY + h * 0.78))
        p.closeSubpath()
        return p
    }
}
