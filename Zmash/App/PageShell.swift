import SwiftUI

/// History, Devices and Settings as pages beside home (D145), not sheets over it: the same top bar, the page's name,
/// and the page in its own navigation stack, so a ride or a setting still opens inside it with a way back.
struct PageShell<Content: View>: View {
    let hub: DeviceHub
    let page: AppPage
    let navigate: (AppPage) -> Void
    let manageRiders: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let compact = geo.size.width < 700
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        TopBar(hub: hub, page: page, compact: compact, narrow: geo.size.width < 1000,
                               navigate: navigate, manageRiders: manageRiders)
                        Text(page.title)
                            .textStyle(.display, size: compact ? 30 : 36)
                            .foregroundStyle(Design.Palette.fg1)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, 4)
                    }
                    .frame(maxWidth: Design.Space.column + 140, alignment: .leading)
                    .padding(.horizontal, compact ? Design.Space.gutter : Design.Space.screen)
                    .padding(.top, 5)
                    .frame(maxWidth: .infinity)
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .screenBackground()
            // The page's own bar only once something is opened inside it (a ride, a setting), for the way back.
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
