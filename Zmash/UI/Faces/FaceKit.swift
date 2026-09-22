import CoreText
import SwiftUI
import UIKit
import ZmashKit

// MARK: - Faces

/// The ride-screen faces (design/Zmash Faces.dc.html). Order = gallery order.
enum FaceID: String, CaseIterable, Codable, Identifiable {
    case paper, aura, night, horizon, kinetic, classic

    var id: String { rawValue }

    var name: String {
        switch self {
        case .paper: "Paper"
        case .aura: "Aura"
        case .night: "Night"
        case .horizon: "Horizon"
        case .kinetic: "Kinetic"
        case .classic: "Classic"
        }
    }

    var description: String {
        switch self {
        case .paper: "A printed race programme. Rigorous grid, hairline rules, ink on warm paper. The legibility reference."
        case .aura: "No instruments. A living colour field that is your effort, with one enormous number floating in it."
        case .night: "A dark face made of light. Glowing lines, wind streaks at speed, numbers lit from within."
        case .horizon: "The terrain becomes a ridge you ride into. Numbers sit in a sky that drifts from dawn to night across the ride."
        case .kinetic: "Type is the only graphic. Power drives weight, speed drives width, grade drives slant."
        case .classic: "The original dashboard, fully customisable: choose every number, the typeface and the size."
        }
    }

    var magic: String {
        switch self {
        case .paper: "Proof print"
        case .aura: "Bloom"
        case .night: "Warp"
        case .horizon: "Summit"
        case .kinetic: "Sprint"
        case .classic: "Wind"
        }
    }

    static let defaultRotation: [FaceID] = [.paper, .aura, .horizon]
}

enum FaceMotion: String, Codable, CaseIterable {
    case full, calm
}

/// Design canvas: every face is laid out at 11" iPad landscape points and scaled to the screen.
enum FaceCanvas {
    static let size = CGSize(width: 1194, height: 834)
}

// MARK: - Data

enum FaceState: Equatable {
    case countdown(Int)
    case waiting
    case riding
    case paused(auto: Bool)
    case lost
    case done
}

/// Everything a face draws. Built from the live engine or from the gallery's demo ride.
struct FaceData {
    var speedKph: Double = 0
    var powerW: Double = 0
    var power3: Double = 0
    var cadenceRpm: Double = 0
    var heartRateBpm: Double?
    var elapsed: Double = 0
    var remaining: Double?
    var distanceM: Double = 0
    var kcal: Double = 0
    var climbedM: Double = 0
    var grade: Double = 0
    var gear = 12
    var gearCount = 24
    var ftp: Double = 200
    var crankDegrees: Double = 0
    /// 0…1 through a timed ride (free rides: through 90 minutes).
    var progress: Double = 0
    /// 61 normalised elevations (0.08…0.98) across the next 5 minutes (or the last 5 for manual terrain).
    var profile: [Double] = Array(repeating: 0.5, count: 61)
    var state: FaceState = .riding
    var event: FaceTelemetry.Event?
    /// 0…1 through the event's 2.2 s lifetime.
    var eventAge: Double = 1
    var trendSpeed: Double = 0
    var trendPower: Double = 0
    var units: Units = .metric

    var zone: Int { PowerZones.zone(powerW: powerW, ftp: ftp) }
    var climbing: Bool { grade > 0.4 }
    var sprint: Bool { powerW > ftp * 1.5 }
    func isEvent(_ kind: FaceTelemetry.EventKind) -> Bool { event?.kind == kind && eventAge < 1 }

    // Formatting, as in the design.
    var speedValue: Double { units.speed(speedKph) }
    var speed0: String { String(Int(speedValue.rounded())) }
    var speed1: String { String(format: "%.1f", speedValue) }
    var powerI: String { String(Int(powerW.rounded())) }
    var power3Text: String { String(Int(power3.rounded())) }
    var cadenceText: String { String(Int(cadenceRpm.rounded())) }
    var hrText: String { heartRateBpm.map { String(Int($0.rounded())) } ?? "—" }
    var elapsedText: String { TimeFormat.clock(Int(elapsed)) }
    var remainingText: String { remaining.map { "−" + TimeFormat.clock(Int($0.rounded(.up))) } ?? "—" }
    var distText: String { String(format: "%.1f", units.distance(distanceM)) }
    var kcalText: String { String(Int(kcal.rounded())) }
    var climbedText: String { String(Int(units.elevation(climbedM).rounded())) }
    var gradeText: String { (grade >= 0 ? "+" : "−") + String(format: "%.1f", abs(grade)) + "%" }
    var gearText: String { "\(gear)/\(gearCount)" }
    var speedUnit: String { units.speedUnit }
    var speedUnitLong: String { units == .metric ? "kilometres per hour" : "miles per hour" }
    var distUnit: String { units.distanceUnit }
    var elevUnit: String { units.elevationUnit }
}

extension FaceData {
    @MainActor
    init(engine: SessionEngine, units: Units) {
        let tele = engine.telemetry
        speedKph = engine.speedKph
        powerW = Double(engine.instantPowerW ?? 0)
        power3 = tele.power3
        cadenceRpm = Double(engine.cadenceRpm ?? 0)
        heartRateBpm = engine.heartRateBpm.map(Double.init)
        elapsed = engine.elapsed
        remaining = engine.remaining
        distanceM = engine.distanceM
        kcal = engine.kcal
        climbedM = engine.elevationGainM
        grade = engine.terrainGrade
        gear = engine.controls.gear
        gearCount = engine.controls.gears.count
        ftp = tele.ftp
        crankDegrees = tele.crankDegrees
        progress = engine.progress
        profile = engine.faceProfile
        event = tele.event
        eventAge = tele.eventAge(at: engine.elapsed) ?? 1
        trendSpeed = tele.trendSpeed
        trendPower = tele.trendPower
        self.units = units
        state = switch engine.phase {
        case .countdown(let n): .countdown(n)
        case .waitingForPedal: .waiting
        case .paused(let auto): .paused(auto: auto)
        case .riding, .finished: engine.timedDone ? .done : engine.trainerLost ? .lost : .riding
        }
    }
}

// MARK: - Power zone colours (design palette)

enum ZoneColors {
    static let colors: [Color] = [0x3A6EA8, 0x2E8A9A, 0x2F9160, 0xC9A227, 0xD4732A, 0xC23B4A, 0xA32B6B].map { Color(hex: $0) }
    static func color(_ zone: Int) -> Color { colors[min(max(zone, 1), 7) - 1] }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

// MARK: - Fonts

/// The design's typefaces, bundled (SIL OFL) and driven through their variation axes.
enum FaceFont {
    enum Family {
        case archivo, newsreader, outfit, robotoFlex

        var postScriptName: String {
            switch self {
            case .archivo: "ArchivoRoman-Thin"
            case .newsreader: "NewsreaderRoman-ExtraLight"
            case .outfit: "Outfit-Thin"
            case .robotoFlex: "RobotoFlex-Regular_Thin"
            }
        }
    }

    // OpenType axis tags as CoreText identifiers.
    static let wght = 2003265652
    static let wdth = 2003072104
    static let slnt = 1936486004
    static let opsz = 1869640570

    @MainActor private static var cache: [String: Font] = [:]

    /// A tabular-figure font at `size` with the given axes (values are quantised for caching).
    @MainActor
    static func font(_ family: Family, _ size: CGFloat, weight: Double = 400, width: Double? = nil, slant: Double? = nil) -> Font {
        let w = (weight / 10).rounded() * 10
        let d = width.map { $0.rounded() }
        let s = slant.map { ($0 * 2).rounded() / 2 }
        let key = "\(family)|\(size)|\(w)|\(d ?? -1)|\(s ?? 99)"
        if let cached = cache[key] { return cached }

        var axes: [Int: Double] = [wght: w]
        if let d { axes[wdth] = d }
        if let s { axes[slnt] = s }
        if family == .newsreader { axes[opsz] = min(72, max(6, Double(size))) }
        let features: [[UIFontDescriptor.FeatureKey: Int]] = [[
            .type: kNumberSpacingType, .selector: kMonospacedNumbersSelector,
        ]]
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: family.postScriptName,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes,
            .featureSettings: features,
        ])
        let font = Font(UIFont(descriptor: descriptor, size: size) as CTFont)
        cache[key] = font
        return font
    }
}

extension View {
    /// Tracked uppercase label, as the design's `letter-spacing: Xem; text-transform: uppercase`.
    func faceLabel(_ family: FaceFont.Family = .archivo, _ size: CGFloat, tracking em: CGFloat, weight: Double = 400) -> some View {
        self.font(FaceFont.font(family, size, weight: weight)).tracking(size * em).textCase(.uppercase)
    }
}

// MARK: - Shared overlays

/// Countdown / waiting / paused / lost / done, in the face's own type.
struct FaceStateOverlay: View {
    let data: FaceData
    let family: FaceFont.Family
    let ink: Color
    let lightScrim: Bool
    let paperDone: Bool

    var body: some View {
        if let content {
            ZStack {
                (lightScrim ? Color(hex: 0xF2EFE8, opacity: 0.72) : Color.black.opacity(0.62))
                VStack(spacing: 18) {
                    Text(content.title)
                        .font(FaceFont.font(family, content.countdown ? 300 : 110, weight: 400))
                        .tracking(content.countdown ? 0 : 110 * 0.16)
                        .textCase(.uppercase)
                        .foregroundStyle(ink)
                        .contentTransition(.numericText(countsDown: true))
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(content.sub)
                        .faceLabel(.archivo, 19, tracking: 0.3)
                        .foregroundStyle(ink.opacity(0.78))
                }
                .padding(.horizontal, 60)
            }
            .allowsHitTesting(false)
            .animation(.snappy, value: content.title)
        }
    }

    private var content: (title: String, sub: String, countdown: Bool)? {
        switch data.state {
        case .riding: return nil
        case .countdown(let n): return ("\(n)", "get ready", true)
        case .waiting: return ("pedal to start", "the clock starts on your first stroke", false)
        case .paused(let auto): return ("paused", auto ? "auto-paused · pedal to resume" : "press pause to resume", false)
        case .lost: return ("trainer lost", "searching for the trainer", false)
        case .done:
            let sub = "\(data.distText) \(data.distUnit) · \(data.climbedText) \(data.elevUnit) · \(data.kcalText) kcal"
            return ("ride complete", paperDone ? "proof print · " + sub : sub, false)
        }
    }
}

/// "Magic moment" labels (kilometre, summit, session best) at the top centre.
struct FaceEventToast: View {
    let data: FaceData
    let ink: Color
    let background: Color

    var body: some View {
        if let e = data.event, !e.label.isEmpty, data.eventAge < 1, data.state == .riding {
            Text(e.label)
                .faceLabel(.archivo, 16, tracking: 0.28)
                .foregroundStyle(ink)
                .padding(.horizontal, 22).padding(.vertical, 10)
                .background(background)
                .overlay(Rectangle().stroke(ink, lineWidth: 1))
                .opacity(1 - pow(data.eventAge, 3))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 26)
                .allowsHitTesting(false)
        }
    }
}

/// Lays a face out on the 1194×834 design canvas and scales it to fit, letterboxed in `background`.
struct FaceCanvasView<Content: View>: View {
    let background: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let fit = min(geo.size.width / FaceCanvas.size.width, geo.size.height / FaceCanvas.size.height)
            let cover = max(geo.size.width / FaceCanvas.size.width, geo.size.height / FaceCanvas.size.height)
            // Within 3 %, fill edge to edge (crops a few points); beyond, letterbox rather than crop content.
            let s = cover / fit < 1.03 ? cover : fit
            ZStack {
                background
                content()
                    .frame(width: FaceCanvas.size.width, height: FaceCanvas.size.height)
                    .clipped()
                    .scaleEffect(s)
                    .frame(width: FaceCanvas.size.width * s, height: FaceCanvas.size.height * s)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}
