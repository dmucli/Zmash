import Foundation
import ZmashKit

// Builds the workout catalog the app bundles (D154): folders of Zwift `.zwo` files → one compact JSON file.
// A file in a subfolder belongs to that folder's collection; one at a folder's top level to "The Sufferfest" when its
// name says so ("Sufferfest - Revolver.zwo"), otherwise to "Community". Runs, distance-based files, unreadable ones and
// duplicates are left out.
//
//   swift run -c release workout-catalog <out.json> <folder> [<folder>…]

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: workout-catalog <out.json> <folder> [<folder>…]\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: args[1])
let roots = args.dropFirst(2).map { URL(fileURLWithPath: $0) }

var entries: [WorkoutCatalogFile.Entry] = []
var seenIDs: Set<String> = []
/// Name + steps, to drop the same workout filed under two collections.
var seenWorkouts: Set<String> = []
var skipped = (run: 0, distance: 0, unreadable: 0, duplicate: 0)

for root in roots {
    let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
        .filter { $0.pathExtension.lowercased() == "zwo" }
        .sorted { $0.path < $1.path }
    for file in files {
        let relative = file.path.dropFirst(root.path.count + 1).split(separator: "/")
        var name = file.deletingPathExtension().lastPathComponent
        let collection: String
        if relative.count > 1 {
            collection = String(relative[0])
        } else if name.hasPrefix("Sufferfest - ") {
            collection = "The Sufferfest"
            name = String(name.dropFirst("Sufferfest - ".count)).trimmingCharacters(in: .whitespaces)
        } else {
            collection = "Community"
        }
        guard let data = try? Data(contentsOf: file), let parsed = ZWOParser.parseFile(data, id: "") else {
            skipped.unreadable += 1
            continue
        }
        guard parsed.isRideable else {
            if parsed.distanceBased { skipped.distance += 1 } else { skipped.run += 1 }
            continue
        }
        var w = parsed.workout
        // The file's own name wins over the file name, except Sufferfest's, whose file names are the titles.
        if collection == "The Sufferfest" || w.name == "Imported workout" { w.name = name }
        let signature = w.name.lowercased() + "|" + w.steps.map { "\($0.seconds):\($0.target)" }.joined(separator: ",")
        guard seenWorkouts.insert(signature).inserted else {
            skipped.duplicate += 1
            continue
        }
        var id = "zc/\(WorkoutCatalogFile.slug(collection))/\(WorkoutCatalogFile.slug(w.name))"
        var n = 2
        while seenIDs.contains(id) {
            id = "zc/\(WorkoutCatalogFile.slug(collection))/\(WorkoutCatalogFile.slug(w.name))-\(n)"
            n += 1
        }
        seenIDs.insert(id)
        w.id = id
        w.summary = ZWOParser.cleanDescription(w.summary)
        let category = WorkoutCatalogFile.category(named: parsed.category) ?? w.inferredCategory
        entries.append(.init(workout: w, collection: collection, author: parsed.author, category: category))
    }
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let data = try encoder.encode(WorkoutCatalogFile(workouts: entries))
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: output, options: .atomic)

let byCategory = Dictionary(grouping: entries, by: \.category).mapValues(\.count).sorted { $0.key < $1.key }
print("\(entries.count) workouts in \(Set(entries.map(\.collection)).count) collections → \(output.path) (\(data.count / 1024) KB)")
print("by kind: " + byCategory.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
print("left out: \(skipped.run) runs, \(skipped.distance) in distance, \(skipped.unreadable) unreadable, \(skipped.duplicate) duplicates")
