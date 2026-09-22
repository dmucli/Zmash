import Foundation
import HealthKit
import ZmashKit

/// Phase 3: save rides to Apple Health as indoor cycling workouts (write-only; nothing is read).
@MainActor
enum HealthExport {
    static let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static let quantityTypes: [HKQuantityTypeIdentifier] = [
        .activeEnergyBurned, .distanceCycling, .heartRate, .cyclingPower, .cyclingCadence,
    ]

    static var shareTypes: Set<HKSampleType> {
        Set(quantityTypes.map { HKQuantityType($0) } + [HKObjectType.workoutType()])
    }

    /// Asks for permission to write workouts. Returns false if Health isn't available.
    static func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: [])
            return true
        } catch {
            return false
        }
    }

    /// Writes the ride: workout + total energy and distance + 5 s power, cadence and heart-rate samples.
    /// Sample times are start + active seconds (pauses are folded out).
    static func save(_ ride: FinishedRide) async throws {
        guard isAvailable, ride.summary.activeSeconds > 0 else { return }
        let start = ride.startedAt
        let end = start.addingTimeInterval(TimeInterval(ride.summary.activeSeconds))

        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: start)

        var samples: [HKSample] = [
            HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                             quantity: HKQuantity(unit: .kilocalorie(), doubleValue: ride.summary.kcal),
                             start: start, end: end),
            HKQuantitySample(type: HKQuantityType(.distanceCycling),
                             quantity: HKQuantity(unit: .meter(), doubleValue: ride.summary.distanceM),
                             start: start, end: end),
        ]
        for point in SampleSeries.buckets(ride.samples, bucketSeconds: 5) {
            let t0 = start.addingTimeInterval(point.minute * 60)
            let t1 = min(t0.addingTimeInterval(5), end)
            guard t1 > t0 else { continue }
            if point.powerW > 0 {
                samples.append(HKQuantitySample(type: HKQuantityType(.cyclingPower),
                                                quantity: HKQuantity(unit: .watt(), doubleValue: point.powerW),
                                                start: t0, end: t1))
            }
            if let cadence = point.cadenceRpm {
                samples.append(HKQuantitySample(type: HKQuantityType(.cyclingCadence),
                                                quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: cadence),
                                                start: t0, end: t1))
            }
            if let hr = point.heartRateBpm {
                samples.append(HKQuantitySample(type: HKQuantityType(.heartRate),
                                                quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: hr),
                                                start: t0, end: t0))
            }
        }
        try await builder.addSamples(samples)
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }
}
