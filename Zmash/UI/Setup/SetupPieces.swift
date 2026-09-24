import SwiftUI
import ZmashKit

// The home screen's parts: the top bar, the ride-type cards, list rows and the Start bar.

/// The top bar (the prototype's nav): the wordmark, pill nav, and on the right what's connected, who's riding and
/// the theme. The tri-stripe above it comes from the screen background.
struct HomeTopBar: View {
    let devices: [DevicePill.Item]
    let compact: Bool
    /// Under 1000 pt (an 11" iPad upright): the pill shows dots only and the rider menu only the badge.
    var narrow = false
    let openHistory: () -> Void
    let openDevices: () -> Void
    let openSettings: () -> Void
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
            Wordmark(size: compact ? 22 : 24)
                .fixedSize()
                .padding(.trailing, compact ? 4 : 20)
            if !compact {
                NavPill(title: "Home", active: true) {}
                NavPill(title: "History", action: openHistory)
                NavPill(title: "Devices", action: openDevices)
                NavPill(title: "Settings", action: openSettings)
            }
            Spacer(minLength: 4)
            DevicePill(items: devices, compact: compact || narrow, action: openDevices).fixedSize()
            RiderMenu(compact: compact || narrow, manage: manageRiders).fixedSize()
            if compact {
                RoundIconButton(icon: "history", size: 40, action: openHistory).accessibilityLabel("History")
                RoundIconButton(icon: "settings", size: 40, action: openSettings).accessibilityLabel("Settings")
            } else {
                RoundIconButton(icon: scheme == .dark ? "sun" : "moon", size: 40) {
                    withAnimation(Design.Motion.base) { prefs.toggleTheme() }
                }
                .accessibilityLabel(scheme == .dark ? "Light theme" : "Dark theme")
            }
        }
        .padding(.vertical, compact ? 12 : 20)
    }
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
                Capsule().strokeBorder(Design.Palette.borderStrong, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.map { "\($0.label): \($0.status)" }.joined(separator: ", "))
        .accessibilityHint("Opens Devices")
    }
}

/// One way to ride (free, workout, route) as a card: what it is, what's set up for it, and its shape (D144).
struct ModeCard<Shape: View>: View {
    let title: String
    let detail: String
    let selected: Bool
    var compact = false
    let action: () -> Void
    @ViewBuilder var shape: Shape

    var body: some View {
        Button(action: action) {
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).textStyle(.h2, size: 17).foregroundStyle(Design.Palette.fg1)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        shape.frame(maxWidth: .infinity).frame(height: 22)
                    }
                } else {
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).textStyle(.h2, size: 22).foregroundStyle(Design.Palette.fg1)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            Text(detail).font(Design.Font.sans(14)).foregroundStyle(Design.Palette.fg3).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                        shape.frame(minWidth: 60, maxWidth: 130).frame(height: 36)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .card(padding: compact ? 14 : 18, selected: selected)
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.lg))
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One thing to choose in home's lists (D144): a title, a line under it, and its shape on the right.
struct BrowserRow<Shape: View>: View {
    let title: String
    var subtitle: String = ""
    var selected = false
    /// The shape's width; nil sizes it to fit (a tag).
    var shapeWidth: CGFloat? = 84
    let action: () -> Void
    @ViewBuilder var shape: Shape

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Design.Font.label).foregroundStyle(Design.Palette.fg1).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(Design.Font.mono(12)).foregroundStyle(Design.Palette.fg3)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                if let shapeWidth {
                    shape.frame(width: shapeWidth, height: 26)
                } else {
                    shape.fixedSize()
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background {
                let shape = RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous)
                if selected {
                    shape.fill(Design.Palette.surfaceSunk)
                    shape.strokeBorder(Design.Accent.vermilion, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.md))
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

/// Pinned to the bottom: what's about to start, and Start. Without a trainer it says so and opens Devices.
struct StartBar: View {
    let title: String
    let detail: String
    let ready: Bool
    let compact: Bool
    let start: () -> Void
    let connect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Design.Palette.border).frame(height: 1)
            HStack(spacing: compact ? 12 : 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Design.Font.sans(17, weight: 700)).foregroundStyle(Design.Palette.fg1)
                    Text(detail).font(Design.Font.mono(12)).foregroundStyle(Design.Palette.fg3)
                }
                .lineLimit(1)
                Spacer(minLength: 12)
                if ready {
                    PrimaryButton(title: "Start ride", icon: "play", action: start)
                        .frame(width: compact ? 150 : 220)
                        .keyboardShortcut(.return, modifiers: [])
                } else {
                    PrimaryButton(title: "Connect trainer", icon: "bluetooth", action: connect)
                        .frame(width: compact ? 190 : 240)
                }
            }
            .frame(maxWidth: Design.Space.column)
            .padding(.horizontal, compact ? Design.Space.gutter : Design.Space.screen)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
        .background(Design.Palette.bg.opacity(0.94).ignoresSafeArea(edges: .bottom))
        .background(.ultraThinMaterial)
    }
}
