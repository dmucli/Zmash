# CLAUDE.md

Zmash is a SwiftUI indoor-cycling app. It's made for an iPad on the handlebars in landscape, and also runs on iPhone and Mac, with a Watch app and widgets. It drives a smart trainer and a Zwift Ride controller over Bluetooth (virtual shifting, gradients, ERG), with no Zwift and no server. See README.md for the feature list.

## Commands

```sh
make test          # ZmashKit tests (swift test, macOS, fast): run after any change in Packages/ZmashKit
make test-app      # the app's tests (ZmashTests) in the iPhone Simulator
make build-sim     # regenerate the project (XcodeGen) and build for the Simulator: the compile check
make races         # rebuild Zmash/Resources/Races/races.json from gpx/ (local only)
make workouts      # rebuild Zmash/Resources/Workouts/catalog.json from the .zwo folders in external sources/ (local only; Debug builds only, D166)
```

- **One test:** `cd Packages/ZmashKit && swift test --filter FITTests/intervalsBecomeLaps`.
- **Toolchain:** the Makefile sets `DEVELOPER_DIR` to Xcode, so use it rather than bare `xcodebuild`.
- **The Xcode project is generated:** `Zmash.xcodeproj` comes from `project.yml`. Never edit it; new files are picked up by `make build-sim`.
- **CI** (`.github/workflows/ci.yml`) runs the kit tests, the Simulator build and the app tests.

## Architecture

- **`Packages/ZmashKit`:** all logic that doesn't need UIKit, Bluetooth or SwiftData, tested on macOS. That covers:
  - protocols: FTMS, Zwift Ride/Play/Click, Wahoo, Tacx FE-C, sensors, heart rate;
  - physics and gears; terrain and drawn courses;
  - `Workout`, `WorkoutLibrary`, the `.zwo` parser and writer;
  - `Route` and the race catalog; `TrainingPlan`, `Campaign` and `Coach`;
  - `FITWriter`, `SessionSummary`/`Lap`, zones, records, and the intervals.icu calendar decoding.
  - **Put new logic here, with a test, whenever it can live without the app.**
- **`Zmash/`, the app:**
  - `Devices/`: CoreBluetooth clients. `DeviceHub` is the single entry for trainer, controller and sensor state.
  - `Session/`:
    - `SessionEngine` is the live ride: a 10 Hz loop, the trainer target, samples each second, pauses, the coach and sounds;
    - the stores: `WorkoutStore`, `RouteStore`, `RaceStore`, `PlanStore` with `PlanChanges`, `CampaignStore`, `Favourites`;
    - `Today` (suggestions for Siri and widgets), the Live Activity, and the Watch link.
  - `Persistence/`: `RideSession` (SwiftData, versioned schema, with samples as encoded `RideSample`s), backup and restore, Health.
  - `Export/`: FIT export, uploads (`Uploads.swift`), and `PlannedWorkouts` (intervals.icu calendar).
  - `App/`: `ZmashApp`/`RootView`, `Preferences`, `Riders`, Siri intents, and `DebugLaunch`.
    - `RootView` swaps pages (`AppPage`: home, history, devices, settings), not sheets.
    - `Preferences.shared` is the one `@Observable` settings object. Per-rider values are swapped in by `Preferences.switchRider`, and some are keyed by rider id in UserDefaults.
  - `UI/`:
    - `Home/`: `HomeView`, its four cards, and the ride pages (`RidePage` shell, `PickerCard`, `SelectionBar`).
    - `Faces/`: the ride-screen faces.
    - `DesignSystem/`: tokens and components.
    - `Setup/`: first-run setup, previews, `PlanView`, `CampaignView`, the builder, race views and `RoutePart`.

### Id conventions (they're persisted: don't change them)

- **Routes:**
  - `race/<year>/<race>/<stage>`, `climb/<slug>`, or imported (`file-…`, from links too);
  - old ids like `ventoux` still resolve (`RouteStore.legacyIDs`);
  - a part of a route is `<base>#<fromM>-<toM>` (`RouteStore.segmentID`/`split`).
- **Plans:** Zmash's own (`ftp-build`), or `zc-<collection>` for the catalog's (`zc-ftp-builder`), with no slash.
- **Workouts:**
  - library ids (plans refer to them);
  - `plan/<plan>/<week>-<index>` (a plan session);
  - `icu/<event>` (intervals.icu, kept in Application Support/Planned);
  - `zwo-…` (imported or built);
  - `zc/<collection>/<name>` (the bundled catalog, `WorkoutCatalog`: standalone workouts, and plan sessions shown only on the Plan page).
- **Persisted `Codable` types** (`RideSample`, `Workout.Step`, `SessionPlan`, enrolments): add fields as optionals, so old data still decodes.

## Design and copy

- **The UI follows the design system:** `design/Zmash Design System/`. Its readme and `Zmash Tablet App.dc.html` (the prototype) are the reference for layout and components.
  - Tokens: `Design.Palette` / `Font` / `Space` / `Radius` / `Motion`, `.textStyle`, `.monoLabel`, `.card()`, `CardBackground(hero:)`.
  - Shapes: pills for buttons, chips and tabs; 16-pt cards with 1-pt borders and no shadows; a vermilion ring for "chosen".
  - Don't add bib numbers (01, 02…) to cards: the user removed them.
- **Voice:** a calm teammate. Short, direct, second person, sentence case, no exclamation marks or emoji. Mono uppercase is for small labels only.
- **Comments:** explain *why*. Follow the surrounding density: doc comments on types and non-obvious members, often citing the decision (`(D151)`).

## Working conventions

- **Record every change** in `DECISIONS.md`, as the next **D-number** (the last is D168). Add checks that need real hardware to `TESTING.md`.
- **Commits:** small, one per decision, with a message saying what and why.
- **Licences:** `external sources/` holds other projects for reference (Auuki is AGPL). Re-implement ideas from public specs, never copy code.
- **Checking UI changes:** build, then take Simulator screenshots using `DebugLaunch`'s launch arguments. The main ones:
  - opening a screen or page: `-ZmashScreen history|settings|devices|faces`, `-ZmashOpen plan|free|workout|route` with `-ZmashTab <tab>` (`-ZmashOpen workout` alone opens the chosen workout's details; a tab opens the grid);
  - choosing the ride: `-ZmashHomePlan auto|manual|draw` with `-ZmashWorkout <id>` or `-ZmashRoute <id>`;
  - seeded data: `-ZmashSeedHistory YES`, `-ZmashEnrolPlan YES -ZmashPlan <id>`, `-ZmashPlanFinished YES`, `-ZmashIntervalsFixture YES`;
  - riding: `-ZmashAutostart auto` (the demo trainer), `-ZmashFace <face>`, `-ZmashHeroTaps <n>` (as if the big number had been tapped n times), `-ZmashLandscape YES` (an iPad on its side, drawn rotated in the screenshot).
  - Don't run `make test-app` while screenshotting on the same simulator: terminating the app kills the test run.
- **What the Simulator can't check:** Bluetooth doesn't work there, so the demo devices stand in. Real-hardware behaviour goes into TESTING.md.
