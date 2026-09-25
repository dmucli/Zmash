import SwiftUI
import ZmashKit

// The app's top bar, what's connected, and FitOrScroll.

/// The app's four pages (D145): home and three peers, reached from the top bar rather than opened as sheets.
enum AppPage: String, CaseIterable {
    case home, history, devices, settings

    var title: String { rawValue.capitalized }
}

/// The top bar on every page (the prototype's nav): the wordmark, pill nav with the page you're on, and on the right
/// what's connected, who's riding and the theme. The tri-stripe above it comes from the screen background.
struct TopBar: View {
    let hub: DeviceHub
    let page: AppPage
    let compact: Bool
    /// Under 1000 pt (an 11" iPad upright): the pill shows dots only and the rider menu only the badge.
    var narrow = false
    let navigate: (AppPage) -> Void
    let manageRiders: () -> Void
    @Environment(Preferences.self) private var prefs
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // The full bar where it fits; otherwise (large text on an iPad) the phone's compact bar.
        ViewThatFits(in: .horizontal) {
            bar(compact: compact)
            bar(compact: true)
        }
    }

    private func bar(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            Button { navigate(.home) } label: {
                Wordmark(size: compact ? 22 : 24).fixedSize().contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Home")
            .padding(.trailing, compact ? 4 : 20)
            if !compact {
                ForEach(AppPage.allCases, id: \.self) { p in
                    NavPill(title: p.title, active: p == page) { navigate(p) }
                }
            }
            Spacer(minLength: 4)
            DevicePill(items: DeviceStatus.items(hub: hub, prefs: prefs), compact: compact || narrow, active: compact && page == .devices) { navigate(.devices) }
                .fixedSize()
            RiderMenu(compact: compact || narrow, manage: manageRiders).fixedSize()
            if compact {
                // A phone has no room for the pills: History and Settings as icons, lit on their page, and the
                // wordmark goes home.
                icon("history", .history)
                icon("settings", .settings)
            } else {
                RoundIconButton(icon: scheme == .dark ? "sun" : "moon", size: 40) {
                    withAnimation(Design.Motion.base) { prefs.toggleTheme() }
                }
                .accessibilityLabel(scheme == .dark ? "Light theme" : "Dark theme")
            }
        }
        .padding(.vertical, compact ? 12 : 20)
    }

    private func icon(_ name: String, _ target: AppPage) -> some View {
        let on = page == target
        return Button { navigate(on ? .home : target) } label: {
            Icon(name, size: 18)
                .foregroundStyle(on ? Design.Palette.invertFg : Design.Palette.fg1)
                .frame(width: 40, height: 40)
                .background {
                    if on {
                        Circle().fill(Design.Palette.invertBg)
                    } else {
                        Circle().fill(Design.Palette.surfaceGlass)
                        Circle().strokeBorder(Design.Palette.borderStrong, lineWidth: 1)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(target.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// What's connected, for the device pill on home and the ride pages.
@MainActor
enum DeviceStatus {
    static func items(hub: DeviceHub, prefs: Preferences) -> [DevicePill.Item] {
        let t = trainer(hub, prefs), c = controller(hub), h = heart(hub)
        return [.init(label: "Trainer", status: t.text, dot: t.dot), .init(label: "Controller", status: c.text, dot: c.dot),
                .init(label: "Heart", status: h.text, dot: h.dot)]
    }

    private static func trainer(_ hub: DeviceHub, _ prefs: Preferences) -> (text: String, dot: Color) {
        if hub.isDemo { return ("Demo", ok) }
        let link = hub.trainer.link
        if prefs.basicTrainer != nil { return (link == .ready ? "Basic · speed sensor" : "Basic · " + link.label.lowercased(), link == .ready ? ok : link.color) }
        guard link == .ready else { return (link.label, link.color) }
        return ("Connected · " + (hub.trainer.activeProtocol?.name ?? "FTMS"), ok)
    }

    private static func controller(_ hub: DeviceHub) -> (text: String, dot: Color) {
        if hub.isDemo { return ("Demo", ok) }
        let link = hub.ride.link
        guard link == .ready else { return (link.label, link.color) }
        guard let battery = hub.ride.batteryPercent else { return ("Connected", ok) }
        return battery < 15 ? ("Battery \(battery) %", Design.Status.caution) : ("Connected · \(battery) %", ok)
    }

    private static func heart(_ hub: DeviceHub) -> (text: String, dot: Color) {
        if let bpm = hub.heartRateBpm { return ("\(bpm) bpm", ok) }
        if let strap = hub.ble?.heartRate, strap.link != .unpaired { return (strap.link.label, strap.link.color) }
        return ("Not set up", Design.Palette.fgGhost)
    }

    private static var ok: Color { Design.Status.go }
}

/// A nav item: a pill, inverted when it's where you are.
struct NavPill: View {
    let title: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Design.Font.sans(15, weight: 500))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(active ? Design.Palette.invertFg : Design.Palette.fg2)
                .padding(.horizontal, 16).frame(minHeight: 38)
                .background { if active { Capsule().fill(Design.Palette.invertBg) } }
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// What's connected, as dots in one glass pill; opens Devices.
struct DevicePill: View {
    struct Item {
        let label: String
        let status: String
        let dot: Color
    }

    let items: [Item]
    let compact: Bool
    /// On the Devices page, on a phone (where there are no pills to show it).
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ForEach(items, id: \.label) { item in
                    HStack(spacing: 6) {
                        Circle().fill(item.dot).frame(width: 7, height: 7)
                        if !compact { Text(item.label).font(Design.Font.sans(13, weight: 500)) }
                    }
                }
            }
            .foregroundStyle(Design.Palette.fg2)
            .padding(.horizontal, 14).frame(minHeight: 40)
            .background {
                Capsule().fill(Design.Palette.surfaceGlass)
                Capsule().strokeBorder(active ? Design.Palette.fg1 : Design.Palette.borderStrong, lineWidth: active ? 2 : 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.map { "\($0.label): \($0.status)" }.joined(separator: ", "))
        .accessibilityHint("Opens Devices")
    }
}

/// Shown as it is when it fits the height it's given, and in a scroll view when it doesn't: home's columns, which
/// fill the screen on an iPad without the page scrolling (D144).
struct FitOrScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollBounceBehavior(.basedOnSize)
        }
    }
}
