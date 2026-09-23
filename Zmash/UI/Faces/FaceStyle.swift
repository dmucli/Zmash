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
        case .ftpPercent: "\(Int((d.powerW / max(d.ftp, 1) * 100).rounded()))%"
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

    /// How many secondary slots each face has, and what it shows by default.
    static func defaultSlots(_ face: FaceID) -> [FaceMetric] {
        switch face {
        case .paper: [.elapsed, .remaining, .distance, .climbed, .energy]
        case .aura: [.speed, .cadence, .elapsed, .grade, .gear]
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
    func slots(_ face: FaceID) -> [FaceMetric] {
        let wanted = Self.defaultSlots(face)
        guard slots.count != wanted.count else { return slots }
        return (0..<wanted.count).map { $0 < slots.count ? slots[$0] : wanted[$0] }
    }
}
