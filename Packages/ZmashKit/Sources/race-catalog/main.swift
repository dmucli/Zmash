import Foundation
import ZmashKit

// Builds the race catalog the app bundles: gpx/<year>/<kind>/<race>/*.gpx → one compact JSON file.
// Every file goes through the same GPXParser and RouteBuilder as a GPX the rider imports.
//
//   swift run -c release race-catalog <gpx dir> <out.json>

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: race-catalog <gpx dir> <out.json>\n".utf8))
    exit(2)
}
let root = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
func folders(_ url: URL) -> [URL] {
    ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

/// "stage-05.gpx" → 5; a one-day race's "route.gpx" → 1.
func stageNumber(_ file: URL) -> Int {
    Int(file.deletingPathExtension().lastPathComponent.filter(\.isNumber)) ?? 1
}

var races: [Race] = []
var problems: [String] = []
/// Famous climbs by id (one per climb and side), keeping the longest profile found.
var famous: [String: FamousClimb] = [:]

for yearDir in folders(root) {
    guard let year = Int(yearDir.lastPathComponent) else { continue }
    for kindDir in folders(yearDir) {
        guard let kind = Race.Kind(rawValue: kindDir.lastPathComponent) else {
            problems.append("unknown race kind \(kindDir.path)")
            continue
        }
        for raceDir in folders(kindDir) {
            let slug = raceDir.lastPathComponent
            let files = ((try? FileManager.default.contentsOfDirectory(at: raceDir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "gpx" }
            var stages: [Stage] = []
            let (name, country) = RaceNames.name(slug)
            for file in files {
                guard let data = try? Data(contentsOf: file), let route = GPXParser.parse(data, id: file.path) else {
                    problems.append("no profile in \(file.path)")
                    continue
                }
                let number = stageNumber(file)
                stages.append(Stage(number: number, elevations: route.elevations.map { Int($0.rounded()) }))
                let source = kind == .classic ? "\(name) \(year)" : "\(name) \(year) · stage \(number)"
                for climb in FamousClimbs.extract(track: GPXParser.track(data), source: source) {
                    // One entry per side: keep the longest profile, and a town name over a compass direction.
                    if let (key, kept) = famous.first(where: { $0.value.sameSide(as: climb) }) {
                        guard climb.elevations.count > kept.elevations.count else { continue }
                        famous[key] = nil
                        var better = climb
                        if climb.side.hasPrefix("from the"), !kept.side.hasPrefix("from the") {
                            better.side = kept.side
                            better.id = kept.id
                        }
                        famous[better.id] = better
                    } else {
                        famous[climb.id] = climb
                    }
                }
            }
            guard !stages.isEmpty else { continue }
            if RaceNames.known[slug] == nil { problems.append("no proper name for \(slug) (title case used)") }
            races.append(Race(id: "\(year)/\(slug)", name: name, year: year, kind: kind, country: country,
                              stages: stages.sorted { $0.number < $1.number }))
        }
    }
}

let order = Race.Kind.allCases
races.sort {
    ($0.kind == $1.kind)
        ? ($0.year != $1.year ? $0.year > $1.year : $0.name < $1.name)
        : order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)!
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let climbs = famous.values.sorted { ($0.country, $0.name, $0.side) < ($1.country, $1.name, $1.side) }
let data = try encoder.encode(RaceCatalog(races: races, climbs: climbs))
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: output)

for race in races {
    let routes = race.stages.map(race.route)
    let km = routes.map(\.distanceM).reduce(0, +) / 1000
    let up = routes.map(\.ascentM).reduce(0, +)
    let climbs = routes.flatMap { Climbs.find($0) }
    let hc = climbs.filter { $0.category == .hc }.count
    let name = "\(race.name) \(race.year)".padding(toLength: 42, withPad: " ", startingAt: 0)
    print(String(format: "%@ %2d stage%@  %5.0f km  %6.0f m  %3d climbs (%d HC)", name,
                 race.stages.count, race.stages.count == 1 ? " " : "s", km, up, climbs.count, hc))
}
print("")
for climb in climbs {
    let r = climb.route
    print(String(format: "%@  %4.1f km  +%4.0f m  %4.1f %%  %@", ("\(climb.name) · \(climb.side)" as NSString).padding(toLength: 48, withPad: " ", startingAt: 0),
                 r.distanceM / 1000, r.ascentM, r.averageGrade, climb.source))
}
let found = Set(climbs.map(\.name))
let missing = FamousClimbs.summits.map(\.name).filter { !found.contains($0) }
if !missing.isEmpty { print("not in the files: " + missing.joined(separator: ", ")) }
problems.forEach { print("! \($0)") }
print(String(format: "%d races, %d stages, %d climbs, %.2f MB → %@", races.count, races.map(\.stages.count).reduce(0, +), climbs.count,
             Double(data.count) / 1_048_576, output.path))
