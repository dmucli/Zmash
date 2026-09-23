# Zmash — Decisions

A running record of the choices made while building Zmash, why they were made, and what would change them.
`BRIEF.md` is the spec; this file explains where and why the build follows or departs from it.

Status legend: **Verified** (checked on hardware or in the Simulator), **Tested** (unit tests), **Unverified** (compiles, not yet exercised).

---

## Product decisions (from the user)

| # | Decision | Date |
|---|---|---|
| U1 | Zwift Ride controllers stay on firmware **1.2.0**. Never update past it (Zwift may lock third-party access, as it did with the Click V2). | 2026-09-22 |
| U2 | **km/h** by default; mph in Settings. | 2026-09-22 |
| U3 | The ride clock starts on the **first pedal stroke** after the 3-2-1 countdown. | 2026-09-22 |
| U4 | Pause/end also on other Ride buttons: pause on A, Z and a short press of either on/off; end on hold B or hold left lower button. | 2026-09-22 |
| U5 | Manual grade range is **−10 % … +16 %** (no steeper descents). | 2026-09-22 |
| U6 | Gear count is configurable: **3 / 6 / 9 / 12 / 18 / 24** (default 24). | 2026-09-22 |
| U7 | Haptics were "a little too much": one buzz per burst of shifts. | 2026-09-22 |
| U8 | A close button is required on the ride screen (it's impossible to leave before pedalling otherwise). | 2026-09-22 |
| U9 | Keep developing from VS Code; Xcode only for on-device debugging. | 2026-09-22 |

## Platform & tooling

**D1. Native iPad app; no web version.** Verified.
Web Bluetooth doesn't exist on iPadOS (every browser there uses WebKit), so a web app can't talk to the devices on the iPad. The native app covers the Mac through "Designed for iPad" (D30).

**D2. Swift 6, SwiftUI, CoreBluetooth, SwiftData, iPadOS 18+. No third-party runtime dependencies.** Verified.
A hand-rolled protobuf varint reader/writer (`ProtoWire`) replaces SwiftProtobuf: Zwift messages use a handful of fields.

**D3. Protocol and physics logic lives in a Swift package (`Packages/ZmashKit`), free of UIKit/CoreBluetooth.** Tested.
It builds and tests with `swift test` on macOS from VS Code, with no simulator. The app target keeps only device I/O and UI.

**D4. XcodeGen (`project.yml`) generates the Xcode project; `Zmash.xcodeproj` is not hand-edited or committed.** Verified.
A `Makefile` wraps everything (`test`, `build-sim`, `build-device`, `build-mac`, `install`). `DEVELOPER_DIR` points at the full Xcode so `xcode-select` doesn't matter.

**D5. bikecontrol is used as a protocol reference only; no code is copied.** Its Non-Commercial licence forbids reuse in some contexts, and its trainer code is private anyway. Protocol facts were cross-checked against Makinolo's write-ups and the Zword byte captures.

**D6. Debug-only launch arguments drive the Simulator for screenshots** (`-ZmashAutostart`, `-ZmashEndAfter`, `-ZmashSeedHistory`, `-ZmashScreen`, `-ZmashLandscape`, `-ZmashCompactWidth`, `-ZmashPiP`). Compiled out of release builds. The headless Simulator can't be tapped or rotated, and iPadOS refuses programmatic rotation, so landscape is previewed by laying the app out landscape inside a rotated frame.

## Devices & protocols

**D7. Ride button masks follow `zwift_ride.dart`, not bikecontrol's generated protobuf enum.** Tested.
The two disagree. Decoding the Zword sketch's raw byte captures bit by bit matches `zwift_ride.dart` (e.g. Z = 0x80, left upper = 0x100). All 16 captures are unit tests.

**D8. The trainer defaults to FTMS; the Zwift trainer protocol is opt-in (Auto / Zwift).** Verified (FTMS in use on the user's KICKR CORE 2).
FTMS is the documented, guaranteed path. The Zwift protocol (native virtual shifting on the trainer) is implemented from Makinolo's write-up and bikecontrol's public protobuf layout, and decodes Makinolo's real sample packet. It hasn't been confirmed on the CORE 2. In Auto mode the app waits 4 s for Zwift riding data, then falls back to FTMS.

**D9. Virtual shifting over FTMS uses an "effective grade".** Verified by feel ("very gradual, which is nice").
The grade sent to the trainer makes its fixed-gear flywheel demand the power the virtual gear needs at the current cadence. It's low-passed (τ ≈ 1 s), but shifts apply immediately. It's clamped to −10 … +16 %. Below 20 rpm the raw terrain grade is sent.

**D10. ERG fallback is available but off by default** (Devices → Advanced → "Shift with ERG"). Unverified.
Brief §6.3's last resort: the trainer holds the power the gear needs, computed from cadence × ratio. ERG lags and can spiral at low cadence, so it's never the default.

**D11. One control-point operation in flight; targets are replaced, not queued.** FTMS requires waiting for each response. Only the latest grade/power target matters, so a pending one is overwritten. Writes are throttled to 4 Hz and a threshold (0.1 % grade, 3 W power).

**D12. Remembered devices reconnect through pending `connect` requests, which never time out on iOS.** Verified (the Ride and trainer reconnect after power-cycling).

**D13. Gear table: 24 Zwift-like ratios from 0.75 to 5.49; start at gear 12 (2.40).** An approximation of Zwift's table (small steps low, bigger steps high). Other gear counts sample the same curve, so the range never changes; only the step size does. Start gear = closest to 2.40.

**D14. Button handling is a pure, clock-injected mapper driven by a configurable `ButtonMap`.** Tested.
- Commands have a trigger: press, repeating (grade, 0.4 s delay then 4 Hz), or hold (end ride, 1 s).
- **On/off buttons only fire on a short release (< 0.6 s)** and can't be given repeat or hold actions, because holding them powers the controller off.
- Paddles use hysteresis (press ≥ 25, release < 15).

**D15. Other controllers (phase 4): Zwift Play (1.x both sides, and firmware 2), Zwift Click v1.** Tested (decoders), Unverified on hardware.
All use the Ride's unencrypted service and "RideOn" handshake:
- Play 2.x speaks the Ride protocol.
- Play 1.x sides are separate peripherals with keypad opcode 0x07.
- Click v1 uses opcode 0x37 (+ acts as right upper = harder, − as left upper = easier).

Everything is translated into the Ride's button vocabulary, so the same mapping and settings apply. Up to two controllers can be paired (both Play sides).

**D16. Zwift Click v2 is not supported.** Zwift locks it to third-party apps: it needs a 24 h "unlock" through the Zwift app, which would mean reverse-engineering Zwift's handshake. It's out of scope.

**D17. Other trainers (phase 4): any FTMS trainer works; Cycling Power–only trainers give metrics without control.** Pairing classifies by advertised service (FTMS 0x1826 or Cycling Power 0x1818), not by brand.

**D18. Heart-rate straps (phase 3): the standard Heart Rate service (0x180D/0x2A37), as an optional third device.** Unverified on hardware.
Heart rate relayed by the trainer's FTMS data is used when no strap is paired. It's stale after 5 s. A reading of 0 (no skin contact) is ignored.

## Riding model

**D19. Displayed speed always comes from Zmash's own physics model**, not the trainer, so every trainer and protocol behaves the same.
- CdA 0.32, Crr 0.004, ρ 1.225, rider (Settings) + bike 9 kg, +1 kg of wheel inertia.
- Sub-stepped integration, with gaps clamped to 2 s.
- It coasts downhill and stops on the flat.

Tested: 200 W on the flat gives ≈ 34 km/h.

**D20. Calories = kJ of mechanical work.** The standard cycling convention (≈ 24 % gross efficiency × 4.184 ≈ 1).

**D21. Auto-pause after 5 s without pedalling — except while coasting downhill** (grade < −1 % and speed > 5 km/h). Otherwise every descent would pause the clock. After 60 s without the trainer, the ride auto-pauses.

**D22. Auto terrain is time-based and seeded.** Tested.
- Grade is a function of active seconds, so the profile always fits the chosen duration exactly.
- The seed is stored per ride ("Ride this again" replays it).
- Warm-up and cool-down are built in; grade ramps are ≤ 0.5 %/s.
- Harder effort climbs more; Mountain has long climbs (≥ 25 % of the body).
- Free ride + Auto appends 10-minute blocks.

**D23. Watts show a 3 s average by default** (instant or 10 s in Settings), with single-sample spikes above 3× the median dropped.

## Screens

**D24. One ink, two backgrounds, one grade-driven accent.** Near-black `#0B0B0C` and near-white `#F5F5F2`. Text ink sits on the flat and shifts to amber on climbs and blue on descents (full hue at ±8 %). Everything is tinted with ink, not system blue or green. Lucide icons at 1.5 px stroke. No emoji or motivational copy. Verified in Simulator.

**D25. Live numbers don't animate.** Verified. Number-roll and crossfade animations blurred values that change 10×/s. Only the countdown animates, and only the waiting clock pulses.

**D26. The ride screen renders from a snapshot (`RideReadout`) and a `DisplayConfig`.** Verified. This powers customisation with a live preview in Settings:
- big number;
- four corner slots;
- typeface (rounded, standard, mono);
- weight and size;
- grade colour on/off.

**D27. The close button sits above every overlay.** Verified. The countdown overlay used to cover it. Before the first pedal stroke it leaves immediately; afterwards it confirms and opens the save screen.

**D28. Compact (Split View / Slide Over) layout is a 2×3 grid sized from the column width.** Verified in a 375 pt column.

**D29. Picture-in-Picture overlay renders a SwiftUI card into an `AVSampleBufferDisplayLayer` twice a second.** Verified on the iPad (2026-09-22).
- It follows UIPiPView's working setup: plain playback audio session, finite 24 h time range, and layer sized in `layoutSubviews`.
- The −1003 failure was a zero-sized layer: `updateUIView` ran before layout.
- In the Simulator it now starts and floats over other apps, but the window is black, which the reference library says is a Simulator limitation.
- Still to confirm: whether YouTube's sound plays normally with the window up (the audio session no longer mixes).

**D30. Mac: "Designed for iPad" builds (`make build-mac`) but is launched from Xcode** (destination "My Mac (Designed for iPad)"). macOS only launches it when Xcode installs it; opening the product directly fails with "incorrect executable format". Nothing Mac-specific was built beyond keyboard shortcuts.

## Data

**D31. Samples are stored as one encoded blob per ride**, not one SwiftData row per second: they're only read whole, and it keeps the 10 s autosaves cheap. New optional fields (heart rate) decode from older rides.

**D32. Crash recovery offers Recover (opens the save screen with the autosaved data) or Discard; it doesn't resume the ride.**

**D33. FIT export instead of direct Strava upload.** Tested (decoded by the independent `fitdecode` parser: CRC, 1 Hz records, lap/session/activity, indoor cycling). Direct Strava upload would need a registered Strava API app with a client secret in the app. The FIT file shared to Strava/Garmin/TrainingPeaks covers it with no account plumbing.

**D34. Apple Health: opt-in, write-only.** Signing Verified, saving Unverified.
- Each ride is saved as an indoor cycling workout with energy, distance, and 5 s power, cadence and heart-rate samples.
- A free Personal Team *can* sign HealthKit (confirmed with a signed device build).
- The Simulator can't pre-grant Health permission, so the save itself is untested until it runs on the iPad.

**D35. After 10 min in the background while not riding (or paused), devices are released; they reconnect on return** (brief §11). This saves controller and strap batteries.

**D36. Settings apply live.** Button mapping, display and theme changes take effect mid-ride. Gear count, rider weight and watts smoothing apply from the next ride, because they're captured when the ride starts.

## Ride faces (design/Zmash Faces.dc.html)

**D37. Faces are native SwiftUI ports of the Claude Design prototype, laid out on its 1194×834 canvas and scaled.** Verified in Simulator.
- Canvas: fonts, sizes, positions, palettes and per-face logic follow `design/RideFace.dc.html` exactly.
- Scaling: within 3 % of the design aspect (e.g. the 1210 pt iPad Pro 11" M5) the canvas fills edge to edge; beyond that (13") it letterboxes in the face's background rather than crop content.

**D38. Faces: Paper, Aura, Night, Horizon, Kinetic** (the user's priority). Chronograph, Tape and Segments are skipped (user decision, 2026-09-22); they stay in the design file for reference only.

**D39. The original dashboard is kept as a sixth face, "Classic".** The customisation built earlier (big number, slots, typeface, size, grade colour, wind) lives on as that face's settings, and it's also the Split View / Slide Over fallback for every face.

**D40. Fonts are bundled and open-licensed.** Archivo, Newsreader, Outfit and Roboto Flex come from google/fonts, SIL OFL, with the licences in `Zmash/Resources/Fonts`; they add 2.9 MB.
- Variable axes (weight, width, slant, optical size) are set through CoreText, so Kinetic's live weight/width/slant and Aura's power-driven weight work as designed.
- Fonts are cached, with quantised axis values.

**D41. Face telemetry lives in `ZmashKit` (`FaceTelemetry`) and is unit-tested.** It covers:
- crank phase (for Aura's breathing) and 3 s power;
- 5 s trends;
- the magic-moment events.

The events follow the prototype's rules, tightened for real rides:
- **Shift:** always fires, lowest priority.
- **Kilometre or mile:** shows the *split* for that unit rather than the average.
- **Summit:** only after a climb of ≥ 30 s above 0.6 %.
- **Session best:** above 1.25 × FTP, at most every 30 s.

**D42. FTP defaults to 200 W** (Settings → Rider), driving Coggan's 7 zones and the zone colour ramp. The prototype used 240.

**D43. The terrain behind the faces:** the next 5 minutes of auto terrain, or, for manual grade, the last 5 minutes ridden (brief option), normalised like the prototype.

**D44. Mid-ride switching: D-pad left/right (new defaults) and ←/→ on a keyboard cycle a rotation; the default rotation is Paper · Aura · Horizon, as in the prototype's shortlist.** It's editable per face in the gallery ("In D-pad rotation"). A 1.2 s name tag and a 300 ms cross-fade show the change.

**D45. Faces own their state screens** (countdown, pedal to start, paused, trainer lost, ride complete) in their own typeface, per the prototype. On faces, the Classic countdown/pause overlays are off. The done state adds only the Keep riding / Finish buttons.

**D46. The global wind layer only applies to Classic.** Night has its own speed-driven streaks, and the other faces have their own motion. "Face motion: Calm" (or Reduce Motion) stills Aura's breathing and thins Night's streaks.

**D47. The gallery's live preview is the prototype's simulator, ported (`FaceDemo`).** Each face moves as intended, including shifts, kilometres, summits and bests.

**D48. Training metrics are pure functions in `ZmashKit` (`Training`), computed on save and cached on the ride.** Power curve (best average for 5 s … 1 h), normalized power (30 s rolling average, fourth-power mean), IF and TSS. Rides saved before this get their metrics filled in once, the first time Progress is opened.

**D49. FTP is estimated, never changed behind your back.** Two sources:
- best 20-minute power × 0.95, from the last 90 days;
- a ramp test: best 1-minute power × 0.75.

An estimate is only offered when it differs from the current FTP by more than 3 %, and it takes one tap (end-of-ride summary, or History → Progress).

**D50. Workouts are steps of `steady` / `ramp` / `free`, expressed as a fraction of FTP.** They never store watts, so changing FTP re-scales every workout. The built-in library is nine workouts (endurance through sprints, plus the ramp test). `.zwo` files import into the same model (SteadyState, Warmup, Cooldown, Ramp, IntervalsT, FreeRide, MaxEffort); anything else in the file is ignored.

**D51. A workout replaces the duration and terrain settings**, because it defines both. The ramp test is open-ended (it ends when you stop), so it has no "done" prompt.

**D52. Two ways to ride a workout, chosen at setup:**
- **ERG** (FTMS and demo only): the trainer holds the target whatever gear you're in, and the shifters change the intensity by 5 % a press (50–150 %), since gears do nothing in ERG.
- **Gradient:** the target becomes the gradient at which it would be steady-state at 20 km/h (clamped −2…12 %, eased with a 3 s time constant). You hold the power yourself, shifting as on a climb. This is the fallback when the trainer can't hold a target (the Zwift trainer protocol has no ERG here).

**D53. The workout layer is one component shared by every face**, not a per-face design: a dark pill at the top with the step, the target, how far off it you are, the time left, what's next, and the whole workout as a strip with a playhead. The per-face treatments sketched in `DESIGN.md` were dropped — five variants of the same information, redrawn per face, is a lot of surface for something you read mid-interval, and a consistent position is easier to find at effort.

**D54. Progress is a third tab in History**, not a new screen: FTP and w/kg, the power curve (all-time vs the last 6 weeks, with a table view), weekly load (TSS) and weekly time as separate charts — never two scales on one axis.

**D55. The summary postcard is set like the Paper face, not like the face you rode.** One card design that always looks right beats five, and Paper is the legibility reference. It shows a power trace for flat rides and the elevation profile when there's something to climb. It's a PNG shared from the end-of-ride summary and from any ride in History.

**D56. A route is an elevation profile resampled every 100 m, ridden by distance.** Grade comes from the 100 m the rider is on, clamped to −10…16 % (U5), and imports are smoothed twice with a 3-point average so GPS elevation noise doesn't become a jackhammer on the trainer. A ride on a route has no planned time: it ends when the distance is covered, and "remaining" becomes an estimate at the current pace.

**D57. GPX and FIT are both read in `ZmashKit`.** GPX takes `trkpt`/`rtept` with `ele` and measures distance with haversine; the FIT reader walks definition and data messages and takes the `record` distance and altitude, falling back to position when a file has no distance. Files that turn up under the wrong extension are tried both ways. Anything under 500 m, or with no elevation, is refused with a message rather than imported empty.

**D58. The bundled climbs are approximations, and say so.** Alpe d'Huez, Ventoux (Bédoin), Stelvio (Prato), Tourmalet (Luz) and Mortirolo (Mazzo) are built from published kilometre-by-kilometre gradients, scaled so total ascent matches the published figure, plus two invented flat/rolling routes. Gradients ease across kilometre boundaries so the trainer never steps. The word "approximate profile" is on the card and in the ride HUD; survey data isn't worth the download.

**D59. The ghost is the quickest completed attempt at the same route**, rebuilt from that ride's samples (1 Hz speed integrates to distance, giving the time at each 100 m). It shows as seconds ahead or behind, and only after 50 m. An attempt counts as complete at 95 % of the route's distance.

**D60. Routes reuse the workout layer's slot and shape** rather than changing the faces: name, ghost, distance to go, the whole profile with a playhead, altitude and distance to the summit. Horizon does get the real route, because every face's terrain strip now draws the next 3 km of it, and the sky follows distance rather than time.

**D61. A ride is one of three things — free, a workout or a route — chosen by one control at the top of setup.** They're mutually exclusive: each supplies the gradient, and two can't.

**D62. Distance, climbing and calories are mirrored onto the engine each tick.** They used to be read straight off the speed model, which is `@ObservationIgnored`, so a view that read only those (the route HUD) never redrew. Anything the UI reads has to be observed state.

**D63. Uploads use your own credentials, and there is no Zmash server.** Strava needs an API application of your own (client ID and secret, callback `zmash://strava`, OAuth through `ASWebAuthenticationSession`); intervals.icu needs your athlete ID and API key. Tokens and secrets live in the keychain, never in UserDefaults. Both services receive the same FIT file the share sheet exports, so the export stays the fallback when a service is down. Auto-upload is off by default.

**D64. iCloud sync is not built.** SwiftData + CloudKit needs the paid Apple Developer Program, which you've declined. Rides stay on the iPad, backed up by iTunes/iCloud device backup, and the FIT export is the way out.

**D65. TrainingPeaks is dropped.** Its upload API is partner-only; there's no personal-use path. intervals.icu covers the same ground for free and takes the same file.

**D66. Apple Watch heart rate and Live Activities are deferred, not refused.** The watch app needs a second target and a watch to test on; a Live Activity duplicates the floating window, which already works. Both stay in the parking lot.

**D67. Every face is customisable, in two ways only: its palette and its secondary numbers.** Layout and typeface stay fixed — customising Paper shouldn't be able to turn it into Kinetic. Each face ships with three or four palettes (Paper: Newsprint, Blueprint, Moss, Ink; Aura: Zones, Ember, Tide, Graphite; Night: Ice, Ember, Lime, Violet; Horizon: A day, Long dusk, Paper sky; Kinetic: Press, Signal, Blueprint), each with a light and a dark version. Classic keeps its own, deeper customisation and links to it.

**D68. Slots are typed metrics, not free text.** Sixteen choices (including "Nothing"), each knowing its own value, its short name and its unit, so a face can label them in its own voice: Paper and Kinetic name them, Night and Horizon write the unit inline. Slot counts are per face (Paper 5, Aura 5, Kinetic 5, Horizon 3, Night 3), and saved settings are padded or trimmed if a face ever changes shape.

**D69. Unset means original.** A face with no saved style is drawn exactly as designed, and "Reset" removes the entry rather than writing defaults. Styles live in `Preferences` as one dictionary keyed by face.

**D70. Customising happens in the gallery, not in Settings.** You're already looking at the face, full screen and moving, so the sheet edits it live behind you.

**D71. Home reads top to bottom in the order you use it: connections, then your ride, then Start.** The old screen was one 640-pt column centred on a 1194-pt display, with connections last, a face preview in the middle and Start below the fold. Now:
- **Connections** first, as three cards (trainer, controller, heart rate), each saying plainly what state it's in and opening Devices.
- **Your ride** below: options on the left, and on the right a preview of what they produce (the generated course, the workout's shape and load, the route's profile, or how manual gradient works).
- **A Start bar pinned to the bottom** that never scrolls, naming what's about to start. Without a trainer it says so and becomes "Connect trainer" rather than a dead grey button.

The face preview left home: choosing a face is a setting, reached from Settings → Faces. Nothing decorative was added (no greeting, no weekly totals) — home is for starting a ride. In Split View it collapses to one column with the same pinned bar.

**D72. Draw is a third kind of free-ride terrain: you sketch the hill's silhouette with a finger, and it spans the whole ride.** The drawing is 64 heights, smoothed, then turned into gradients scaled so its steepest climb is Effort's maximum (Easy 4 %, Medium 7 %, Hard 10 %); descents follow the same scale but never pass −10 % (U5). A sketch is judged by its shape, not its pixel height, so any drawing rides sensibly. On an open-ended ride the drawing repeats every 30 minutes. It is auto terrain underneath (the D-pad still biases it, faces show what's ahead), it's kept when you switch away and back, and it's saved with the ride so "Ride this again" brings it back. Dragging again repaints only what the finger crosses; Clear starts from flat.

**D73. Every face plays its own version of each moment, within the brief (DESIGN.md §7).** Eight moments: start (first pedal stroke), shift, kilometre, summit, session best, sprint (crossing 150 % FTP, at most once every 30 s), pause and finish. Each is triggered by something the rider did, lasts at most 2.2 s, and plays one at a time; there is no idle animation.
- **Built from one shared toolkit, recipes per face:** rings, flashes, sweeps, print stamps, type echoes, roadside posts, rising motes, lens lines. Paper stays in print (stamps, registration marks, an ink roller at the start). Aura spreads light through its field. Night's light is additive. Horizon has morning rising, markers passing and the view opening at the summit. Kinetic's moments are type.
- **Smooth at any data rate:** a moment is drawn from its age alone, on its own 60 fps clock that stops when the moment ends.
- **Pause:** the face rests — colour drains and it dims — and pedalling brings it back.
- **Calm motion / Reduce Motion:** only the still effects (flashes, stamps, marks, underlines) remain, as fades.
- **Previews:** in the face gallery, a bar plays any moment on the sample ride, and a Showreel plays them all in turn.

**D74. Real races ship as a compact catalog, not as GPX.** The 159 GPX files in `gpx/` (83 MB, 30 races: Grand Tours, 2026 stage races and classics) stay on your Mac and are git-ignored. `make races` runs the `race-catalog` tool, which processes every file exactly as a GPX you import yourself (`GPXParser` then `RouteBuilder`: 100 m points, smoothed), and writes one 0.9 MB JSON file that the app bundles. The files carry no names, so names and countries come from a table keyed by folder, which restores what the slugs lost ("li-ge-bastogne-li-ge" becomes Liège–Bastogne–Liège). Stages have numbers but no town names, since the data doesn't have them.

**D75. Estimated time is ridden at 70 % of your FTP through the ride's own road model**, at a steady speed per 100 m, capped at 80 km/h downhill. It's labelled with its wattage ("at 140 W") because your real time depends on how you ride. It's honest on big days: a 5,500 m Alpine stage at 140 W really is 11 hours or more.

**D76. Climbs are found, not listed.**
- **How:** a climb runs from a low point while the road stays within max(20 m, 10 % of the gain) of its high point. Its foot and top are then placed where gain² ÷ length peaks, which trims flat approaches and flat summit plateaus: a section stays only if it's at least half as steep as the climb.
- **What counts:** at least 40 m of gain over 300 m at 3 % or more.
- **Category:** from gain × average %, as HC, 1, 2, 3 or 4.
- **Checked against real climbs:** Madeleine comes out as 19.2 km at 7.9 % (real: 19.2 km at 7.9 %), Col de la Loze 26.6 km at 6.4 % (26.4 km at 6.5 %), Cipressa 5.7 km at 4.0 % (5.6 km at 4.1 %).
- **Limit:** short Flemish bergs that gain under 40 m in this elevation data don't register, so Flanders shows fewer climbs than the race book.

**D77. Long stages: pick a length of time, then the segment.** Full, 30 min, 45 min, 1 h, 1 h 30 or 2 h. The window is as long as that time takes at your pace, so it narrows on climbs, and you drag it along the profile or jump to Start, Hardest (most climbing) or Finale, which is the default for stages over 75 min. The segment is part of the route id (`race/2025/tour-de-france/18#164000-172600`), so the engine, history, "Ride this again" and the ghost all work on that exact piece with no new plumbing. A race's stage list shares one height scale (with a floor at 40 % of its biggest relief), so flat stages look flat next to mountain ones.

**D78. The course preview shows the road you'll actually ride.** It used to add up gradients per time step and stretch the result to fill the card, so a flat course could look like a mountain. Now:
- **Real metres:** the generated course is ridden at your estimate pace (70 % FTP, your weight) and becomes metres of elevation over kilometres, drawn with the same profile and climb markers as a race stage.
- **An honest scale:** the height scale is 40 % of what your pace could climb in that time (at a steady power you gain height at about P ÷ m·g, on any gradient). A mountain course fills the card at any length, and a flat one stays a gentle line.
- **The generator keeps types apart:** flat, rolling and hilly roads now each stay within their own band of height (about 15, 50 and 140 m above the start at medium effort, scaled ×0.7 / ×1.3 by effort), instead of forcing climbs to at least balance descents, which let "flat" drift 90 m.
- **Mountain has fewer, longer climbs:** one in half an hour, three in ninety minutes, covering 40–55 % of the ride.
- **Tested:** relief orders flat < rolling < hilly < mountain with no overlap across efforts, and harder effort is steeper within a type.

**D79. Six round 3 faces, ported from design/new round (RideFace3):** Borne, Stem card, Piste, Groupset, Broadcast and Tarmac. Ardoise and Brevet were not picked.
- **Faithful to the prototype:** layouts, colours and drawing follow `RideFace3.dc.html` point for point on the 1194×834 canvas. Numbers are SwiftUI text; graphics are Canvas, with the static parts (the Piste track, Tarmac's asphalt texture) drawn once.
- **Fonts:** Barlow Condensed (six static weights, OFL) and Permanent Marker (Apache 2.0) are bundled next to the round 1 fonts.
- **The road ahead is real:** a `RideCourse` in ZmashKit holds the course and its climbs, using the same detection as the race catalog. On a route it's the route; on generated terrain it's the course ridden at 70 % FTP, and your place on it follows the clock, because that terrain is defined in time. Borne's stone (km and metres to the summit, the next kilometre's gradient; on the flat, the next col), the Stem card, Broadcast's ribbon and Tarmac's painted finish all read from it. Rides with no known road (manual, workouts) get the design's fallbacks, e.g. Borne shows metres climbed.
- **New telemetry, tested:** best 200 m and a Flying 200 event (after the first kilometre, at most once a minute), and spin-up (120 rpm held for 5 s). Coasting means moving at zero cadence.
- **Motion is interpolated between samples:** the crank, chain, lap dot and road scroll run at 60 fps from rates, easing back to the ride's data, so nothing steps at the engine's 10 Hz.
- **Each face keeps its own magic:** Borne's summit sign, Stem's felt-tip tick, Piste's lit last 200 m, Groupset's spin disc, Broadcast's flamme rouge, Tarmac's painted road. The gallery previews each one, and the showreel includes it.
- **Palettes:** Stem card has three felt-tip colours and Groupset four anodised colours. The other four have one palette each, the design's. Broadcast and Tarmac are dark by nature. Their layouts are fixed, so they have no metric slots.
- **French stays French:** on Borne (SOMMET, PROCHAIN COL, à gravir), as on real stones.

**D80. Every face has the whole course's profile along the bottom, full width, with zoom.** Faces already fill the screen, so a strip laid over them would cover numbers. Instead each face shrinks by about 11 % (letterboxed in its own background colour) and the profile gets its own 92 pt band.
- **What it shows:** the whole course start to finish, what you've ridden shaded darker, you as a marker, and the climbs' categories. Heights are honest: at least 8 m of relief per km shown, so a flat road stays flat.
- **Zoom:** whole course, 20, 10, 5 or 2 km around you (a quarter of the window behind you, the rest ahead). Change it with the − / + buttons, a pinch, the keyboard (− and +), or two new controller commands you can map in Settings → Controller buttons. The level is remembered.
- **With no known road** (manual gradient, workouts), the strip shows what you've ridden so far, labelled "ridden".
- **Colours:** the strip takes the face's background and picks dark or light ink from it, so it reads on Horizon's changing sky.
- **Classic** gets it too, except in Split View. It can be turned off in Settings → Faces.

**D81. Every face is in the mid-ride rotation by default, and a swipe switches faces (supersedes the shortlist in D44).** The rotation was a three-face shortlist (Paper, Aura, Horizon), so faces added later, such as the six round 3 ones, never came up when switching mid-ride. Now:
- **Stored as exclusions:** the gallery's switch ("When switching mid-ride") takes a face out, and at least two always remain. New faces join automatically; the old shortlist is no longer read.
- **Swipe:** on the ride screen, a left or right swipe does what the D-pad does. It works alongside a tap, which still shows the controls.

**D82. Famous climbs come from the race files, found by where their summits are (supersedes D58).** The approximate climbs (built from published gradients) and the two invented routes are gone; every profile in the app is now a real one.
- **How they're found:** `make races` checks each race's track against a table of about 40 famous summits (coordinates, altitude, the towns their sides start from). A track that tops out near a summit, at the right height, rides that climb; the climb is cut from the foot to the top as the climb finder sees it. Mountains are searched within 3 km of the summit, small hills within 700 m (Flemish bergs are close together), and a pass seen only in its last few hundred metres (a stage crossing it from a high valley) doesn't count.
- **Sides:** named after the nearest known starting town (Bédoin, Luz-Saint-Sauveur), or by direction ("from the west") when none is close. When several races ride the same side, the longest profile is kept.
- **What's in:** 20 climbs, including Alpe d'Huez, Ventoux (Bédoin), the Tourmalet from both sides, the Galibier, Télégraphe, Loze, Madeleine, Hautacam, Superbagnères, Peyresourde, the Giau, the Cipressa and Poggio, the Flemish bergs, La Redoute and the Cauberg. Stelvio, Mortirolo, the Izoard, the Zoncolan, the Angliru and others aren't ridden in these files, so they're not in the app; `make races` lists them, and they'll appear when a race file with them is added.
- **In the app:** the Route picker lists them by country after the races, each opening the same page as a stage (profile, numbers, estimate, and a time window on long climbs). A climb page opens on the whole climb.
- **Old ids:** rides saved on the old Alpe d'Huez, Ventoux and Tourmalet now point at their real equivalents, so history, "Ride this again" and the ghost keep working. Stelvio, Mortirolo and the invented routes resolve to nothing, and the home screen forgets them.

## Known gaps (need the user's hardware)

| Item | What to check |
|---|---|
| M0 probe checklist | Run Settings → Hardware probe once; export the log. |
| Zwift trainer protocol on CORE 2 | Devices → Advanced → Trainer protocol → Zwift: does shifting feel native? |
| PiP audio | YouTube sound plays normally with the floating window up. |
| Apple Health | Turn on, ride, check Fitness shows an indoor cycling workout. |
| Zwift Play / Click, HR strap, ERG | No hardware here; decoders are unit-tested only. |
| Faces on device | Legibility of each face from the saddle at ~80 cm; Aura and Night smoothness and energy over a real ride. |
