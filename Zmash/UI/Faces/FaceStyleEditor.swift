import SwiftUI
import ZmashKit

/// Customises one face: palette, main number, secondary numbers and font (Phase 11, D109, D110).
/// The gallery behind it redraws as you change things.
struct FaceStyleEditor: View {
    let face: FaceID
    @Environment(Preferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    /// Tried to take the second-to-last face out of rotation.
    @State private var rotationRefused = false

    private var style: FaceStyle { prefs.style(face) }

    /// Whether the D-pad's face switch mid-ride stops at this face (moved here from the gallery, D146).
    private var inRotation: Binding<Bool> {
        Binding(
            get: { !prefs.faceRotationExcluded.contains(face) },
            set: { on in
                rotationRefused = false
                if on { prefs.faceRotationExcluded.remove(face) }
                // Keep at least two faces to switch between.
                else if prefs.faceRotation.count > 2 { prefs.faceRotationExcluded.insert(face) }
                else { rotationRefused = true }
            })
    }

    var body: some View {
        @Bindable var prefs = prefs
        NavigationStack {
            Form {
                // The same sections, in the same order, for every face (D110); Classic's come from its display settings.
                if face == .classic {
                    Section {
                        Toggle("Colour by grade", isOn: $prefs.display.gradeColor)
                        Toggle("Wind background", isOn: $prefs.windBackground)
                    } header: { SectionHeader("Colour") }
                } else {
                    Section {
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
                    } header: { SectionHeader("Palette") }
                }

                Section {
                    if face == .classic {
                        Picker("Main number", selection: $prefs.display.hero) {
                            ForEach(DisplayMetric.allCases) { Text($0.label).tag($0) }
                        }
                    } else {
                        Picker("Main number", selection: Binding(get: { style.hero ?? prefs.mainNumber }, set: { set(hero: $0) })) {
                            ForEach(FaceMetric.allCases.filter { $0 != .empty }) { m in Text(m.name).tag(m) }
                        }
                    }
                } header: {
                    SectionHeader("Main number")
                } footer: {
                    Text("The big one. Settings' main number (\(prefs.mainNumber.name.lowercased())) sets it on every face; pick another here for \(face.name) alone. Mid-ride, tap it for the next one.")
                }

                if face == .classic {
                    Section {
                        ForEach(0..<4, id: \.self) { i in
                            Picker(Self.classicSlots[i], selection: classicSlot(i)) {
                                ForEach(DisplayMetric.allCases) { Text($0.label).tag($0) }
                            }
                        }
                    } header: { SectionHeader("Numbers") }
                } else if !FaceStyle.defaultSlots(face).isEmpty {
                    Section {
                        ForEach(style.slotItems(face)) { slot in
                            Picker("Slot \(slot.id + 1)", selection: Binding(
                                get: { slot.metric },
                                set: { set(slot: slot.id, to: $0) })) {
                                    ForEach(FaceMetric.allCases) { m in Text(m.name).tag(m) }
                                }
                        }
                    } header: {
                        SectionHeader("Numbers")
                    } footer: {
                        Text(slotsFooter)
                    }
                }

                Section {
                    if face == .classic {
                        Picker("Font", selection: $prefs.display.style) {
                            Text("Bib (Archivo condensed)").tag(NumberStyle.bib)
                            Text("Rounded").tag(NumberStyle.rounded)
                            Text("Standard").tag(NumberStyle.standard)
                            Text("Mono").tag(NumberStyle.mono)
                        }
                        Picker("Weight", selection: $prefs.display.weight) {
                            Text("Regular").tag(NumberWeight.regular)
                            Text("Medium").tag(NumberWeight.medium)
                            Text("Semibold").tag(NumberWeight.semibold)
                            Text("Bold").tag(NumberWeight.bold)
                        }
                        Picker("Main number size", selection: $prefs.display.heroScale) {
                            Text("Small").tag(0.8)
                            Text("Medium").tag(1.0)
                            Text("Large").tag(1.2)
                        }
                    } else {
                        Picker("Font", selection: Binding(get: { style.font }, set: { set(font: $0) })) {
                            Text("As designed").tag(FaceFont.Family?.none)
                            ForEach(FaceFont.Family.choices, id: \.self) { f in
                                Text(f.title).font(FaceFont.font(f, 17, weight: 500)).tag(FaceFont.Family?.some(f))
                            }
                        }
                    }
                } header: { SectionHeader("Font") }

                Section {
                    Toggle("When switching faces mid-ride", isOn: inRotation)
                } header: {
                    SectionHeader("Rotation")
                } footer: {
                    Text(rotationRefused ? "Keep at least two faces to switch between."
                                         : "Off, and the controller's face switch skips \(face.name).")
                }

                Section {
                    Picker("Motion", selection: $prefs.faceMotion) {
                        Text("Full").tag(FaceMotion.full)
                        Text("Calm").tag(FaceMotion.calm)
                    }
                    Toggle("Course profile along the bottom", isOn: $prefs.courseStrip)
                } header: {
                    SectionHeader("For all faces")
                }

                Section {
                    Button("Reset \(face.name)", role: .destructive) {
                        if face == .classic { prefs.display = .standard } else { prefs.resetStyle(face) }
                    }
                }
            }
            .zmashForm()
            .navigationTitle("Customise \(face.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private static let classicSlots = ["Top left", "Bottom left", "Top right", "Bottom right"]

    private func classicSlot(_ i: Int) -> Binding<DisplayMetric> {
        Binding(get: { prefs.display.slot(i) }, set: { value in
            var slots = (0..<4).map { prefs.display.slot($0) }
            slots[i] = value
            prefs.display.slots = slots
        })
    }

    private func set(hero: FaceMetric) {
        var s = style
        // Settings' main number is the default: choosing it follows Settings again (D159).
        s.hero = hero == prefs.mainNumber ? nil : hero
        prefs.setStyle(s, for: face)
    }

    private func set(font: FaceFont.Family?) {
        var s = style
        s.font = font
        prefs.setStyle(s, for: face)
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
