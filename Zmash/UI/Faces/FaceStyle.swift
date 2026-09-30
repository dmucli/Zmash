import SwiftUI
import ZmashKit

// MARK: - Metrics

/// A number that can sit in one of a face's secondary slots (roadmap Phase 11).
enum FaceMetric: String, CaseIterable, Codable, Identifiable, Sendable {
    case speed, power, power3, cadence, heartRate, elapsed, remaining, distance, climbed, energy
    case grade, gear, altitude, toGo, ftpPercent, empty

    var id: String { rawValue }

    /// Name in the picker.
    var name: String {
        switch self {
        case .speed: "Speed"
        case .power: "Power"
        case .power3: "Power, 3 s"
        case .cadence: "Cadence"
        case .heartRate: "Heart rate"
        case .elapsed: "Elapsed"
        case .remaining: "Remaining"
        case .distance: "Distance"
        case .climbed: "Climbed"
        case .energy: "Energy"
        case .grade: "Grade"
        case .gear: "Gear"
        case .altitude: "Altitude"
        case .toGo: "Distance to go"
        case .ftpPercent: "% of FTP"
        case .empty: "Nothing"
        }
    }

    func value(_ d: FaceData) -> String {
        switch self {
        case .speed: d.speed0
        case .power: d.powerI
        case .power3: d.power3Text
        case .cadence: d.cadenceText
        case .heartRate: d.hrText
        case .elapsed: d.elapsedText
        case .remaining: d.remainingText
        case .distance: d.distText
        case .climbed: d.climbedText
        case .energy: d.kcalText
        case .grade: d.gradeText
        case .gear: d.gearText
        case .altitude: d.altitudeM.map { String(Int(d.units.elevation($0).rounded())) } ?? "—"
        case .toGo: d.toGoM.map { String(format: "%.1f", d.units.distance($0)) } ?? "—"
        case .ftpPercent: "\(Int((d.shownPowerW / max(d.ftp, 1) * 100).rounded()))%"
        case .empty: ""
        }
    }

    /// Label under the value on faces that name their numbers (Paper, Aura, Kinetic).
    func short(_ d: FaceData) -> String {
        switch self {
        case .speed: d.speedUnit
        case .power: "watts"
        case .power3: "3 s watts"
        case .cadence: "rpm"
        case .heartRate: "heart"
        case .elapsed: "elapsed"
        case .remaining: "remaining"
        case .distance: "distance"
        case .climbed: "climbed"
        case .energy: "energy"
        case .grade: "grade"
        case .gear: "gear"
        case .altitude: "altitude"
        case .toGo: "to go"
        case .ftpPercent: "% ftp"
        case .empty: ""
        }
    }

    /// Unit written after the value on faces that set them inline (Night, Horizon).
    func unit(_ d: FaceData) -> String {
        switch self {
        case .speed: d.speedUnit
        case .power: "watts"
        case .power3: "3 s watts"
        case .cadence: "rpm"
        case .heartRate: "bpm"
        case .elapsed: "elapsed"
        case .remaining: "remaining"
        case .distance: d.distUnit
        case .climbed: d.elevUnit + " climbed"
        case .energy: "kcal"
        case .grade: "grade"
        case .gear: "gear"
        case .altitude: d.elevUnit
        case .toGo: d.distUnit + " to go"
        case .ftpPercent: "of ftp"
        case .empty: ""
        }
    }

    /// Grade is the one metric a face may colour when the road tilts up.
    var tintsWhenClimbing: Bool { self == .grade }

    /// What a tap on the big number steps through mid-ride (D159, D160).
    static let heroRing: [FaceMetric] = [.speed, .power, .cadence, .heartRate, .ftpPercent, .grade]

    /// What takes the big number's small place, after speed (D161): the first a face doesn't show already.
    static let standIns: [FaceMetric] = [.power, .cadence, .heartRate, .ftpPercent, .grade, .elapsed, .distance, .climbed, .energy]
}

// MARK: - Tapping the big number

/// Mid-ride, shows the next big number (D159). Compared by what it depends on, as a closure can't be.
struct NextHeroAction: Equatable {
    /// Classic or a face: which default the round comes back to.
    let classic: Bool
    let perform: @MainActor @Sendable () -> Void

    static func == (a: Self, b: Self) -> Bool { a.classic == b.classic }

    @MainActor func callAsFunction() { perform() }
}

extension EnvironmentValues {
    /// nil outside the ride (the gallery, previews), where the number stays put.
    @Entry var nextHero: NextHeroAction? = nil
}

extension View {
    /// The big number: mid-ride, a tap on it shows the next one (D159), and so does VoiceOver's action.
    func heroTap() -> some View { modifier(HeroTap(tap: true)) }

    /// Only the VoiceOver action, for a face read as one element (its numbers inside aren't reachable).
    func heroAction() -> some View { modifier(HeroTap(tap: false)) }
}

private struct HeroTap: ViewModifier {
    let tap: Bool
    @Environment(\.nextHero) private var next

    func body(content: Content) -> some View {
        if let next {
            if tap {
                content
                    .contentShape(Rectangle())
                    .onTapGesture { next() }
                    .accessibilityAction(named: "Next main number") { next() }
            } else {
                content.accessibilityAction(named: "Next main number") { next() }
            }
        } else {
            content
        }
    }
}

// MARK: - Palettes

/// One face's colour scheme. Every face reads `bg`, `ink` and `accent`; Aura, Night and Horizon
/// also read the extras they're made of.
struct FacePalette: Identifiable, Sendable {
    let id: String
    let name: String
    let light: (bg: UInt32, ink: UInt32, accent: UInt32)
    let dark: (bg: UInt32, ink: UInt32, accent: UInt32)
    /// Night's glow, Aura's mesh ramp, Horizon's skies.
    var glow: UInt32?
    var mesh: [UInt32]?
    var skies: [[UInt32]]?

    func bg(dark d: Bool) -> Color { Color(hex: d ? dark.bg : light.bg) }
    func ink(dark d: Bool) -> Color { Color(hex: d ? dark.ink : light.ink) }
    func accent(dark d: Bool) -> Color { Color(hex: d ? dark.accent : light.accent) }
}

enum FacePalettes {
    /// The palettes a face offers; the first is its original design.
    static func options(for face: FaceID) -> [FacePalette] {
        switch face {
        case .paper: paper
        case .aura: aura
        case .night: night
        case .horizon: horizon
        case .kinetic: kinetic
        case .borne: borne
        case .stem: stem
        case .piste: piste
        case .groupset: groupset
        case .broadcast: broadcast
        case .tarmac: tarmac
        case .classic: []
        }
    }

    /// Increase Contrast (DESIGN §4, D138): the face's palette with the most contrast between ink and background.
    static func highestContrast(for face: FaceID, dark: Bool) -> FacePalette? {
        options(for: face).max { contrast($0, dark: dark) < contrast($1, dark: dark) }
    }

    /// WCAG contrast ratio of a palette's ink on its background.
    static func contrast(_ p: FacePalette, dark: Bool) -> Double {
        let (bg, ink) = dark ? (p.dark.bg, p.dark.ink) : (p.light.bg, p.light.ink)
        let a = luminance(bg), b = luminance(ink)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func luminance(_ hex: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double {
            let c = Double(v) / 255
            return c <= 0.039_28 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF) + 0.7152 * channel((hex >> 8) & 0xFF) + 0.0722 * channel(hex & 0xFF)
    }

    static func palette(_ face: FaceID, id: String) -> FacePalette {
        let all = options(for: face)
        return all.first { $0.id == id } ?? all.first ?? paper[0]
    }

    static let paper: [FacePalette] = [
        FacePalette(id: "newsprint", name: "Newsprint",
                    light: (0xF2EFE8, 0x141414, 0xC8341B), dark: (0x16151A, 0xEDEAE2, 0xFF6B4A)),
        FacePalette(id: "blueprint", name: "Blueprint",
                    light: (0xE7EEF5, 0x16283A, 0x1E6FA8), dark: (0x0E1724, 0xDCE7F2, 0x5BA9DE)),
        FacePalette(id: "moss", name: "Moss",
                    light: (0xEEF1E7, 0x1B2419, 0x4C7A32), dark: (0x11160F, 0xE4EADC, 0x8FBF5F)),
        FacePalette(id: "ink", name: "Ink",
                    light: (0xFFFFFF, 0x000000, 0x000000), dark: (0x000000, 0xFFFFFF, 0xFFFFFF)),
    ]

    /// Aura's mesh is the power-zone ramp; a palette can replace that ramp with one of its own.
    static let aura: [FacePalette] = [
        FacePalette(id: "zones", name: "Zones",
                    light: (0xF6F4F0, 0x14141A, 0x7A3410), dark: (0x07070B, 0xFFFFFF, 0xFFD9A8)),
        FacePalette(id: "ember", name: "Ember",
                    light: (0xFBF4EE, 0x1A1310, 0x8A2F10), dark: (0x0B0705, 0xFFF3EA, 0xFFC49F),
                    mesh: [0x6E4A2E, 0x8A5526, 0xA85F1E, 0xC46A1A, 0xDC7418, 0xEE8524, 0xFF9E3D]),
        FacePalette(id: "tide", name: "Tide",
                    light: (0xF0F5F7, 0x101A1F, 0x0F5C74), dark: (0x04080B, 0xEAF6FA, 0x9FE8FF),
                    mesh: [0x1E4D6B, 0x1C6079, 0x1A7386, 0x1E8894, 0x2A9C9B, 0x45B2A4, 0x6CC9B2]),
        FacePalette(id: "graphite", name: "Graphite",
                    light: (0xF4F4F4, 0x121212, 0x444444), dark: (0x08080A, 0xF2F2F2, 0xBBBBBB),
                    mesh: [0x2A2A2E, 0x3A3A40, 0x4C4C53, 0x5F5F67, 0x74747D, 0x8B8B94, 0xA5A5AD]),
    ]

    static let night: [FacePalette] = [
        FacePalette(id: "ice", name: "Ice",
                    light: (0x000000, 0xFFFFFF, 0x9FE8FF), dark: (0x000000, 0xFFFFFF, 0x9FE8FF), glow: 0x9FE8FF),
        FacePalette(id: "ember", name: "Ember",
                    light: (0x000000, 0xFFFFFF, 0xFFB38A), dark: (0x000000, 0xFFFFFF, 0xFFB38A), glow: 0xFFB38A),
        FacePalette(id: "lime", name: "Lime",
                    light: (0x000000, 0xFFFFFF, 0xA8F0A0), dark: (0x000000, 0xFFFFFF, 0xA8F0A0), glow: 0xA8F0A0),
        FacePalette(id: "violet", name: "Violet",
                    light: (0x000000, 0xFFFFFF, 0xC9A8FF), dark: (0x000000, 0xFFFFFF, 0xC9A8FF), glow: 0xC9A8FF),
    ]

    static let horizon: [FacePalette] = [
        FacePalette(id: "day", name: "A day",
                    light: (0xEAF1F6, 0x1A2230, 0xFF7A4D), dark: (0x0E1320, 0xEDF0F4, 0xFF9C6E),
                    skies: [[0xF3D9C8, 0xEFC6A8, 0xD9E2EA], [0xCFE2F0, 0xEAF1F6, 0xF7F9FA],
                            [0xBFD8EC, 0xDCE9F2, 0xF2F6F8], [0xF6D9B8, 0xE9B98E, 0xC9B4C4],
                            [0x2A3550, 0x1B2338, 0x0E1320]]),
        FacePalette(id: "dusk", name: "Long dusk",
                    light: (0xF3DCC6, 0x2A1A18, 0xC8341B), dark: (0x140C10, 0xF4E3D6, 0xFF9C6E),
                    skies: [[0xFBE2C4, 0xF6C79A, 0xE0A98C], [0xF8D2AE, 0xEFB988, 0xD59A80],
                            [0xF0BC96, 0xE2A07C, 0xBE8478], [0xC98C7E, 0x8E5F63, 0x5A3E48],
                            [0x36243A, 0x201828, 0x100C18]]),
        FacePalette(id: "paper-sky", name: "Paper sky",
                    light: (0xF2EFE8, 0x141414, 0xC8341B), dark: (0x16151A, 0xEDEAE2, 0xFF6B4A),
                    skies: [[0xF6F3EC, 0xF2EFE8, 0xEAE6DC], [0xF4F1EA, 0xEFECE4, 0xE6E2D8],
                            [0xF2EFE8, 0xEBE7DE, 0xE0DCD2], [0xEDE8DE, 0xE2DCD0, 0xD2CBBE],
                            [0x2A2822, 0x1E1C18, 0x14130F]]),
    ]

    // Round 3: the design's colours; Stem card and Groupset offer the rider's pick of felt tip and anodising.
    static let borne: [FacePalette] = [
        FacePalette(id: "stone", name: "Stone", light: (0xDDDBD4, 0x141414, 0x141414), dark: (0x0B0C0E, 0xF2F0EA, 0xF2F0EA)),
    ]
    static let stem: [FacePalette] = [
        FacePalette(id: "red", name: "Red felt", light: (0xE4E2DB, 0x141414, 0xC8261C), dark: (0x141517, 0xEDEBE5, 0xC8261C)),
        FacePalette(id: "blue", name: "Blue felt", light: (0xE4E2DB, 0x141414, 0x2B4FA8), dark: (0x141517, 0xEDEBE5, 0x2B4FA8)),
        FacePalette(id: "green", name: "Green felt", light: (0xE4E2DB, 0x141414, 0x2F7A48), dark: (0x141517, 0xEDEBE5, 0x2F7A48)),
    ]
    static let piste: [FacePalette] = [
        FacePalette(id: "pine", name: "Pine", light: (0xE9E7E1, 0x141414, 0xC8261C), dark: (0x0D0E11, 0xF4F3EE, 0xFFD65A)),
    ]
    static let groupset: [FacePalette] = [
        FacePalette(id: "orange", name: "Orange", light: (0xF1F1EE, 0x141517, 0xF26B1D), dark: (0x141517, 0xEDEEF0, 0xF26B1D)),
        FacePalette(id: "blue", name: "Blue", light: (0xF1F1EE, 0x141517, 0x2B7BE0), dark: (0x141517, 0xEDEEF0, 0x3D8BF0)),
        FacePalette(id: "red", name: "Red", light: (0xF1F1EE, 0x141517, 0xD8261C), dark: (0x141517, 0xEDEEF0, 0xE8392E)),
        FacePalette(id: "gold", name: "Gold", light: (0xF1F1EE, 0x141517, 0xC99A1A), dark: (0x141517, 0xEDEEF0, 0xE0B23A)),
    ]
    static let broadcast: [FacePalette] = [
        FacePalette(id: "navy", name: "Navy", light: (0x0B1A33, 0xFFFFFF, 0xFFD23F), dark: (0x0B1A33, 0xFFFFFF, 0xFFD23F)),
    ]
    static let tarmac: [FacePalette] = [
        FacePalette(id: "asphalt", name: "Asphalt", light: (0x35363A, 0xF4F4F0, 0xF2C230), dark: (0x1E1F21, 0xF4F4F0, 0xF2C230)),
    ]

    static let kinetic: [FacePalette] = [
        FacePalette(id: "press", name: "Press",
                    light: (0xFBFAF7, 0x111112, 0xC8341B), dark: (0x0B0B0C, 0xF4F3F0, 0xFF6B4A)),
        FacePalette(id: "signal", name: "Signal",
                    light: (0xF5F3EC, 0x14140F, 0x0B7A4B), dark: (0x0A0C0A, 0xF0F5EF, 0x4FD68A)),
        FacePalette(id: "blueprint", name: "Blueprint",
                    light: (0xE7EEF5, 0x16283A, 0x1E6FA8), dark: (0x0E1724, 0xDCE7F2, 0x5BA9DE)),
    ]
}

// MARK: - Style

/// What the rider chose for one face: its palette and what goes in its secondary slots.
struct FaceStyle: Codable, Equatable, Sendable {
    var paletteID: String
    var slots: [FaceMetric]
    /// The main (big) number, as the face draws it. No longer chosen per face (D160): the face view sets the rider's
    /// main number here. Kept so styles saved with one (D109) still load, and it carries over once.
    var hero: FaceMetric?
    /// The face's font; nil means the one it was designed with (D109).
    var font: FaceFont.Family?
    /// Set by the face view, not saved (D161): what shows in the big number's small place, so the two swap, and
    /// whether the face has a small place for it at all.
    var standIn: FaceMetric?
    var heroShown = true

    enum CodingKeys: String, CodingKey { case paletteID, slots, hero, font }

    init(paletteID: String, slots: [FaceMetric], hero: FaceMetric? = nil, font: FaceFont.Family? = nil) {
        self.paletteID = paletteID
        self.slots = slots
        self.hero = hero
        self.font = font
    }

    /// Styles saved before the main number and font could be chosen still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        paletteID = try c.decode(String.self, forKey: .paletteID)
        slots = try c.decode([FaceMetric].self, forKey: .slots)
        hero = try c.decodeIfPresent(FaceMetric.self, forKey: .hero)
        font = try c.decodeIfPresent(FaceFont.Family.self, forKey: .font)
    }

    var heroMetric: FaceMetric { hero ?? .speed }

    /// The big number's value: the face's own speed text (its decimals) when it's speed, else the metric's.
    func heroValue(_ d: FaceData, speed: String) -> String {
        heroMetric == .speed ? speed : heroMetric.value(d)
    }

    /// The big number's label: the face's own speed wording when it's speed, else the metric's unit.
    func heroLabel(_ d: FaceData, speed: String) -> String {
        heroMetric == .speed ? speed : heroMetric.unit(d)
    }

    /// The font to draw with: the rider's choice, or the face's own. The stem card's felt-tip Marker is kept.
    func family(_ design: FaceFont.Family) -> FaceFont.Family {
        design == .marker ? .marker : (font ?? design)
    }

    /// How many secondary slots each face has, and what it shows by default.
    static func defaultSlots(_ face: FaceID) -> [FaceMetric] {
        switch face {
        case .paper: [.elapsed, .remaining, .distance, .climbed, .energy]
        case .aura: [.power, .cadence, .elapsed, .grade, .gear]
        case .night: [.distance, .climbed, .energy]
        case .horizon: [.distance, .climbed, .gear]
        case .kinetic: [.elapsed, .remaining, .distance, .grade, .gear]
        // Round 3 faces have fixed layouts, taken from the objects they depict.
        case .borne, .stem, .piste, .groupset, .broadcast, .tarmac, .classic: []
        }
    }

    static func `default`(_ face: FaceID) -> FaceStyle {
        FaceStyle(paletteID: FacePalettes.options(for: face).first?.id ?? "", slots: defaultSlots(face))
    }

    func palette(_ face: FaceID) -> FacePalette { FacePalettes.palette(face, id: paletteID) }

    /// Slots, padded or trimmed to what the face expects (settings survive a face gaining a slot).
    /// The slots with their numbers, for ForEach: a slot's identity is its place on the face, whatever it shows
    /// (the same metric can be in two slots).
    func slotItems(_ face: FaceID) -> [FaceSlot] {
        slots(face).enumerated().map { FaceSlot(id: $0.offset, metric: $0.element) }
    }

    func slots(_ face: FaceID) -> [FaceMetric] {
        let wanted = Self.defaultSlots(face)
        let padded = slots.count == wanted.count ? slots : (0..<wanted.count).map { $0 < slots.count ? slots[$0] : wanted[$0] }
        // The big number's place among them goes to its stand-in (D161); with none, speed takes the last one.
        return HeroCycle.row(padded, hero: heroMetric, standIn: standIn, designed: .speed, heroShown: heroShown,
                             open: { $0 != .empty })
    }

    // MARK: The big number is unique (D161)

    /// What a small place designed for `metric` shows: the metric, or its stand-in while it's the big number.
    func at(_ metric: FaceMetric) -> FaceMetric {
        metric == heroMetric ? standIn ?? metric : metric
    }

    /// A small place's value and label: the design's own, or the stand-in's while `metric` is the big number. A label
    /// in capitals stays in capitals.
    func small(_ metric: FaceMetric, _ d: FaceData, _ value: String, _ label: String) -> (value: String, label: String) {
        let m = at(metric)
        guard m != metric else { return (value, label) }
        let short = m.short(d)
        return (m.value(d), label.rangeOfCharacter(from: .lowercaseLetters) == nil ? short.uppercased() : short)
    }

    /// The numbers each face draws in fixed small places (its slots aside), which the big number swaps with.
    static func fixedSmalls(_ face: FaceID) -> [FaceMetric] {
        switch face {
        case .paper: [.power, .power3, .cadence, .heartRate, .grade, .gear]
        case .aura: [.ftpPercent]
        case .night: [.power, .cadence, .elapsed, .grade, .gear]
        case .horizon: [.power, .cadence, .elapsed, .grade]
        case .kinetic: [.power, .cadence]
        case .borne: [.power, .cadence, .grade, .elapsed, .remaining, .gear]
        case .stem: [.power, .cadence, .grade, .elapsed, .remaining, .distance]
        case .piste: [.power, .cadence, .elapsed]
        case .groupset: [.power, .cadence, .elapsed, .grade, .gear]
        case .broadcast: [.gear, .power, .cadence, .grade, .elapsed, .heartRate]
        case .tarmac: [.power, .cadence, .elapsed, .remaining, .grade, .gear]
        case .classic: []
        }
    }
}

/// One numbered slot on a face and the metric it shows.
struct FaceSlot: Identifiable, Equatable {
    let id: Int
    let metric: FaceMetric
}
