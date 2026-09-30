import Foundation

/// Minimal Garmin FIT activity encoder: file_id, event, 1 Hz records (with hrv when the strap sends RR), laps (one per
/// workout interval), session, activity.
/// Enough for Strava, Garmin Connect, TrainingPeaks and intervals.icu to import an indoor ride.
/// Written from the public FIT protocol description (little-endian, FIT CRC-16).
public enum FITWriter {
    /// Seconds between the Unix epoch and the FIT epoch (1989-12-31 00:00:00 UTC).
    static let fitEpochOffset: TimeInterval = 631_065_600

    enum BaseType: UInt8 {
        case enumeration = 0x00
        case uint8 = 0x02
        case uint16 = 0x84
        case uint32 = 0x86
    }

    struct Field {
        let number: UInt8
        let type: BaseType
        let value: UInt64
        /// An array field (the hrv message's times): its values, all of `type`.
        var array: [UInt64]? = nil

        init(number: UInt8, type: BaseType, value: UInt64) {
            self.number = number
            self.type = type
            self.value = value
        }

        init(number: UInt8, type: BaseType, array: [UInt64]) {
            self.number = number
            self.type = type
            self.value = 0
            self.array = array
        }

        var baseSize: Int {
            switch type {
            case .enumeration, .uint8: 1
            case .uint16: 2
            case .uint32: 4
            }
        }

        var size: Int { baseSize * (array?.count ?? 1) }

        var bytes: [UInt8] { (array ?? [value]).flatMap { le($0, baseSize) } }
    }

    enum Message: UInt16 {
        case fileId = 0
        case session = 18
        case lap = 19
        case record = 20
        case event = 21
        case activity = 34
        case hrv = 78
    }

    /// `startAltitudeM`: where the ride begins, when it's a real road (a route's first point); altitude per record is
    /// then climbed from each second's gradient and distance, so the file carries the ride's profile.
    /// Pauses (`RideSample.pausedBefore`) keep the wall clock: records are timestamped as they happened, the timer
    /// stops and starts around each pause, and the elapsed time runs to `endedAt` while the timer time is the active
    /// time. Without pauses (and in rides from before they were kept), active time and wall clock are the same.
    public static func encode(startedAt: Date, samples: [RideSample], summary: SessionSummary,
                              startAltitudeM: Double = 0, endedAt: Date? = nil) -> Data {
        var body = Body()
        let timeline = RideTimeline(samples: samples)
        let start = fitTime(startedAt)
        let active = max(summary.activeSeconds, samples.last.map { $0.t + 1 } ?? 0)
        let minimumEnd = start + UInt32(Double(active) + timeline.pausedSeconds)
        let end = max(minimumEnd, endedAt.map(fitTime) ?? 0)
        let activeMs = UInt64(summary.activeSeconds) * 1000
        let elapsedMs = UInt64(end - start) * 1000

        body.message(.fileId, local: 0, [
            Field(number: 0, type: .enumeration, value: 4),   // type: activity
            Field(number: 1, type: .uint16, value: 255),      // manufacturer: development
            Field(number: 2, type: .uint16, value: 1),        // product
            Field(number: 4, type: .uint32, value: UInt64(start)), // time_created
        ])

        body.message(.event, local: 1, [
            Field(number: 253, type: .uint32, value: UInt64(start)),
            Field(number: 0, type: .enumeration, value: 0),   // event: timer
            Field(number: 1, type: .enumeration, value: 0),   // event_type: start
        ])

        // Distance per record, integrated from speed so it ends at the ride's distance.
        let integrated = samples.reduce(0.0) { $0 + $1.speedKph / 3.6 }
        let scale = integrated > 0 ? summary.distanceM / integrated : 0
        var distance = 0.0
        var altitude = startAltitudeM
        let hasHR = samples.contains { $0.heartRateBpm != nil }
        /// Distance at the end of each second, for the laps.
        var distanceAt: [Double] = []
        distanceAt.reserveCapacity(samples.count)
        for s in samples {
            if let paused = s.pausedBefore, paused > 0 {
                // The timer stopped when the pause began, and starts again now.
                let resumed = start + UInt32(timeline.wall(active: Double(s.t)))
                let stopped = resumed - UInt32(paused.rounded())
                timerEvent(&body, at: stopped, type: 4)   // stop_all
                timerEvent(&body, at: resumed, type: 0)   // start
            }
            let step = s.speedKph / 3.6 * scale
            distance += step
            distanceAt.append(distance)
            altitude += step * s.gradePercent / 100
            // One record layout per file: with heart rate (local 6) or without (local 2). A second with no reading
            // (the strap dropped out) is FIT's "invalid", not 0 bpm.
            let bpm = s.heartRateBpm.map { UInt64(min(254, max(0, $0))) } ?? 0xFF
            let hr: [Field] = hasHR ? [Field(number: 3, type: .uint8, value: bpm)] : []
            body.message(.record, local: hasHR ? 6 : 2, hr + [
                Field(number: 253, type: .uint32, value: UInt64(start + UInt32(timeline.wall(active: Double(s.t))))),
                Field(number: 5, type: .uint32, value: UInt64((distance * 100).rounded())),      // distance, cm
                Field(number: 2, type: .uint16, value: UInt64(min(65_534, max(0, ((altitude + 500) * 5).rounded())))), // altitude
                Field(number: 6, type: .uint16, value: UInt64(min(65_534, (s.speedKph / 3.6 * 1000).rounded()))), // speed, mm/s
                Field(number: 7, type: .uint16, value: UInt64(min(65_534, max(0, s.powerW)))),   // power
                Field(number: 4, type: .uint8, value: UInt64(min(254, max(0, s.cadenceRpm)))),   // cadence
            ])
            // Beat-to-beat intervals (D150): hrv messages of five times each, in 1/1000 s, padded with FIT's
            // invalid. Read back as a stream in order, they give intervals.icu its HRV and DFA α1.
            if let rr = s.rrMs, !rr.isEmpty {
                for chunk in stride(from: 0, to: rr.count, by: 5).map({ Array(rr[$0..<min($0 + 5, rr.count)]) }) {
                    let times = chunk.map { UInt64(min(65_534, max(0, $0))) } + Array(repeating: 0xFFFF, count: 5 - chunk.count)
                    body.message(.hrv, local: 7, [Field(number: 0, type: .uint16, array: times)])
                }
            }
        }

        let common: [Field] = [
            Field(number: 253, type: .uint32, value: UInt64(end)),
            Field(number: 2, type: .uint32, value: UInt64(start)),                    // start_time
            Field(number: 7, type: .uint32, value: elapsedMs),                        // total_elapsed_time, ms
            Field(number: 8, type: .uint32, value: activeMs),                         // total_timer_time, ms
            Field(number: 9, type: .uint32, value: UInt64((summary.distanceM * 100).rounded())), // total_distance, cm
            Field(number: 11, type: .uint16, value: UInt64(summary.kcal.rounded())),  // total_calories
            Field(number: 1, type: .enumeration, value: 1),                           // event_type: stop
        ]

        // One lap per workout interval when the ride has them (D151), otherwise the whole ride.
        let laps = Lap.of(samples)
        if laps.count > 1 {
            for (i, lap) in laps.enumerated() {
                let first = lap.range.lowerBound, last = lap.range.upperBound - 1
                let lapStart = start + UInt32(timeline.wall(active: Double(samples[first].t)))
                let lapEnd = i == laps.count - 1 ? end : start + UInt32(timeline.wall(active: Double(samples[last].t + 1)))
                let fromM = first == 0 ? 0 : distanceAt[first - 1]
                let share = Double(lap.seconds) / Double(max(samples.count, 1))
                body.message(.lap, local: 3, [
                    Field(number: 253, type: .uint32, value: UInt64(lapEnd)),
                    Field(number: 2, type: .uint32, value: UInt64(lapStart)),                // start_time
                    Field(number: 7, type: .uint32, value: UInt64(lapEnd - lapStart) * 1000), // total_elapsed_time, ms
                    Field(number: 8, type: .uint32, value: UInt64(lap.seconds) * 1000),       // total_timer_time, ms
                    Field(number: 9, type: .uint32, value: UInt64(((distanceAt[last] - fromM) * 100).rounded())), // distance, cm
                    Field(number: 11, type: .uint16, value: UInt64((summary.kcal * share).rounded())), // total_calories
                    Field(number: 13, type: .uint16, value: UInt64((lap.avgSpeedKph / 3.6 * 1000).rounded())), // avg_speed
                    Field(number: 17, type: .uint8, value: UInt64(min(254, lap.avgCadenceRpm))), // avg_cadence
                    Field(number: 19, type: .uint16, value: UInt64(lap.avgPowerW)),           // avg_power
                    Field(number: 20, type: .uint16, value: UInt64(lap.maxPowerW)),           // max_power
                    Field(number: 24, type: .enumeration, value: i == laps.count - 1 ? 7 : 1), // lap_trigger: time, session_end
                    Field(number: 0, type: .enumeration, value: 9),                           // event: lap
                    Field(number: 1, type: .enumeration, value: 1),                           // event_type: stop
                ] + (hasHR ? [
                    Field(number: 15, type: .uint8, value: UInt64(lap.avgHeartRateBpm ?? 0xFF)), // avg_heart_rate
                    Field(number: 16, type: .uint8, value: UInt64(lap.maxHeartRateBpm ?? 0xFF)), // max_heart_rate
                ] : []))
            }
        } else {
            body.message(.lap, local: 3, common + [
                Field(number: 0, type: .enumeration, value: 9),                           // event: lap
            ])
        }

        body.message(.session, local: 4, common + [
            Field(number: 0, type: .enumeration, value: 8),                           // event: session
            Field(number: 5, type: .enumeration, value: 2),                           // sport: cycling
            Field(number: 6, type: .enumeration, value: 6),                           // sub_sport: indoor_cycling
            Field(number: 14, type: .uint16, value: UInt64((summary.avgSpeedKph / 3.6 * 1000).rounded())), // avg_speed
            Field(number: 18, type: .uint8, value: UInt64(summary.avgCadenceRpm)),    // avg_cadence
            Field(number: 20, type: .uint16, value: UInt64(summary.avgPowerW)),       // avg_power
            Field(number: 21, type: .uint16, value: UInt64(summary.maxPowerW)),       // max_power
            Field(number: 22, type: .uint16, value: UInt64(summary.elevationGainM.rounded())), // total_ascent, m
            Field(number: 25, type: .uint16, value: 0),                               // first_lap_index
            Field(number: 26, type: .uint16, value: UInt64(max(laps.count, 1))),      // num_laps
        ] + (summary.avgHeartRateBpm.map { [
            Field(number: 16, type: .uint8, value: UInt64($0)),                       // avg_heart_rate
            Field(number: 17, type: .uint8, value: UInt64(summary.maxHeartRateBpm ?? $0)), // max_heart_rate
        ] } ?? []))

        body.message(.activity, local: 5, [
            Field(number: 253, type: .uint32, value: UInt64(end)),
            Field(number: 0, type: .uint32, value: activeMs),                         // total_timer_time
            Field(number: 1, type: .uint16, value: 1),                                // num_sessions
            Field(number: 2, type: .enumeration, value: 0),                           // type: manual
            Field(number: 3, type: .enumeration, value: 26),                          // event: activity
            Field(number: 4, type: .enumeration, value: 1),                           // event_type: stop
        ])

        var header: [UInt8] = [14, 0x10]                        // header size, protocol 1.0
        header += le(UInt64(2132), 2)                           // profile version 21.32
        header += le(UInt64(body.bytes.count), 4)               // data size
        header += Array(".FIT".utf8)
        header += le(UInt64(crc16(header)), 2)

        var file = header + body.bytes
        file += le(UInt64(crc16(file)), 2)
        return Data(file)
    }

    /// A timer event (event 0) of `type` (0 start, 4 stop all), sharing the start event's layout.
    private static func timerEvent(_ body: inout Body, at time: UInt32, type: UInt64) {
        body.message(.event, local: 1, [
            Field(number: 253, type: .uint32, value: UInt64(time)),
            Field(number: 0, type: .enumeration, value: 0),
            Field(number: 1, type: .enumeration, value: type),
        ])
    }

    static func fitTime(_ date: Date) -> UInt32 {
        UInt32(max(0, date.timeIntervalSince1970 - fitEpochOffset))
    }

    /// FIT CRC-16 (CRC-16/ARC: poly 0x8005 reflected, init 0).
    public static func crc16(_ bytes: [UInt8]) -> UInt16 {
        let table: [UInt16] = [0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
                               0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400]
        var crc: UInt16 = 0
        for byte in bytes {
            var tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int(byte & 0xF)]
            tmp = table[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ table[Int((byte >> 4) & 0xF)]
        }
        return crc
    }

    static func le(_ value: UInt64, _ size: Int) -> [UInt8] {
        (0..<size).map { UInt8((value >> (8 * UInt64($0))) & 0xFF) }
    }

    /// Data records; emits a definition message the first time each local type is used.
    struct Body {
        var bytes: [UInt8] = []
        private var defined: Set<UInt8> = []

        mutating func message(_ global: Message, local: UInt8, _ fields: [Field]) {
            if !defined.contains(local) {
                bytes += [0x40 | local, 0, 0]                   // definition header, reserved, little-endian
                bytes += le(UInt64(global.rawValue), 2)
                bytes.append(UInt8(fields.count))
                for f in fields { bytes += [f.number, UInt8(f.size), f.type.rawValue] }
                defined.insert(local)
            }
            bytes.append(local)                                 // data header
            for f in fields { bytes += f.bytes }
        }
    }
}
