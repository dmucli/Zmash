import AppIntents
import SwiftData
import ZmashKit

/// Hands Siri and Shortcuts requests to the running app (D100).
@MainActor @Observable
final class IntentRouter {
    static let shared = IntentRouter()

    enum Action: Equatable {
        /// Start this ride now (or set it up on home when the trainer isn't connected).
        case ride(SessionPlan)
        case endRide
    }

    var pending: Action?
    /// A ride set up by Siri while the trainer wasn't connected, for home to show.
    var prepared: SessionPlan?
    /// Set by the app while a ride is on, so a request to start another can say no.
    var riding = false

    /// Hands over a ride to start, or explains why not.
    func ride(_ plan: SessionPlan) throws {
        guard !riding else { throw IntentError.alreadyRiding }
        pending = .ride(plan)
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case alreadyRiding
    case nothingToday

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .alreadyRiding: "You're already riding. End this ride first."
        case .nothingToday: "There's nothing to suggest today."
        }
    }
}

// MARK: Entities

struct WorkoutEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Workout"
    static let defaultQuery = WorkoutQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct WorkoutQuery: EntityQuery, EntityStringQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [WorkoutEntity] {
        identifiers.compactMap { id in WorkoutStore.workout(id: id).map { WorkoutEntity(id: $0.id, name: $0.name) } }
    }
    @MainActor func suggestedEntities() async throws -> [WorkoutEntity] {
        WorkoutStore.all.map { WorkoutEntity(id: $0.id, name: $0.name) }
    }
    @MainActor func entities(matching string: String) async throws -> [WorkoutEntity] {
        WorkoutStore.all.filter { $0.name.localizedCaseInsensitiveContains(string) }.map { WorkoutEntity(id: $0.id, name: $0.name) }
    }
}

struct ClimbEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Climb"
    static let defaultQuery = ClimbQuery()
    let id: String
    let name: String
    let side: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(side)") }
}

struct ClimbQuery: EntityQuery, EntityStringQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [ClimbEntity] {
        identifiers.compactMap { id in RaceStore.climb(id: id).map { ClimbEntity(id: $0.id, name: $0.name, side: $0.side) } }
    }
    @MainActor func suggestedEntities() async throws -> [ClimbEntity] {
        RaceStore.climbs.map { ClimbEntity(id: $0.id, name: $0.name, side: $0.side) }
    }
    @MainActor func entities(matching string: String) async throws -> [ClimbEntity] {
        RaceStore.climbs.filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map { ClimbEntity(id: $0.id, name: $0.name, side: $0.side) }
    }
}

// MARK: Intents

struct StartTodaysRideIntent: AppIntent {
    static let title: LocalizedStringResource = "Start today's ride"
    static let description = IntentDescription("Starts the ride the Today card suggests.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        let prefs = Preferences.shared
        let today = Today.compute(prefs: prefs)
        guard let pick = today.picks.first else { throw IntentError.nothingToday }
        try IntentRouter.shared.ride(Today.plan(for: pick, prefs: prefs))
        return .result()
    }
}

struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a workout"
    static let openAppWhenRun = true
    @Parameter(title: "Workout") var workout: WorkoutEntity

    @MainActor func perform() async throws -> some IntentResult {
        var plan = Preferences.shared.lastPlan
        plan.routeID = nil
        plan.workoutID = workout.id
        try IntentRouter.shared.ride(plan)
        return .result()
    }
}

struct RideClimbIntent: AppIntent {
    static let title: LocalizedStringResource = "Ride a climb"
    static let openAppWhenRun = true
    @Parameter(title: "Climb") var climb: ClimbEntity

    @MainActor func perform() async throws -> some IntentResult {
        var plan = Preferences.shared.lastPlan
        plan.workoutID = nil
        plan.routeID = climb.id
        try IntentRouter.shared.ride(plan)
        return .result()
    }
}

struct EndRideIntent: AppIntent {
    static let title: LocalizedStringResource = "End my ride"
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        IntentRouter.shared.pending = .endRide
        return .result()
    }
}

struct WeekSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "How much did I ride this week?"
    static let description = IntentDescription("Hours, distance and climbing since Monday.")

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let week = Calendar.mondayFirst.dateInterval(of: .weekOfYear, for: .now)!.start
        let rid = Preferences.shared.riderID
        let d = FetchDescriptor<RideSession>(predicate: #Predicate { $0.isComplete && $0.riderID == rid && $0.startedAt >= week })
        let rides = (try? RideStore.context.fetch(d)) ?? []
        guard !rides.isEmpty else { return .result(dialog: "No rides yet this week.") }
        let units = Preferences.shared.units
        let seconds = rides.map(\.activeSeconds).reduce(0, +)
        let km = units.distance(rides.map(\.distanceM).reduce(0, +))
        let up = units.elevation(rides.map(\.elevationGainM).reduce(0, +))
        let text = String(format: "This week: %d h %02d, %.0f %@ and %.0f %@ of climbing, over %d ride%@.",
                          seconds / 3600, seconds / 60 % 60, km, units.distanceUnit, up, units.elevationUnit,
                          rides.count, rides.count == 1 ? "" : "s")
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct ZmashShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartTodaysRideIntent(), phrases: ["Start today's ride in \(.applicationName)",
                                                               "Ride with \(.applicationName)"],
                    shortTitle: "Today's ride", systemImageName: "bicycle")
        AppShortcut(intent: StartWorkoutIntent(), phrases: ["Start \(\.$workout) in \(.applicationName)",
                                                            "Start a workout in \(.applicationName)"],
                    shortTitle: "Start a workout", systemImageName: "chart.bar.fill")
        AppShortcut(intent: RideClimbIntent(), phrases: ["Ride \(\.$climb) in \(.applicationName)",
                                                         "Ride a climb in \(.applicationName)"],
                    shortTitle: "Ride a climb", systemImageName: "mountain.2.fill")
        AppShortcut(intent: WeekSummaryIntent(), phrases: ["How much did I ride this week in \(.applicationName)",
                                                           "My week in \(.applicationName)"],
                    shortTitle: "This week", systemImageName: "calendar")
        AppShortcut(intent: EndRideIntent(), phrases: ["End my ride in \(.applicationName)"],
                    shortTitle: "End ride", systemImageName: "flag.checkered")
    }
}
