import Foundation

/// A route ridden by distance rather than by time (roadmap Phase 8): an elevation profile,
/// resampled every 100 m so grade lookups are a constant-time index.
public struct Route: Codable, Equatable, Identifiable, Sendable {
    /// Distance between profile points.
    public static let step: Double = 100
    /// Gradients are clamped to what the trainer and the rider can use (U5: nothing below −10 %).
    public static let gradeRange: ClosedRange<Double> = -10...16

    public var id: String
    public var name: String
    public var place: String
    /// Elevation in metres, every `step` metres from the start.
    public var elevations: [Double]
    /// True for the bundled climbs, whose profiles are approximations.
    public var approximate = false

    public init(id: String, name: String, place: String, elevations: [Double], approximate: Bool = false) {
        self.id = id
        self.name = name
        self.place = place
        self.elevations = elevations
        self.approximate = approximate
    }

    public var distanceM: Double { Double(max(elevations.count - 1, 0)) * Self.step }

    public var ascentM: Double {
        zip(elevations, elevations.dropFirst()).reduce(0) { $0 + max(0, $1.1 - $1.0) }
    }

    public var maxElevationM: Double { elevations.max() ?? 0 }
    public var minElevationM: Double { elevations.min() ?? 0 }

    public var averageGrade: Double {
        distanceM > 0 ? (elevations.last! - elevations.first!) / distanceM * 100 : 0
    }

    /// The steepest kilometre of the route.
    public var steepestKmGrade: Double {
        let n = Int(1000 / Self.step)
        guard elevations.count > n else { return averageGrade }
        return (0...(elevations.count - 1 - n)).map { (elevations[$0 + n] - elevations[$0]) / 1000 * 100 }.max() ?? 0
    }

    /// Distance of the highest point (the summit to ride towards).
    public var summitDistanceM: Double {
        guard let i = elevations.firstIndex(of: maxElevationM) else { return distanceM }
        return Double(i) * Self.step
    }

    public func elevation(atDistance d: Double) -> Double {
        guard elevations.count > 1 else { return elevations.first ?? 0 }
        let x = min(max(d / Self.step, 0), Double(elevations.count - 1))
        let i = Int(x)
        if i >= elevations.count - 1 { return elevations[elevations.count - 1] }
        return elevations[i] + (elevations[i + 1] - elevations[i]) * (x - Double(i))
    }

    /// Gradient over the 100 m the rider is on.
    public func grade(atDistance d: Double) -> Double {
        guard elevations.count > 1 else { return 0 }
        let i = min(max(Int(d / Self.step), 0), elevations.count - 2)
        let g = (elevations[i + 1] - elevations[i]) / Self.step * 100
        return min(max(g, Self.gradeRange.lowerBound), Self.gradeRange.upperBound)
    }

    /// Gradients every `stepM` metres from `from`, for the faces' terrain strip.
    public func grades(from: Double, spanM: Double, stepM: Double) -> [Double] {
        stride(from: from, through: from + spanM, by: stepM).map { grade(atDistance: $0) }
    }

    public var summary: String {
        String(format: "%.1f km · %.0f m · %.1f %%", distanceM / 1000, ascentM, averageGrade)
    }
}

// MARK: - Building

public enum RouteBuilder {
    /// Builds a route from raw (distance, elevation) points: resampled to 100 m and smoothed,
    /// so GPS elevation noise doesn't turn into a jackhammer on the trainer.
    public static func make(id: String, name: String, place: String = "", points: [(distanceM: Double, elevationM: Double)],
                            approximate: Bool = false) -> Route? {
        let points = points.sorted { $0.distanceM < $1.distanceM }
        guard let last = points.last, last.distanceM >= Route.step, points.count > 1 else { return nil }
        var sampled: [Double] = []
        var i = 0
        var d = 0.0
        while d <= last.distanceM {
            while i < points.count - 2, points[i + 1].distanceM < d { i += 1 }
            let a = points[i], b = points[i + 1]
            let span = b.distanceM - a.distanceM
            let t = span > 0 ? min(max((d - a.distanceM) / span, 0), 1) : 0
            sampled.append(a.elevationM + (b.elevationM - a.elevationM) * t)
            d += Route.step
        }
        return Route(id: id, name: name, place: place, elevations: smooth(sampled), approximate: approximate)
    }

    /// Three-point moving average, twice: enough to kill barometric jitter, not enough to flatten a ramp.
    static func smooth(_ values: [Double]) -> [Double] {
        var out = values
        for _ in 0..<2 {
            guard out.count > 2 else { break }
            var next = out
            for i in 1..<(out.count - 1) { next[i] = (out[i - 1] + out[i] * 2 + out[i + 1]) / 4 }
            out = next
        }
        return out
    }

    /// Metres between two coordinates (haversine, mean Earth radius).
    public static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Turns a track of coordinates with elevation into a route.
    public static func fromTrack(id: String, name: String, place: String = "",
                                 track: [(lat: Double, lon: Double, ele: Double)]) -> Route? {
        guard track.count > 1 else { return nil }
        var points: [(distanceM: Double, elevationM: Double)] = [(0, track[0].ele)]
        var total = 0.0
        for (a, b) in zip(track, track.dropFirst()) {
            total += distance(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon)
            points.append((total, b.ele))
        }
        return make(id: id, name: name, place: place, points: points)
    }
}

// MARK: - GPX

/// Reads the track (or route) points of a GPX file: `trkpt`/`rtept` with `lat`, `lon` and `ele`.
public final class GPXParser: NSObject, XMLParserDelegate {
    private var track: [(lat: Double, lon: Double, ele: Double)] = []
    var points: [(lat: Double, lon: Double, ele: Double)] { track }
    private var pending: (lat: Double, lon: Double)?
    private var name: String?
    private var text = ""

    public static func parse(_ data: Data, id: String) -> Route? {
        let p = GPXParser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        guard xml.parse(), p.track.count > 1 else { return nil }
        return RouteBuilder.fromTrack(id: id, name: p.name ?? "Imported route", track: p.track)
    }

    public func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                       qualifiedName: String?, attributes a: [String: String]) {
        text = ""
        let e = element.lowercased()
        guard e == "trkpt" || e == "rtept" || e == "wpt" && !track.isEmpty,
              let lat = Double(a["lat"] ?? ""), let lon = Double(a["lon"] ?? "") else { return }
        pending = (lat, lon)
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    public func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        switch element.lowercased() {
        case "ele":
            if let p = pending, let ele = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                track.append((p.lat, p.lon, ele))
                pending = nil
            }
        case "name":
            if name == nil {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { name = t }
            }
        case "trkpt", "rtept", "wpt":
            pending = nil
        default:
            break
        }
    }
}

// MARK: - FIT

/// Reads the `record` messages of a FIT file (the format Garmin, Wahoo and Strava export),
/// taking distance and altitude — or position when the file has no distance.
public enum FITRouteReader {
    private struct FieldDef { let number: UInt8; let size: Int; let baseType: UInt8 }
    private struct MessageDef {
        let global: UInt16
        let littleEndian: Bool
        let fields: [FieldDef]
        /// Bytes of developer fields (Connect IQ, Stryd…) after the standard ones in each data message: skipped.
        var developerBytes = 0
    }

    public static func parse(_ data: Data, id: String, name: String = "Imported route") -> Route? {
        let bytes = [UInt8](data)
        guard bytes.count > 14, bytes[8] == 0x2E, bytes[9] == 0x46, bytes[10] == 0x49, bytes[11] == 0x54 else { return nil }
        var i = Int(bytes[0])
        let dataEnd = min(bytes.count, i + Int(UInt32(bytes[4]) | UInt32(bytes[5]) << 8 | UInt32(bytes[6]) << 16 | UInt32(bytes[7]) << 24))
        var defs: [UInt8: MessageDef] = [:]
        var byDistance: [(distanceM: Double, elevationM: Double)] = []
        var track: [(lat: Double, lon: Double, ele: Double)] = []

        while i < dataEnd {
            let header = bytes[i]
            i += 1
            if header & 0x80 != 0 { // compressed timestamp: data message, local type in bits 5–6
                let local = (header >> 5) & 0x03
                guard let def = defs[local] else { return nil }
                i = read(bytes, at: i, def: def, byDistance: &byDistance, track: &track)
                continue
            }
            let local = header & 0x0F
            if header & 0x40 != 0 { // definition message
                guard i + 5 <= dataEnd else { break }
                let littleEndian = bytes[i + 1] == 0
                let global = littleEndian ? UInt16(bytes[i + 2]) | UInt16(bytes[i + 3]) << 8
                                          : UInt16(bytes[i + 2]) << 8 | UInt16(bytes[i + 3])
                let count = Int(bytes[i + 4])
                i += 5
                var fields: [FieldDef] = []
                for _ in 0..<count {
                    guard i + 3 <= dataEnd else { return nil }
                    fields.append(FieldDef(number: bytes[i], size: Int(bytes[i + 1]), baseType: bytes[i + 2]))
                    i += 3
                }
                var developerBytes = 0
                if header & 0x20 != 0 { // developer fields: number, size, developer index each; only their size matters
                    guard i < dataEnd else { break }
                    let devCount = Int(bytes[i])
                    i += 1
                    for _ in 0..<devCount {
                        guard i + 3 <= dataEnd else { return nil }
                        developerBytes += Int(bytes[i + 1])
                        i += 3
                    }
                }
                defs[local] = MessageDef(global: global, littleEndian: littleEndian, fields: fields, developerBytes: developerBytes)
            } else {
                guard let def = defs[local] else { return nil }
                i = read(bytes, at: i, def: def, byDistance: &byDistance, track: &track)
            }
        }

        if byDistance.count > 1 { return RouteBuilder.make(id: id, name: name, points: byDistance) }
        return RouteBuilder.fromTrack(id: id, name: name, track: track)
    }

    /// Reads one data message, keeping record (20) distance/altitude/position.
    private static func read(_ bytes: [UInt8], at start: Int, def: MessageDef,
                             byDistance: inout [(distanceM: Double, elevationM: Double)],
                             track: inout [(lat: Double, lon: Double, ele: Double)]) -> Int {
        var i = start
        var distance: Double?
        var altitude: Double?
        var lat: Double?
        var lon: Double?
        for f in def.fields {
            defer { i += f.size }
            guard def.global == 20, i + f.size <= bytes.count else { continue }
            let raw = uint(bytes, at: i, size: f.size, littleEndian: def.littleEndian)
            switch f.number {
            case 0: if raw != 0x7FFF_FFFF { lat = Double(Int32(bitPattern: UInt32(truncatingIfNeeded: raw))) * (180 / 2_147_483_648) }
            case 1: if raw != 0x7FFF_FFFF { lon = Double(Int32(bitPattern: UInt32(truncatingIfNeeded: raw))) * (180 / 2_147_483_648) }
            case 2: if raw != 0xFFFF { altitude = Double(raw) / 5 - 500 }         // altitude, m
            case 5: if raw != 0xFFFF_FFFF { distance = Double(raw) / 100 }        // distance, cm
            case 78: if raw != 0xFFFF_FFFF { altitude = Double(raw) / 5 - 500 }   // enhanced_altitude
            default: break
            }
        }
        if let altitude {
            if let distance { byDistance.append((distance, altitude)) }
            if let lat, let lon { track.append((lat, lon, altitude)) }
        }
        return i + def.developerBytes
    }

    private static func uint(_ bytes: [UInt8], at i: Int, size: Int, littleEndian: Bool) -> UInt32 {
        let slice = Array(bytes[i..<min(i + min(size, 4), bytes.count)])
        return (littleEndian ? slice.reversed() : slice).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }
}

// MARK: - Ghost

/// A previous attempt at a route: the time it reached each 100 m.
public struct Ghost: Codable, Equatable, Sendable {
    /// Seconds elapsed at each profile point.
    public var times: [Double]

    public init(times: [Double]) { self.times = times }

    /// Builds a ghost from a ride's samples (1 Hz speed integrates to distance).
    public init?(samples: [RideSample]) {
        guard samples.count > 1 else { return nil }
        var times: [Double] = [0]
        var distance = 0.0
        var next = Route.step
        for s in samples {
            distance += s.speedKph / 3.6
            while distance >= next {
                times.append(Double(s.t))
                next += Route.step
            }
        }
        guard times.count > 1 else { return nil }
        self.times = times
    }

    public var totalSeconds: Double { times.last ?? 0 }

    /// Seconds ahead (positive) or behind (negative) the ghost at this distance, or nil past its end.
    public func delta(elapsed: Double, distanceM: Double) -> Double? {
        let x = distanceM / Route.step
        let i = Int(x)
        guard i >= 0, i + 1 < times.count else { return nil }
        let ghostTime = times[i] + (times[i + 1] - times[i]) * (x - Double(i))
        return ghostTime - elapsed
    }
}
