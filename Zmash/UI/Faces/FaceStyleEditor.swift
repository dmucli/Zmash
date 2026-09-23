import SwiftUI
import ZmashKit

/// Customises one face: its palette and what sits in its secondary slots (roadmap Phase 11).
/// The gallery behind it redraws as you change things.
struct FaceStyleEditor: View {
    let face: FaceID
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var style: FaceStyle { prefs.style(face) }

    var body: some View {
        NavigationStack {
            Form {
                if face == .classic {
                    Section {
                        NavigationLink("Numbers, typeface and size") { DisplaySettingsView() }
                    } footer: {
                        Text("Classic has always been the customisable one: choose every number, the typeface and its size.")
                    }
                } else {
                    Section("Palette") {
                        ForEach(FacePalettes.options(for: face)) { palette in
                            Button { set(palette: palette.id) } label: {
                                HStack(spacing: 14) {
                                    Swatch(palette: palette, dark: scheme == .dark)
                                    Text(palette.name).font(Design.Font.label).foregroundStyle(Design.Palette.primary)
                                    Spacer()
                                    if style.paletteID == palette.id {
                                        Icon("check", size: 18).foregroundStyle(Design.Palette.primary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !FaceStyle.defaultSlots(face).isEmpty {
                    Section {
                        ForEach(Array(style.slots(face).enumerated()), id: \.offset) { i, metric in
                            Picker("Slot \(i + 1)", selection: Binding(
                                get: { metric },
                                set: { set(slot: i, to: $0) })) {
                                    ForEach(FaceMetric.allCases) { m in Text(m.name).tag(m) }
                                }
                        }
                    } header: {
                        Text("Numbers")
                    } footer: {
                        Text(slotsFooter)
                    }
                    }

                    Section {
                        Button("Reset \(face.name)", role: .destructive) { prefs.resetStyle(face) }
                    }
                }
            }
            .navigationTitle("Customise \(face.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private var slotsFooter: String {
        switch face {
        case .paper: "The row under the big numbers."
        case .aura: "The five quiet numbers along the bottom."
        case .night: "The lit line in the bottom-right corner."
        case .horizon: "The line along the ground."
        case .kinetic: "The row under the rule."
        default: ""
        }
    }

    private func set(palette: String) {
        var s = style
        s.paletteID = palette
        prefs.setStyle(s, for: face)
    }

    private func set(slot: Int, to metric: FaceMetric) {
        var s = style
        var slots = s.slots(face)
        guard slot < slots.count else { return }
        slots[slot] = metric
        s.slots = slots
        prefs.setStyle(s, for: face)
    }
}

/// Background, ink and accent as one small tile.
private struct Swatch: View {
    let palette: FacePalette
    let dark: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(palette.bg(dark: dark))
            HStack(spacing: 4) {
                Circle().fill(palette.ink(dark: dark)).frame(width: 10, height: 10)
                Circle().fill(palette.accent(dark: dark)).frame(width: 10, height: 10)
            }
        }
        .frame(width: 52, height: 34)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Design.Palette.hairline, lineWidth: 1))
    }
}
