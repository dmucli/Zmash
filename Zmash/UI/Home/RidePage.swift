import SwiftUI
import ZmashKit

// The ride pages (D149), after the design system's picker: under home's top bar, one row (‹ back, the pill tab
// switcher, filter chips, +), a grid of big cards where the card is the preview, and the inverted selection bar at the
// bottom with the choice and Start.

/// What a ride page needs from the app: the devices (is there a trainer?), how to start, Devices, and the way home.
struct RideContext {
    let hub: DeviceHub
    let start: (SessionPlan) -> Void
    let openDevices: () -> Void
    let back: () -> Void

    @MainActor var trainerReady: Bool { hub.trainer.link == .ready }
}

/// What the selection bar shows: the ride, ♡, the one option that belongs to it, and Start.
struct Selection {
    let title: String
    let meta: String
    var favourite: (on: Bool, toggle: () -> Void)? = nil
    var option: AnyView? = nil
    let start: () -> Void
}

struct RidePage<Tabs: View, Tools: View, Content: View>: View {
    let context: RideContext
    /// nil: no bar (the plan page starts from the plan itself).
    var selection: Selection?
    var compact = false
    /// Beside ‹: the page's tabs (or what stands for them).
    @ViewBuilder var tabs: Tabs
    /// On the right, or on a second row on a phone: filter chips and +.
    @ViewBuilder var tools: Tools
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) { back; tabs }
                        HStack(spacing: 8) { tools }
                    }
                } else {
                    HStack(spacing: 12) { back; tabs; tools }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, compact ? 12 : 18)
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if let selection {
                SelectionBar(selection: selection, context: context, compact: compact)
                    .padding(.top, compact ? 10 : 14)
            }
        }
    }

    private var back: some View {
        RoundIconButton(icon: "chevron-left", size: 44, action: context.back)
            .accessibilityLabel("Back to home")
            .keyboardShortcut(.escape, modifiers: [])
    }
}

// MARK: - Header

/// The prototype's tab switcher: a sunk capsule, the chosen tab raised on the surface.
struct PickerTabs<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var tab: Tab
    var compact = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.0) { value, title in
                let on = value == tab
                Button {
                    withAnimation(Design.Motion.fast) { tab = value }
                } label: {
                    Text(title).font(Design.Font.sans(compact ? 14 : 15, weight: 600)).lineLimit(1).minimumScaleFactor(0.6)
                        .foregroundStyle(on ? Design.Palette.fg1 : Design.Palette.fg3)
                        .padding(.horizontal, compact ? 10 : 18).frame(minHeight: 38)
                        .background {
                            if on {
                                Capsule().fill(Design.Palette.surface)
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Design.Palette.surfaceSunk))
        .fixedSize(horizontal: !compact, vertical: true)
    }
}

/// Filter chips, in one row that scrolls when it doesn't fit.
struct FilterChips<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options, id: \.0) { value, title in
                    Chip(title: title, selected: value == selection) {
                        withAnimation(Design.Motion.fast) { selection = value }
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// "+": what a page can add.
struct AddMenu<Items: View>: View {
    let label: String
    @ViewBuilder var items: Items

    var body: some View {
        Menu { items } label: {
            Icon("plus", size: 18).foregroundStyle(Design.Palette.fg1)
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(Design.Palette.borderStrong, lineWidth: 1))
                .contentShape(Circle())
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Grid

/// The picker's grid: rows of big cards, scrolling inside the page, opening on the chosen one.
struct PickerGrid<Content: View>: View {
    let columns: Int
    let rowHeight: CGFloat
    /// The card to show when the grid opens or shows something else.
    var scrollTo: String?
    /// Changes when the grid shows something else (a tab, a filter, a race), to scroll again.
    var showing: String = ""
    @ViewBuilder var content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: max(columns, 1)), spacing: 14) {
                    content.frame(height: rowHeight)
                }
                .padding(.bottom, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear { if let scrollTo { proxy.scrollTo(scrollTo, anchor: .center) } }
            .onChange(of: showing) {
                guard let scrollTo else { return }
                Task { @MainActor in proxy.scrollTo(scrollTo, anchor: .center) }
            }
        }
    }
}

/// A card in the picker: the name, a mono line of figures, and the ride's shape filling the bottom; ♡ in the corner
/// (where the prototype has its bib), a vermilion ring when chosen. The hero variant is the hatch, in bone.
struct PickerCard<Shape: View>: View {
    let title: String
    let meta: String
    var selected = false
    var hero = false
    /// A profile drawn edge to edge along the bottom, as the prototype's route cards.
    var fullBleed = false
    var tag: String? = nil
    var favourite: (on: Bool, toggle: () -> Void)? = nil
    let action: () -> Void
    @ViewBuilder var shape: Shape
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(Design.Font.sans(19, weight: 700))
                            .foregroundStyle(hero ? Design.Palette.fgOnHero : Design.Palette.fg1)
                            .lineLimit(2).minimumScaleFactor(0.8)
                        Text(meta).font(Design.Font.mono(12))
                            .foregroundStyle(hero ? Design.Palette.fgOnHero2 : Design.Palette.fg3)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        if let tag {
                            Tag(title: tag, fill: Design.Accent.vermilion).padding(.top, 4)
                        }
                    }
                    .padding(.trailing, favourite == nil ? 0 : 34)
                    Spacer(minLength: 0)
                    shape
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40, maxHeight: fullBleed ? 90 : 96)
                        .padding(.horizontal, fullBleed ? -20 : 0)
                }
                .padding(.top, 18).padding(.horizontal, 20).padding(.bottom, fullBleed ? 0 : 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(CardBackground(selected: false, hero: hero))
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.lg, style: .continuous))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: Design.Radius.lg, style: .continuous)
                            .strokeBorder(Design.Accent.vermilion, lineWidth: 2)
                    }
                }
                .environment(\.onHero, hero)
                .contentShape(RoundedRectangle(cornerRadius: Design.Radius.lg))
            }
            .buttonStyle(PressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
            if let favourite {
                FavouriteButton(on: favourite.on, size: 18, toggle: favourite.toggle)
                    .environment(\.colorScheme, hero ? .dark : scheme)
                    .padding(4)
            }
        }
    }
}

/// A word in an empty grid about how to fill it.
struct PickerHint: View {
    let text: String

    var body: some View {
        Text(text).font(Design.Font.body).foregroundStyle(Design.Palette.fg3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 520, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Design.Radius.lg, style: .continuous)
                .strokeBorder(Design.Palette.border, style: StrokeStyle(lineWidth: 1, dash: [6, 5])))
    }
}

// MARK: - Selection bar

/// The prototype's inverted bar: what's chosen, its figures, ♡, its one option, and Start.
struct SelectionBar: View {
    let selection: Selection
    let context: RideContext
    var compact = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let flipped: ColorScheme = scheme == .dark ? .light : .dark
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                words
                Spacer(minLength: 8)
                if let option = selection.option { option.fixedSize() }
                startButton
            }
            VStack(alignment: .leading, spacing: 12) {
                words
                if let option = selection.option { option }
                HStack { Spacer(minLength: 0); startButton }
            }
        }
        .environment(\.colorScheme, flipped)
        .padding(.vertical, 12).padding(.leading, selection.favourite == nil ? 22 : 8).padding(.trailing, 12)
        .background(RoundedRectangle(cornerRadius: Design.Radius.lg, style: .continuous).fill(Design.Palette.invertBg))
    }

    private var words: some View {
        HStack(spacing: 6) {
            if let fav = selection.favourite {
                FavouriteButton(on: fav.on, toggle: fav.toggle)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.title).font(Design.Font.sans(17, weight: 700)).foregroundStyle(Design.Palette.fg1)
                Text(context.trainerReady ? selection.meta : "Connect a trainer to start")
                    .font(Design.Font.mono(12)).foregroundStyle(Design.Palette.fg2)
            }
            .lineLimit(1)
        }
    }

    @ViewBuilder private var startButton: some View {
        if context.trainerReady {
            PillButton(title: "Start ride", icon: "play", style: .primary, action: selection.start)
                .fixedSize()
                .keyboardShortcut(.return, modifiers: [])
        } else {
            PillButton(title: "Connect trainer", icon: "bluetooth", style: .primary, action: context.openDevices)
                .fixedSize()
        }
    }
}
