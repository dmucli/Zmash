import SwiftUI
import ZmashKit

// The four ride pages (D148) share one shape: pushed from home with the system bar (‹ Home, swipe back), a Choose
// card on the left (tabs, a line about the tab, the list or settings) and a Preview card on the right (the ride as
// chosen, and Start). On a phone they stack, and Start is pinned at the bottom.

/// What a ride page needs from the app: the devices (is there a trainer?), how to start, and the way to Devices.
struct RideContext {
    let hub: DeviceHub
    let start: (SessionPlan) -> Void
    let openDevices: () -> Void

    @MainActor var trainerReady: Bool { hub.trainer.link == .ready }
}

extension EnvironmentValues {
    /// A ride page stacked on a phone, or with large text: lists take a fixed height inside the scrolling page.
    @Entry var ridePageStacked = false
}

/// What the Start footer says and does. The heart, when there is one, keeps the ride under Favourites.
struct StartInfo {
    let title: String
    let detail: String
    let start: () -> Void
    var favourite: (on: Bool, toggle: () -> Void)? = nil
}

struct RidePage<Choose: View, Preview: View>: View {
    let title: String
    let context: RideContext
    /// nil: no footer (the plan page starts from the plan itself).
    var start: StartInfo?
    @ViewBuilder var choose: Choose
    @ViewBuilder var preview: Preview
    @Environment(Preferences.self) private var prefs
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geo in
            let stacked = geo.size.width < 700 || typeSize.isAccessibilitySize
            Group {
                if stacked {
                    ScrollView {
                        VStack(spacing: 14) {
                            choose.card(padding: 0)
                            preview.frame(minHeight: 320).card(padding: 0)
                        }
                        .padding(.horizontal, Design.Space.gutter)
                        .padding(.vertical, 12)
                    }
                    .environment(\.ridePageStacked, true)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if let start {
                            VStack(spacing: 0) {
                                Rectangle().fill(Design.Palette.border).frame(height: 1)
                                footer(start, compact: true).padding(.horizontal, Design.Space.gutter)
                            }
                            .background(Design.Palette.bg.opacity(0.94).ignoresSafeArea(edges: .bottom))
                            .background(.ultraThinMaterial)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        choose
                            .frame(width: min(440, max(380, geo.size.width * 0.36)))
                            .frame(maxHeight: .infinity, alignment: .top)
                            .card(padding: 0)
                        VStack(spacing: 0) {
                            preview.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            if let start {
                                Rectangle().fill(Design.Palette.border).frame(height: 1)
                                footer(start, compact: false).padding(.horizontal, 22)
                            }
                        }
                        .card(padding: 0)
                    }
                    .frame(maxWidth: Design.Space.column + 140)
                    .padding(.horizontal, Design.Space.screen)
                    .padding(.top, 8).padding(.bottom, 16)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .screenBackground(stripe: false)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                DevicePill(items: DeviceStatus.items(hub: context.hub, prefs: prefs), compact: true, action: context.openDevices)
                    .fixedSize()
            }
        }
    }

    /// The ride as chosen, and Start (or Connect trainer without one).
    private func footer(_ info: StartInfo, compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            if let fav = info.favourite {
                FavouriteButton(on: fav.on, toggle: fav.toggle).padding(.leading, -12)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title).font(Design.Font.sans(17, weight: 700)).foregroundStyle(Design.Palette.fg1)
                Text(context.trainerReady ? info.detail : "Connect a trainer to start")
                    .font(Design.Font.mono(12)).foregroundStyle(Design.Palette.fg3)
            }
            .lineLimit(1)
            Spacer(minLength: 12)
            if context.trainerReady {
                PrimaryButton(title: "Start ride", icon: "play", action: info.start)
                    .frame(width: compact ? 150 : 210)
                    .keyboardShortcut(.return, modifiers: [])
            } else {
                PrimaryButton(title: "Connect trainer", icon: "bluetooth", action: context.openDevices)
                    .frame(width: compact ? 190 : 230)
            }
        }
        .padding(.vertical, 14)
    }
}

// MARK: - The Choose card's parts

/// The Choose card: its tabs, a line about the tab, an optional "+" menu, then the content.
struct ChooseColumn<Tab: Hashable, Menu: View, Content: View>: View {
    let tabs: [(Tab, String)]
    @Binding var tab: Tab
    let hint: String
    /// The "+" menu's accessibility label; nil: no menu.
    var addLabel: String? = nil
    @ViewBuilder var menu: Menu
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Segmented(options: tabs, selection: $tab)
                if let addLabel {
                    SwiftUI.Menu { menu } label: {
                        Icon("plus", size: 18).foregroundStyle(Design.Palette.fg1)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Design.Palette.surfaceSunk))
                            .contentShape(Circle())
                    }
                    .accessibilityLabel(addLabel)
                }
            }
            .padding(.horizontal, 14).padding(.top, 14)
            Text(hint).font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .contentTransition(.opacity)
            content.frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

extension ChooseColumn where Menu == EmptyView {
    init(tabs: [(Tab, String)], tab: Binding<Tab>, hint: String, @ViewBuilder content: () -> Content) {
        self.init(tabs: tabs, tab: tab, hint: hint, addLabel: nil, menu: { EmptyView() }, content: content)
    }
}

/// A list in the Choose card: scrolls inside the card, and opens on what's chosen.
struct ChooseList<Content: View>: View {
    /// The row to show when the list opens or its content changes.
    var scrollTo: String?
    /// Changes when the list shows something else (a tab, a race), to scroll again.
    var showing: String = ""
    @ViewBuilder var content: Content
    @Environment(\.ridePageStacked) private var stacked

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) { content }
                    .padding(.horizontal, 8).padding(.bottom, 10)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear { if let scrollTo { proxy.scrollTo(scrollTo, anchor: .center) } }
            .onChange(of: showing) {
                guard let scrollTo else { return }
                Task { @MainActor in proxy.scrollTo(scrollTo, anchor: .center) }
            }
        }
        .frame(height: stacked ? 380 : nil)
    }
}

/// A group's name in a list.
struct ChooseSection: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title).monoLabel().foregroundStyle(Design.Palette.fg3)
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A word in an empty list about how to fill it.
struct ChooseHint: View {
    let text: String

    var body: some View {
        Text(text).font(Design.Font.small).foregroundStyle(Design.Palette.fg3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sunkTile()
            .padding(.top, 8)
    }
}

/// One thing to choose: a title, a line under it, its shape, and ♡ when it can be a favourite.
struct ChooseRow<Shape: View>: View {
    let title: String
    var subtitle: String = ""
    var selected = false
    /// The shape's width; nil sizes it to fit (a tag).
    var shapeWidth: CGFloat? = 84
    var favourite: (on: Bool, toggle: () -> Void)? = nil
    let action: () -> Void
    @ViewBuilder var shape: Shape

    var body: some View {
        HStack(spacing: 0) {
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
                .padding(.leading, 12).padding(.trailing, favourite == nil ? 12 : 2).padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
            if let favourite {
                FavouriteButton(on: favourite.on, size: 16, toggle: favourite.toggle)
            }
        }
        .background {
            let shape = RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous)
            if selected {
                shape.fill(Design.Palette.surfaceSunk)
                shape.strokeBorder(Design.Accent.vermilion, lineWidth: 2)
            }
        }
    }
}

/// A plan or a campaign in a preview, with a way back to the chosen ride.
struct Closable<Content: View>: View {
    let close: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .topTrailing) {
                RoundIconButton(icon: "x", size: 40) { withAnimation(Design.Motion.base) { close() } }
                    .accessibilityLabel("Back to the ride")
                    .padding(14)
            }
    }
}
