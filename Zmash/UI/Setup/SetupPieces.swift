import SwiftUI
import ZmashKit

// The home screen's parts: header buttons, device cards, chooser rows and the Start bar.

/// History / Settings: icon and word on a wide screen, icon only when space is tight.
struct HeaderButton: View {
    let icon: String
    let title: String
    let showsTitle: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Icon(icon, size: 20)
                if showsTitle { Text(title).font(Design.Font.label) }
            }
            .foregroundStyle(Design.Palette.primary)
            .padding(.horizontal, showsTitle ? 16 : 12)
            .frame(minWidth: 44, minHeight: 44)
            .background(Capsule().fill(Design.Palette.surface))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// One device: what it is, whether it's there, and a way into Devices.
struct DeviceCard: View {
    let icon: String
    let title: String
    let status: String
    let dot: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Icon(icon, size: 22)
                    .foregroundStyle(Design.Palette.primary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Design.Palette.background))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                    HStack(spacing: 6) {
                        Circle().fill(dot).frame(width: 7, height: 7)
                        Text(status).font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                Icon("chevron-right", size: 16).foregroundStyle(Design.Palette.secondary)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(RoundedRectangle(cornerRadius: 16).fill(Design.Palette.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Devices")
    }
}

/// The chosen workout or route, with a way to change it.
struct ChooserRow: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Text("Change").font(Design.Font.small).foregroundStyle(Design.Palette.secondary)
                Icon("chevron-right", size: 16).foregroundStyle(Design.Palette.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Design.Palette.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            Rectangle().fill(Design.Palette.hairline).frame(height: 1)
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Design.Palette.primary)
                    Text(detail).font(Design.Font.small.monospacedDigit()).foregroundStyle(Design.Palette.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 12)
                if ready {
                    PrimaryButton(title: "Start", action: start)
                        .frame(width: compact ? 140 : 240)
                        .keyboardShortcut(.return, modifiers: [])
                } else {
                    PrimaryButton(title: "Connect trainer", action: connect)
                        .frame(width: compact ? 180 : 240)
                }
            }
            .frame(maxWidth: Design.Space.column)
            .padding(.horizontal, compact ? Design.Space.gutter : 40)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
        .background(Design.Palette.background.ignoresSafeArea(edges: .bottom))
    }
}
