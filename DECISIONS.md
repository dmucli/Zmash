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

**D83. One band along the bottom carries the ride's context; nothing floats over a face.** The route and workout panels at the top covered face headers (Paper's column heads, Broadcast's LIVE badge), event messages covered Paper's heads, and the controls sat on the profile. Now the band under the face (D80) holds all of it:
- **Left:** the route (name, distance to go, time ahead of or behind your best in words, altitude and summit), or the workout (step, target with "on target / ease off / push", time left in the step, what's next, intensity).
- **Middle:** the course profile, or for a workout its blocks with a playhead. Events (a kilometre, a summit, a best) show over it briefly.
- **Right:** zoom (profile only) and the controller and trainer dots, which turn orange or red when a link drops.
- **When it shows:** always with a route or workout; otherwise when the profile is on. Turned off with no plan, there's no band: events return to the face, and the dots appear in the corner only when something's disconnected. Split View keeps the plan and drops the profile.
- **Controls:** the close button now leads the on-screen control row, and the row sits above the band. It still appears on tap and hides after 4 s.

**D84. SwiftUI hygiene, per the swiftui-expert checklist.** Lists never key rows by position: face metric slots are `FaceSlot`s numbered by their place on the face (the same metric can fill two slots), climbs key by where they start, gallery dots by face, and calendar headers by weekday number (the symbols repeat). Loops emit one view per item (empty slots are filtered out first). The ride screen builds its face data once per update and shares it between the face and the band. The home screen is split into `SetupView` (sections), `SetupPieces` (device cards, chooser rows, Start bar) and `SetupPreviews`.

**D85. Screen audit fixes (11" and 13" landscape and portrait, light and dark).**
- **Rows of numbers share the width equally:** on Paper and Kinetic, an hour-plus countdown ("−1:55:07") ran into the next number. Each cell now gets a fixed share with a gap and shrinks its value to fit, and cells align at the top.
- **Home in portrait** stacks the options above the preview below 1000 pt wide, and a preview's figures never wrap mid-number.
- **Stem card and Broadcast without a course** (a workout, manual gradient) draw what's been ridden on an honest scale, so a flat ride is a low line instead of a slab.
- **Profile labels** (a climb's category at the top, the last kilometre mark) stay inside their card.
- **Screenshot runs** (any -Zmash… launch argument, debug builds only) discard a leftover unfinished ride instead of prompting.
- Not checked: Split View (the Simulator can't script it). Its compact dashboard is unchanged apart from the band.

**D86. Older smart trainers: Wahoo's pre-FTMS control and Tacx FE-C over Bluetooth.** Unverified on hardware; the codecs are tested against byte layouts worked from the specs.
- **Choosing a protocol:** from the control services a trainer offers, in the order FTMS > Zwift > Wahoo > Tacx. Devices → Advanced → Trainer protocol can force Wahoo or Tacx; a forced protocol the trainer doesn't offer falls back to the order. Auto still tries the Zwift protocol first when it's offered. The diagnostics log records what was offered and what was chosen.
- **Wahoo** (older KICKR, SNAP, CORE): unlock, sim mode with rider + bike mass, Crr 0.004 and wind resistance 0.51 kg/m, then grade (−100…+100 % over 0…65535); or ERG in watts. Leaving ERG re-sends sim mode. Commands go one at a time, each waiting for its write response. Power and cadence come from the Cycling Power measurement.
- **Tacx FE-C** (older Neo, Flux, Vortex, Genius): ANT pages on the 6E40FEC1 service. On connect it sends user configuration (page 55) and wind (page 50), then track resistance (page 51, grade in 0.01 % from −200 %) or target power (page 49, 0.25 W). It reads power and cadence (page 25) and speed and heart rate (page 16). Messages are checksummed, and bad ones are dropped.
- **Both** support ERG, so workouts and "Shift with ERG" work; gearing is folded into the grade as with FTMS. Discovery also recognises the FE-C service and Tacx names.

**D87. Power meters, speed and cadence sensors, and basic trainers.** Unverified on hardware; the parsers, curves and matching are unit-tested.
- **Two new device roles** in Devices: power meter (Cycling Power) and speed/cadence sensor (CSC). A device that advertises only Cycling Power is offered as both a trainer and a power meter, since older Wahoo trainers look exactly like power meters. One that also offers FTMS or Tacx FE-C is only ever a trainer. A device serves one role; pairing it as another moves it.
- **Power source:** trainer (default) or power meter. With the power meter chosen, its power drives the numbers and the physics. ERG targets are divided by the smoothed ratio of power meter to trainer (steady pedalling only, capped at ±25 %, settling over about a minute), so the pedals read the target.
- **Cadence** from a sensor or the power meter fills in when the trainer reports none.
- **Basic trainers:** choose "Basic" and a model in Devices → Trainer. Power is worked out from rear-wheel speed (a speed sensor, or a power meter that counts wheel turns) through the maker's published curve (Kinetic, CycleOps Fluid 2), or a rough generic fluid or magnetic curve. A paired power meter replaces the estimate. Resistance can't be controlled, so gradient and gears are shown but not felt, and the Devices screen says so. Wheel size is adjustable (2105 mm default).

**D88. iPhone and Mac.** The same app, not a separate one.
- **iPhone:** built for iPhone and iPad, portrait and landscape on iPhone. Home, History and Settings use their narrow layouts. The ride screen follows width, not size class: under 700 pt (an iPhone upright, iPad Split View) it shows the compact dashboard, and wider (an iPhone on its side included) it shows a face. On a short screen (compact height) the band slims to 60 pt and drops its detail lines, and the on-screen controls fold into two rows of smaller buttons when narrow. The folding also fixes a bug: the one-row controls were wider than a phone or Split View column even while hidden, which pushed the whole ride screen off-centre.
- **Mac:** the iPad build runs on Apple silicon Macs ("Designed for iPad"); `make build-mac` builds it. Keyboard shortcuts already cover riding (arrows, [ ], space, E, + and −, Esc). Built but not launched here; Bluetooth on the Mac is untested.
- **Debug:** the landscape preview (-ZmashLandscape) now also reports a compact height on a phone, as a real rotation would.

**D89. A drawn course rides as steep as you draw it (supersedes D72's scaling).** D72 rescaled every drawing so its steepest climb hit Effort's maximum, so "steepest" never changed as you redrew, and a gentle sketch rode like a wall. Now the drawing's own slope sets the grade: rising the card's full height across a quarter of its width is the effort's maximum (Easy 4 %, Medium 7 %, Hard 10 %), gentler strokes are proportionally gentler, and nothing passes the maximum or −10 % downhill. "Steepest" and "fastest descent" follow every stroke. Effort still scales the whole drawing.

**D90. The Today card: one suggestion, with why.** At the top of "Your ride" on home.
- **Freshness:** fitness is the 42-day and fatigue the 7-day exponentially weighted daily load (TSS of saved rides), and form is fitness minus fatigue, counted before today. Below −20 it suggests recovery, above +5 it pushes, otherwise it keeps things steady. The line says so, with the number ("Fresh legs · form +8").
- **What it can suggest:** every workout, sorted by its estimated intensity (easy under IF 0.70, moderate to 0.85, hard above; the ramp test counts as hard); the famous climbs at your pace (steep ones, 6 %+ average, only on fresh days); and an easy spin on rolling roads for tired legs.
- **How it chooses:** it skips anything ridden in the last seven days and prefers the length you usually ride (the median of your last ten rides). Ties keep the library's order, so it's stable. Plans and campaigns will lead the list when they exist.
- **Using it:** "Ride this" fills the home plan; the dice button shows the next of up to three suggestions; × hides the card until tomorrow. With no rides yet: "First ride? · Easy spin, 30 min".

**D91. Palmarès: records on the famous climbs, and lifetime totals in cycling terms.** A fourth History tab, shown even before the first ride.
- **The wall:** every famous climb by country, with its profile. Once ridden foot to top, it's ticked and shows your best time, VAM and date. Until then it's faded, with "Ride it".
- **Climbs inside stages count:** the catalog now records where each famous climb sits on each stage (`Stage.famousClimbs`, 28 placements, mapped to the merged climb ids). A Tour stage over the Tourmalet therefore also times the Tourmalet. A ride's distance along the route comes from its 1 Hz speeds, scaled to agree with the ride's distance; a windowed ride starts at its window. A climb counts only if the ride covered it from the foot to the top.
- **Totals:** metres climbed (as Everests and as Ventoux from Bédoin), kilometres (as Tours de France, the 2025 race's length), hours and rides, and how many of the famous climbs you've done.
- **On the summary:** "First time up …", "New best on …" (with how much quicker) or how far off your best, plus milestones crossed: each Everest (8,848 m total), each 1,000 km, each 100 hours.
- Records are computed from saved rides, not stored. The summit-time message during the ride comes with coaching (Phase 14).

**D92. Monthly and yearly recaps.** A shareable card in the ride postcard's style.
- **What it shows:** hours, kilometres, metres climbed, rides, the Everest comparison, the longest ride, the best 20 minutes, the route ridden most (when more than once), the favourite face, and the longest run of weeks with a ride.
- **Where it shows:** on home in the first week of a month (last month) and the first two weeks of January (last year). × hides it until the next one. History → Progress can always open last month's and the year so far.
- **Faces:** rides now record the face on screen when saved, for "favourite face". Older rides have none.
- Months and weeks follow the device's calendar.

**D93. First-run setup.** Six short steps, each skippable, shown on first launch and from Settings → Set up again:
1. **Welcome:** "Set up", or "Try the demo instead".
2. **Controller:** paired right there from a live list.
3. **Trainer:** smart (pair it) or basic (pick the model, pair a speed sensor).
4. **Heart rate.**
5. **About you:** weight, bike and FTP. "Not sure" sets 2.5 W/kg and puts a ramp test first on the Today card until one is ridden.
6. **First spin:** shift up twice, raise the gradient twice (felt on the trainer), then ten seconds at 90 % of FTP or more. Each part moves on by itself; the on-screen buttons work too.

Existing installs (with a saved plan) count as set up. Screenshot runs skip it unless they ask for it (`-ZmashScreen setup`, `-ZmashSetupStep n`).

**D94. A difficulty rating, 1 to 5, on the ride you're about to do.** A five-bar gauge with a word (Easy, Steady, Moderate, Hard, Very hard) on the title row of each Your ride card, and next to each Today suggestion.
- **Routes, generated courses and drawings** are rated by length at your estimate pace: under 20 min, 45 min, 90 min, 3 h, then longer. Steep ground (a kilometre at 8 %+, or 600 m+ of climbing an hour) makes it one step harder.
- **Workouts** are rated by the training load they ask for (TSS under 25, 45, 65, 90, then more). The ramp test is 4.
- **Manual gradient** is rated by length alone. An open-ended ride has no rating.

**D95. "Stop session" when ending a ride.** The End ride? dialog (from the close button or the flag) now offers three choices:
- **End and review:** the summary screen, as before.
- **Stop session:** saves the ride and goes straight home, with uploads and Apple Health as usual but no effort rating or note. A ride under a minute is discarded instead, as the review would have suggested.
- **Keep riding.**

Holding the controller's end button still ends and reviews.

**D96. Grand Tour campaigns.** Any stage race can be ridden as a campaign, from its page in the Route picker ("Ride it as a campaign").
- **Rivals:** 20 invented riders (no real names), fixed when the campaign starts, from 85 % to 115 % of your estimate pace (70 % of FTP then), each with a ±3 % day on each stage. They ride each stage's real profile with the same physics as you. Everything is seeded, so results never change after the fact.
- **Stages** go in order. Ride one whole, or only its finale (the last 30, 45 or 60 minutes at your pace). The skipped part is added at your estimate pace, so short rides still move you through a Tour.
- **What counts:** any saved ride on the campaign's next stage (whole or any window) that reached the end of what it set out to ride. This is true whether it was started from the campaign page, the Today card or the stage page, and it is counted at save (review or Stop session).
- **Classifications:** general on total time. Mountains: the first three over each categorised climb inside the part ridden (HC 20/15/12, cat 1 10/8/6, cat 2 5/3/2, cat 3 2/1, cat 4 1); your time over each top comes from the ride's samples. Leaders wear yellow and red dots in the tables. The summary shows your stage place, your GC place and movement, points, and any jersey taken, then a final result on the last stage.
- **Today card:** leads with the next stage, cut to its finale at your usual ride length.
- **Storage:** small JSON files in Application Support, kept out of the ride database. One active campaign per race; abandoning keeps the results as a DNF.

**D97. Gentle coaching.** Off by default. Settings → Coaching messages turns it on, with a switch for each kind:
- **Cadence:** under 65 rpm while pushing for a full minute, outside ERG.
- **Last effort:** 45 s or less left in a workout's last hard step (88 % FTP or more).
- **Climbs:** halfway up each categorised climb on the course, with the distance to the top and, when there's a ghost, how far up or down on your best you are.
- **Bests:** at the top of a famous climb (ridden on its own or inside a stage): "First time up …", "New best on … (quicker by …)" or how far off your best.

Messages use the band's event slot, with a quiet outline instead of the accent, for six seconds. They're at least a minute apart and held back while sprinting (over 150 % FTP); summit times always show, including at the finish of a climb ridden on its own. Off in Calm motion. The rules are a pure `Coach` in ZmashKit, fed each tick by the engine.

**D98. Ride sounds, synthesised live.** Off by default. In Settings: Ride sounds, a volume slider and the kilometre chime.
- **What plays:**
  - wind rising above 25 km/h;
  - freewheel ticks when coasting (18 pawls on a 2.105 m wheel);
  - a chain click on each shift, heavier on a jump of two or more;
  - a crowd swelling in the last kilometre of a categorised climb, loudest on HC;
  - a bell at summits and a chime at each kilometre;
  - three beeps before each workout step change;
  - a short finish arpeggio.
- **How:** no audio files. A single AVAudioEngine source node synthesises filtered noise, clicks and sine partials, with parameters handed over under a mutex. What to play is decided by the pure `SoundCues` in ZmashKit (tested). Silent while paused.
- **Mixing:** with sounds on, the audio session mixes with other apps (the floating window's session gains "mix with others" too), so music or video keeps playing. The ringer switch doesn't mute it (the floating window needs a playback session); the switch and volume in Settings do.
- **Swift 6 note:** the render block is built in a nonisolated function. One made inside a main-actor method is main-actor isolated and traps on the audio thread.

**D99. Trainer calibration (spin-down).** Devices → Trainer → Calibrate, once the trainer is connected. It shows the last calibration date, in orange when it's a month old or never done.
- **FTMS:** Spin Down Control (0x13, start). The response gives the target speeds, and Fitness Machine Status 0x14 walks through "speed up", "stop pedalling", then success or error.
- **Tacx FE-C:** calibration request page 1 (spin-down bit). Page 2 gives the target speed and whether the current speed is right; page 1 comes back with the result and the spin-down time.
- **Older Wahoo:** points to Wahoo's app. I don't know its calibration command's bytes well enough to send them blind.
- **Zwift protocol:** says there's nothing to do.
- **The screen:** the trainer's speed live next to the target, one instruction at a time, a two-minute timeout, and "Try again".
- **With a power meter:** Devices says how the trainer reads against it (from D87's ratio, after about a minute of riding).
- There's no reminder on home; the date in Devices is enough.

**D100. Siri and Shortcuts.** Five App Intents, with phrases:
- "Start today's ride in Zmash": the Today card's first suggestion.
- "Start ‹workout› in Zmash": any library or imported workout.
- "Ride ‹climb› in Zmash": any famous climb.
- "How much did I ride this week in Zmash": answered by Siri, without opening the app (hours, distance, climbing, rides since Monday).
- "End my ride in Zmash": end and review.

Riding intents open the app and start at once when the trainer is connected (or in demo). Otherwise they set the ride up on home, where Start says what's missing. They also appear as Shortcuts actions, so a Focus automation can start a ride. A small `IntentRouter` hands requests to the running app. The metadata builds into the app (5 actions, 5 phrases).

**D101. Training plans that adapt.** In the Workout picker, under Plans:
- **The four plans:** FTP Build (6 weeks), Ready for Ventoux (8 weeks, ending with the real climb from Bédoin), Base (4 weeks), Back on the bike (3 weeks). Three sessions a week.
- **Starting:** pick your ride days (Tue, Thu, Sat by default) and this week or next Monday.
- **Scheduling:** worked out afresh each day, never stored. With fewer days than sessions, the most important sessions are kept. A session not ridden by its day moves to your next ride day that week, and with no day left it's missed, never stacked. The History calendar shows the planned days as dashed outlines.
- **Sessions:** library workouts, generated intervals (tempo 82 %, sweet spot 90 %, threshold 100 %, VO₂ 115 %, with recoveries) and endurance rides, or a famous climb. Each has a stable workout id (`plan/<plan>/<week>-<slot>`), so a saved ride marks its session done; a climb session counts when you ride that climb in its week.
- **Adapting:** the average power held in a session's hard steps (85 % FTP+) against their targets sets the next session of that family. Above 105 % goes a notch up (3 % harder), and under 90 % or cutting it short goes a notch down, within ±3 notches. FTP itself follows the Progress tab's estimate when you accept it, so every target moves with it.
- **Where it shows:** the Today card leads with a plan session on its day; the plan page shows the week, what's next with "Ride this", and "Leave the plan". One plan at a time; enrolments are small JSON files, cached in memory.

**D102. A workout builder.** "New" in the Workout picker; "Edit" on your own workouts (swipe or long press); "Copy and edit" on library ones.
- **The workout as blocks:** height is the target and the FTP line is dashed. Tap a block to select it; drag its right edge to stretch it in 15 s steps.
- **The selected step:** steady, ramp or free; length; target(s) in % of FTP with the watts beside; label; move earlier or later; duplicate; delete; "repeat this step and the next × N" for intervals.
- **Live totals:** length, TSS, intensity and the difficulty rating (D94).
- **Saving and export:** saves to My workouts (the old Imported section, now holding both). Export shares a `.zwo`, written by `ZWOWriter` with each label in an attribute Zwift ignores, so re-importing keeps them. Every library workout round-trips (tested).

**D103. The ride as a Live Activity on iPhone.** When a ride starts on an iPhone, it appears on the lock screen and in the Dynamic Island:
- **Lock screen:** power, the clock (counting by itself), distance or time to go, gear, grade and heart rate, plus the workout step and target.
- **Dynamic Island:** power and the clock when compact; with the title and step or grade when expanded.
- **Updates:** every 2 s from the app. The clock runs from a start date, so it stays smooth between updates. When the ride ends, the final numbers stay for 15 minutes.
- **iPad:** has no Live Activities, so the floating window remains the way there.
- **How:** a new widget extension target (`ZmashWidgets`, bundle `com.davidmucelli.zmash.widgets`) draws it, with local updates only (no push, no App Group). `Activity` isn't Sendable, so the app keeps its id and looks it up in detached tasks.
- **Checked** in the iPhone Simulator: the activity starts and updates, and the extension renders it. The Simulator's screenshots don't draw the island. The first device build registers the extension's ID on your Apple account.
- **Widgets and the Watch (Phase 17's other two) are waiting:**
  - widgets need an App Group to read the app's data, which may need a paid account;
  - the Watch needs a watchOS runtime to test and a Watch to verify heart-rate mirroring.

**D104. Widgets.** Three, on the home screen and the lock screen:
- **This week:** hours, TSS, rides, and a bar per day, Monday first. Small, medium, or rectangular on the lock screen.
- **Next up:** the Today card's first suggestion and why. Small, or rectangular on the lock screen.
- **Form:** fresh, OK or tired, with the number. Small, circular or inline on the lock screen.

**How:** the app writes a small JSON summary into the App Group `group.com.davidmucelli.zmash` when home appears and after each saved ride, and reloads the timelines when it changes. The widgets read it, with an hourly refresh besides.

**Account:** the free account allowed the App Group. One device build registered it, and both provisioning profiles carry it.

**Checked:** the summary is written correctly in the Simulator. The widgets themselves haven't been seen yet, because the command line can't add them to a home screen.

**D105. Apple Watch.** On iPhone, Devices → Heart rate → "Heart rate from Apple Watch" (off by default).
- **Starting:** starting a ride opens Zmash on the Watch with an indoor-cycling workout (`HKHealthStore.startWatchApp`).
- **Heart rate:** the watch runs a live workout session mirrored to the iPhone (iOS 17+ mirroring) and sends heart rate over it. The hub takes a paired strap first, then the Watch, then the trainer's.
- **On the wrist:** the iPhone sends the ride once a second (title, power, time, gear, grade, paused). Tap the watch to pause or resume; turn the crown to shift, one gear a notch.
- **No double workouts:** when the ride ends, the watch discards its own workout if the iPhone is saving the ride to Health (with trainer power); otherwise it keeps it, so rings still count.
- **iPad:** it can't pair a Watch, so a strap stays the answer there.
- **Targets:** `ZmashWatch` (watchOS 11+, bundle `com.davidmucelli.zmash.watchkitapp`), embedded in the iPhone app. A shared `WatchMessage` (JSON) travels over the mirrored session.
- **Checked** in paired simulators: the watch app runs, and starting a ride on the iPhone opens it and asks for Health access. Past that (allowing access, mirroring, heart rate) needs a tap and a real Watch.

**D106. No countdown; the ride starts when the pedals turn.** The 3-2-1 countdown is gone, from the faces and from Classic. A ride opens waiting for the pedals ("pedal to start") and the clock starts on the first sign of pedalling (cadence or power), with no one-second wait. The gallery's demo still shows its countdown moment.

**D107. A course profile you can read.** The band along the bottom is taller: 132 pt (76 on a phone on its side), up from 92 and 60. The profile now fills its height with the stretch shown: the scale is the actual altitude range, at least 12 m. This replaces D80's "8 m per km" floor, which flattened most roads to a line. The lowest and highest altitudes are written in a gutter on the left, so the exaggeration can be read.

**D108. The ride's controls slide up as a panel; A opens it; hold B for 3 s to end, with a filling circle.** This supersedes the floating buttons of D83 and D88.
- **The panel** comes up from the bottom and covers the band:
  - gears (− / + with the current gear);
  - gradient (or gradient bias on auto terrain, routes and workouts);
  - pause/resume, the floating window, end, and hide.
- **Opening and closing:** it opens and closes with the controller's A (a new "Show controls" command) or a tap on the screen. A swipe down or 8 s without a touch also closes it. It stays up before the first pedal stroke, where End reads "Back" and just leaves.
- **Your button map:** A was "pause" by default. A saved map with A still on pause moves to "Show controls" once; Z and the on/off buttons still pause.
- **Ending by hold:** the hold is now 3 s (it was 1 s). The controller reports when a hold starts and stops, and a ring fills clockwise in the middle of the screen. When it's full, the ride ends and goes to the review (the same as "End and review"; Stop session stays in the End dialog).
- **Keyboard:** [ ], the arrows, space, E, Esc and T work whether the panel is up or not.

**D109. Every face: choose its main number and its font.** Speed is the main number by default on every face. That changes Aura, whose big number was power; power moves into its bottom row, and the Z-zone line and the mesh still follow power.
- **Main number:** in Customise, any metric (power, heart rate, cadence, time left, % FTP…). A face keeps its own speed formatting (its decimals, "kilometres per hour") when speed is chosen. Paper's column heading follows the choice. Big numbers shrink to fit a longer value.
- **Font:** "As designed", Archivo, Newsreader (serif), Outfit (round), Roboto Flex or Barlow Condensed. It replaces the face's family everywhere on it, the shared number cells and the paused/finished screens included. The stem card's felt-tip handwriting (Marker) stays.
- **Storage:** both live in `FaceStyle`; styles saved before this load unchanged.

**D110. One Customise sheet for every face, Classic included; face settings leave Settings.**
- **The same sections, in the same order, for every face:** Palette (Classic: Colour, i.e. colour by grade and wind), Main number, Numbers, Font (Classic: typeface, weight and main-number size), For all faces (motion, course profile), Reset.
- **Classic:** its old separate display screen is gone.
- **Settings → Faces:** keeps only the way into the gallery and the current face; "Classic face", face motion and the course-profile switch moved into Customise.

**D111. Tarmac: the road runs up the screen, in perspective.** Tarmac was a road from above, scrolling sideways. Now it's the road seen from the saddle, narrowing to a vanishing point under a dusk sky and a far ridge.
- **Speed:** the centre dashes (4 m painted, 8 m gap) and bands in the verge sweep towards you at your real speed.
- **Grade:** the horizon drops as the road climbs and lifts on descents, eased so it never jumps.
- **Painted on the road, foreshortened:** the next kilometre number, and the fans' paint over the last 500 m of a categorised climb.
- **Climbs:** chevrons line both verges, one per percent, kept in the distance clear of the numbers; the verge turns from grass to rock.
- **Numbers:** they stay where they were, with a soft shadow to read over road and verge.

**D112. Several riders on one iPad.** A rider chip in the home header switches riders, adds one ("Add a rider…": name, weight, bike, FTP, or a guess plus a ramp test) or opens Settings → Riders to rename, switch or remove.
- **What's each rider's:** weight, bike, FTP, face and face styles, Classic's layout, the Apple Health setting, the ramp-test suggestion; their rides, and everything built from them (History, Palmarès, recaps, the Today card, form, ghosts, FTP estimates, widgets, Siri's weekly numbers); their training plan and campaigns; and their Strava and intervals.icu accounts. Nobody's ride is uploaded to someone else's account.
- **What's shared:** devices, the button map, units, theme, sounds, coaching, the Watch switch, and the plan on home.
- **How:** the settings stay the current rider's live values. Switching stores the outgoing rider's values in their profile and loads the incoming rider's, so the rest of the app is unchanged. Rides carry a `riderID` ("" for the first rider, and for every ride saved before this); every ride query filters on it. Plan and campaign files carry it too, and upload keys get the rider's id appended (the first rider keeps the original keys, so nothing needs to reconnect).
- **Removing a rider:** deletes their rides, plans and campaigns from the iPad, after a confirmation. You can't remove the rider who's currently riding.
- **Your existing data:** it all becomes "Rider 1", which you can rename in Settings → Riders.

## Design system (design/Zmash Design System)

The system in `design/Zmash Design System/` is the app's look from now on. The 11 faces keep their own look; the system covers everything around them, plus the band and the controls panel under them. Classic is rebuilt as the prototype's Live ride screen. Screens the prototype doesn't show (Palmarès, campaigns, plans, the builder, recaps) are designed from its components.

**D113. Tokens and fonts.** `Design.swift` now holds the system's tokens.
- **Palette:** the semantic colours, light and dark (bg, surface, surface-sunk, surface-glass, surface-hero, border, border-strong, fg-1/2/3/ghost, on-hero, accent, terrain, invert, block-rest).
  - Plus `Design.Tarmac` for the ride, the same in both themes, and `Design.Accent`, `Design.Status` and `Design.Zone`.
  - The OKLCH accents are converted to sRGB hex once, written beside their OKLCH source: vermilion #E85433, vermilion-deep #C52D1F, team blue #008EF9 (just outside sRGB, so clipped), go #36A558 (dark #53BE70), caution #E9AB2B, stop #D73337, zone 2 #7FB6EE, zone 4 #F48A64.
- **The old names stay as aliases:** background → bg, primary → fg-1, secondary → fg-3, hairline → border. The app's ~450 uses changed look at once, and each screen then moves to the new components.
- **Grade accent:** climbing now tints towards vermilion and descending towards team blue (it was amber and blue).
- **Type:**
  - Archivo for everything.
  - Numbers of 20 pt and up use the bib voice: Archivo at 62 % width, weight 800. Table figures below 20 pt stay at full width, where 62 % would be too small to read.
  - JetBrains Mono (bundled, OFL) for uppercase labels at +0.14 em and for clocks.
  - Archivo Italic (bundled) for the "ZMASH" wordmark at 80 % width and weight 900.
  - `.textStyle(.display/.h1/.h2/.body/.small)` carries the scale's tracking and line height; `.monoLabel()` does the label style.
- **Spacing, radius and motion:** a 32-pt screen gutter on tablets (16 on phones), a 14-pt gap between cards, radii 4/8/12/16/22, and ease-out (.2,.7,.2,1) at 140 ms and 220 ms. Press scales to 0.97, with no bounces.

**D114. Components.** `Components.swift` and `Textures.swift`.
- **Buttons and controls:**
  - `PillButton` (primary vermilion with ink text; secondary glass with a border-strong outline; invert; glass and bone for the ride).
  - `Chip`, `Tag`, `KeyCap`.
  - `Segmented` as a row of pills, the active one inverted.
  - `RoundIconButton` as a ringed circle, or vermilion for the action that moves you on. It takes the tarmac look inside the ride (`onTarmac`).
  - `PrimaryButton` is a vermilion pill.
  - `PillToggleStyle` for switches.
- **Cards and stats:**
  - `.card()`: 16 radius, 1-pt border, no shadow. A 2-pt vermilion ring when selected; hatch with bone text for a hero card.
  - `BibIndex`: 01, 02… in fg-ghost, vermilion when lit.
  - `.sunkTile()`, `StatTile`, `StatStrip`, `SettingRow`, `HUDChip`, `Wordmark`.
- **Textures:**
  - grain, a 200-pt noise tile generated once, multiplied on light and screened on dark;
  - the bar-tape hatch drawn in a Canvas;
  - lane dashes;
  - the tri-stripe;
  - `.screenBackground()`, which puts bg, grain and the stripe on a screen.
- **Where blur and shadow appear:** glass blur only on HUD chips. No shadows except sheets.

**D115. Home follows the prototype.**
- **Top bar:** the tri-stripe across the top edge, the ZMASH wordmark, and pill nav (Home, History, Devices, Settings).
  - On the right: one glass device pill (a dot per trainer, controller and heart rate, which opens Devices), the rider menu, and the theme button.
  - The three connection cards that used to fill the top of home are gone. What they said is now the pill's dots, spoken in full by VoiceOver, and Devices shows the rest.
- **Greeting:** a mono date ("WEDNESDAY · WEEK 39") and "Ready when you are, {first name}.", with THIS WEEK (rides and hours) on the right.
- **Today card:** now the hero, bib 01 on the bar-tape hatch. It has the reason as a mono label, the title large, and the route's profile, the workout's zone blocks, or lane dashes for a free ride. Under that, its numbers and "Ride this" in vermilion.
- **Ride types:** beside it, three cards for the ways to ride: 02 free ride ("Just pedal."), 03 workout, 04 route. They replace the Free ride / Workout / Route segmented control. The selected card has a vermilion ring; tapping a selected workout or route card opens its picker. Before one is chosen, the workout and route cards show a faded example.
- **Your ride:** below, the options and the preview each sit in a card.
- **Start bar:** repeats the chosen card's bib, with "Start ride" as a vermilion pill.
- **Phones:** the nav collapses to History and Settings icons, and the three cards sit in a row under the hero.
- **Other changes:**
  - Workout strips are coloured by power zone.
  - Route profiles use the motif (a line over a terrain-blue fill, with the ridden part in vermilion).
  - Status dots use go, caution and stop.
  - The rider badge is vermilion.
  - The monthly recap is a small card with bib numerals.

**D116. Pickers, Devices, Settings, setup.**
- **Workout and route pickers:** now grids of cards, like the prototype's Workouts/Routes screen. A large title, pill actions (New, Import, Done), and chips that filter by kind.
  - Each card carries a bib index, a mono meta line (length, TSS and IF; km, m and average grade), and its shape: zone blocks or the profile.
  - Stage races show one bar per stage: grey when flat, blue when hilly, vermilion for the mountain stages.
  - The race page puts the campaign on a hatch card above its stage cards. The stage page has its profile and figures in a card, and presets as chips.
  - Deleting your own workout or route moves to a long press (grids have no swipe).
- **Settings:** follows the prototype, with cards in two columns.
  - Left: the rider (badge, name, and FTP, weight and bike as bib tiles with −/+), appearance (theme, units and watts as pill segments), and faces.
  - Right: the ride, sound and coaching, and connections (Devices, buttons, uploads, diagnostics, probe, set up again).
- **Deeper screens stay forms, in the system's look:** Devices, Uploads, Controller buttons, Riders, Customise.
  - Surface rows on the grained background, mono section headers, Archivo, the pill switch.
  - Values and actions are in ink, so vermilion stays for effort and for switches that are on.
  - Devices rows show an icon tile with a status dot, the kind as a mono label, the state and the detail.
  - Controller buttons show an L/R key cap.
- **Navigation bars:** titles are set in Archivo.
- **Icons:** added the Lucide icons the system uses (zap, gauge, share-2, activity, upload, refresh-cw, sliders-horizontal, …) at a 1.5 stroke.
- **Setup flow:** display headings, the wordmark on the welcome step, cards and the screen background.

**D117. Summary, History and the screens the prototype doesn't show.**
- **Summary:** follows the prototype's Summary.
  - Header: a vermilion bib (this ride's number in the week), a mono date and kind, the ride's name large, and Share, Discard and Save as pills (Save in vermilion).
  - Under it, a stat strip in one card: mono labels over bib numerals, split by hairlines.
  - Wide screens: the ride's charts on the left (they weren't on the summary before), and on the right training, campaign, records, "How hard did it feel?" and the note. Phones stack them.
  - The effort scale's segments take the zone colours.
- **History:**
  - Rides are cards: a mono date, the ride's name, bib figures, and an effort dot in zone colours. Delete moves to a long press on the list, and stays in the ride's page.
  - The calendar marks ridden days in vermilion; planned days are a dashed vermilion ring.
  - Charts are titled with mono labels: power vermilion, cadence team blue, heart rate zone 4, speed ink.
  - The power curve is all-time vermilion over the last six weeks in blue. Weekly load bars are vermilion and weekly time bars blue.
  - The ride's page uses the summary's header and stat strip.
- **Palmarès:** metres climbed is a hatch hero card (bib 96 with Everest and Ventoux counts). Distance, Tours de France, hours and famous climbs sit in a stat strip. Climb cards show a vermilion "Ridden" tag, best time as a bib, and VAM and date in mono; climbs not yet ridden are quieter, with a "Ride it" pill.
- **Recap and ride postcard:** now hero cards in the system (hatch, tri-stripe, wordmark, bone bib numerals, the key figure in vermilion), not the Paper face's cream. The Paper face itself is unchanged.
- **Plan:** the next session is a hatch hero card with "Ride this".
- **Builder:** blocks take zone colours, and the selected block has a vermilion ring.
- **Campaign:** takes the cards and type through the tokens.

**D118. The ride: Classic becomes the Live ride; the band and panel go tarmac.**
- **Classic is rebuilt as the prototype's Live ride.** It's tarmac whatever the theme, in one adaptive layout (landscape, upright, narrow).
  - **On top, the bar-tape hatch:**
    - the next few minutes of road as a skyline (lane dashes on a manual ride), with the wind background over it if that's on;
    - HUD glass chips:
      - the ride: its bib (02 free, 03 workout or 04 route, the same numbers as home's cards), name, and distance to go or the next step;
      - the workout step with "Hold 290 W" and its time left in vermilion mono, or on a route the distance to the summit and the gap to your best;
      - grade (tinted by grade when "Colour by grade" is on);
      - time, with what's left;
    - Pause (glass) and End ride (bone) pills, bottom right.
  - **Below:**
    - the main number as a 150-pt-class bib with its unit (and W/kg for power);
    - three more numbers, split by hairlines. Time is skipped, since the HUD shows it.
    - The gear column: − ringed, + in vermilion, the gear between, the ladder under it.
  - **Where the choices come from:** the main number and the others are still Classic's choices from Customise.
  - **Font:** gains a "Bib (Archivo condensed)" choice, now the default; a Classic left on the old default (Rounded) moves to it once.
  - **The profile along the bottom:** it's the band, as before.
- **The band under every face is always tarmac.** The faces keep their own look.
  - **Look:** the tri-stripe along its top, mono labels, bib figures, and the profile motif (blue fill, the ridden part vermilion, a bone dot with a tarmac halo).
  - **Figures:** a step's time left and a behind-your-best gap are vermilion; ahead-of-best is go-green.
  - **Status and zoom:** connection dots are go-green, and the zoom buttons are tarmac pills.
  - **Narrow screens:** under 520 pt (an iPhone upright), the band keeps the plan and drops the squeezed strip.
- **Controls panel:** a tarmac sheet (22-pt corners, a hairline, the sheet shadow) with ringed buttons, + in vermilion, and mono labels.
- **Hold-to-end ring:** fills in vermilion on glass.
- **"Time's up" prompt:** a tarmac sheet with a vermilion 0:00 and pills.
- **Face gallery chrome:** a vermilion bib for the face's number, a display name, mono labels, the pill switch, Customise as a glass pill, "Use this face" in vermilion, and moment chips in mono. The faces themselves are unchanged.
- **Home on an 11" iPad upright:** the device pill shows dots only, and today's figures move above its buttons when they don't fit beside them.

**D119. Widgets, Live Activity, Watch, and the audit.**
- **Tokens outside the app:** `Zmash/Shared/Brand.swift` holds the few tokens the widgets, Live Activity and Watch need, since they can't see `Design`. Archivo and JetBrains Mono are bundled in the widget extension and the Watch app, about 850 KB.
- **Live Activity:** tarmac, with power as a vermilion bib, the clock in mono, and mono labels.
- **Home and lock screen widgets:** keep the system's backgrounds, so they tint and go vibrant on the lock screen as iOS expects. They take bib numerals, mono labels, and the week's bars and form in vermilion.
- **Watch:** bib power in vermilion, a mono clock and mono labels.
- **Audit:**
  - **Covered:** screens checked at 11" and 13" iPad (landscape and portrait), iPhone 17 Pro, and light and dark.
  - **Fixes it led to:** the 11" portrait top bar (dots-only device pill), today's figures wrapping, the band on a narrow iPhone, and the Live ride's side numbers.
- **Where the app departs from the system:**
  - "Route scenery" on the Live ride is the road ahead drawn on the hatch, since there's no video.
  - Phones use a 16-pt gutter.
  - Faces keep their own type and colours.
  - The recap and ride postcard became hero cards (they had the Paper face's cream).
  - The face gallery keeps its dark scrim over the face.

**D120. The face gallery frames the face.**
- **Before:** the face filled the screen, and the details and buttons at the bottom covered its lower third.
- **Now:** the face is drawn at the ride screen's full size and scaled into a frame (22-pt corners, a hairline, the sheet shadow) in the upper part. The moments, the dots, the face's details and the buttons sit below it on tarmac, not over it.
- **Result:** what you browse is the whole face as it rides, band included.

**D121. No "pedal to start" overlay.** Before the first pedal stroke, the face shows as it is, with nothing over it; the clock still starts on the first stroke (D108). On Classic, the clock pulses until then.

**D122. Review fixes to the ride (2026-09-24).** From the full review:
- **3 s power:** the spike filter holds back one reading more than 3× the median and the last reading; a second in a row is a real effort and both count. Before, one rejected reading froze the average for the rest of the effort.
- **Cadence from crank data** (Cycling Power, older Wahoo) drops to 0 after 3 s with no new crank event, so auto-pause works and stopped cadence isn't recorded.
- **A pause is a stop:** the speed model halts on pause, and the ride picks up from standstill.
- **Letting go of the trainer:** ending a ride sends a flat, non-ERG target. Past a route's end ("keep riding") the road is flat. Below 20 rpm, ERG shifting asks for 0 W rather than keeping the last target.
- **Trainer negotiation:** ERG over FTMS needs the trainer's target-power feature. An unanswered Request Control is retried (with the control point re-subscribed). A silent Zwift handshake falls back to whatever else the trainer offers (FTMS, Wahoo or Tacx), in Auto and when Zwift is chosen. Finding nothing controllable retries discovery twice. Wahoo and Tacx no longer wait out the 3 s readiness timeout.
- **Controllers:** a dropout mid-hold releases the end-hold ring; an unanswered handshake is sent once more.
- **Sound:** ride sounds restart after a call or a route change, and the floating window always mixes with other audio, so starting a ride never stops music (sounds on or off).
- **Events:** an event that arrives while another is showing is shown next instead of lost (a kilometre split, a summit).
- **Also:** trainer-relayed heart rate clears after 5 s without a reading; the route's time left uses about the last minute's pace; successful ERG acknowledgements no longer fill the diagnostics log.

**D123. Review fixes to data and integrations (2026-09-24).**
- **Apple Health:** the switch stays on only if Health really allows writing workouts (the permission sheet finishing isn't enough), and says where to allow it if not. Failed saves go to the diagnostics log. The Watch keeps its own workout unless the iPhone can really save the ride.
- **Uploads:** the Strava redirect is `zmash://localhost`, inside the callback domain the help asks for. Upload state is per ride, and each ride remembers where it was sent (`sentTo`), so History shows it and auto-upload never sends twice. After a Strava upload, the app asks Strava a few times how processing went, so a duplicate or a bad file shows as an error. intervals.icu can be disconnected, and the Uploads screen updates on connect and disconnect.
- **Deleting a ride** asks first everywhere, and gives back what it counted for: its plan session goes back to not done, and if it was a campaign's latest stage, that stage is to ride again (stages go in order, so earlier ones stay). Campaign stages now remember their ride.
- **Home refreshes** ("this week", the Today card, the widgets) when a ride is saved or deleted, not only when the rider changes.
- **The ride store:** if it can't be opened, its files move to Files → Zmash → "Recovered rides …" and the app starts a new history, with an alert, rather than crash on every launch. Failed saves are logged. Crash recovery only offers the current rider's autosave. A versioned SwiftData schema wasn't added: it changes how the only copy of the rides is opened, and can't be tried on the iPad from here. It should come with the first change that needs a migration.
- **Removing a rider** also removes their upload tokens and keys (the keychain outlives the app).
- **Race catalog:** a campaign whose race can't be found is on hold, not finished. A load failure is logged. A test checks the bundled catalog decodes and keeps the ids the app uses.
- **Files:** plans, campaigns, routes and the widget summary are written atomically. The app's Documents folder shows in Files.
- **Leftovers:** Live Activities left by a crash are ended at launch. The Watch ends a workout after 3 minutes without word from the iPhone, has an End workout button, and a new ride replaces a stuck session.
- **Weeks start on Monday everywhere:** plan weeks, "Start next Monday", this week (Siri, home, widgets) and weekly progress, whatever the locale. The widgets start a new week at Monday midnight on their own.
- **Siri:** a request that arrives before the app has drawn (a cold launch) isn't lost; the app waits up to 20 s for the trainer before setting the ride up on home instead; asking for a ride during a ride says so.
- **Plans:** starting mid-week warns when week 1 will lose sessions, and ride days can be changed without leaving the plan.
- **Also:** one FTP and weight range for setup, Settings and new riders; "Manage riders…" opens the riders page; hiding the Today card is per rider.

**D124. Review fixes to the screens (2026-09-24).**
- **The face gallery on a phone:** below 760 pt wide the details and buttons stack under the face, with less padding, and the chevrons give way to swiping. Below 560 pt tall the description and moments are left out. The face's scale can't go to zero. Taking the second-to-last face out of rotation says why it can't.
- **Units:** Broadcast's last stretch is in metres (metric) or yards (imperial, over the last mile), each converted. Borne's stone is a French kilometre marker, so its numbers stay metric like its labels. Sensor speed and the calibration text follow the rider's units.
- **History:** a row shows all four numbers when they fit, and time and distance otherwise. Rows use the stored route name instead of loading the route. The calendar scrolls, works out the plan's days once, and out-of-month days are readable.
- **The ride:** swiping on the compact dashboard no longer changes the saved face unseen. Coaching and events show in the band even when it's narrow, and over the face when there's no band. A long custom main number shrinks on Paper, Kinetic, Horizon and Night rather than overflowing. Grades never read "-0.0". Time remaining rounds up the same way on every face. Horizon marks the summit just taken at the rider, not at the next high point.
- **Postcards** are titled with the route when there's no workout.

**D125. Review fixes for battery and smoothness (2026-09-24).**
- **Ambient motion only while riding:** Piste, Groupset, Tarmac and Night's animations stop when paused, done or waiting for the first stroke, and with Reduce Motion (DESIGN §4). Calm holds Piste and Tarmac still, as they have no quieter mode.
- **No timers left running:** the face name tag's 30 Hz timeline stops once it has faded (it used to run for the rest of the ride after the first face change).
- **Tarmac** casts its shadow from the numbers only, not over the 60 fps road.
- **Static artwork is its own view:** Piste's track and Borne's stone (136 weathering marks) redraw only when the theme or the stone changes, not on every tick. A course's face profile and climbs are worked out once per course.
- **The engine:** a trainer frame just after a loop tick no longer causes a second tick, and unchanged values aren't published again, so a paused ride doesn't redraw 14 times a second.
- **The floating window** renders its card every 5 s while hidden (twice a second while showing), plus a fresh frame when you leave the app.
- **Ride sounds** rest the audio engine after 4 s of silence and start it again with the next sound. The synthesiser's constants are no longer built on every sample.
- **Stored rides:** autosave every 30 s (leaving the app still saves at once). Samples and power curves are decoded once and kept in a small cache while their data is unchanged. History fetches only the current rider's rides. Campaigns are read from disk once until they change. The current plan is worked out once per rider and day. Each race's stage routes are built once. The famous climbs are sorted once.
- **Launch and Settings:** the race catalog loads off the main thread. The diagnostics report is written when you tap Share, not every time Settings draws. Chart scrubbing no longer re-buckets the ride.

**D126. Review polish (2026-09-24).**
- **Tokens:** body text on hero cards has its own token (`fgOnHeroBody`) instead of six hard-coded greys. The over-face glass in the gallery is `Tarmac.glass`. The gear ladder's unselected ticks are tarmac (they vanished in light mode). One colour map for link states: unpaired is grey everywhere, not red on the ride screen.
- **Touch:** compact pills and chips look as before but take a 44 pt touch. The recap's close button and the Classic gear buttons are 44 pt. The number tiles in Settings keep 32 pt buttons, since 44 pt ones don't fit three across on an iPhone.
- **VoiceOver:** each face reads as one summary (face, speed, watts, cadence, grade, time, gear). The gallery's dots and chevrons and the calendar's months are labelled. In Settings, the number itself is adjustable (swipe up or down).
- **Asking first:** deleting an imported route or one of your workouts, discarding edits in the workout builder, and "Set up again". Set up again, opened from Settings, can be left as it was.
- **States:** the pairing sheet says when Bluetooth is off or not allowed, and after 20 s without a device, what usually helps. History's empty state says what will be there. The floating window's error has a backing, so it reads over any face.
- **The band's messages** (coaching, kilometres, summits) are 15 pt, readable from the saddle.
- **Not done:** Dynamic Type outside the ride and Increase Contrast. The design system's fonts are built at fixed sizes, and scaling them needs a visual pass screen by screen. The ride screen's other 10–12 pt mono labels follow the design system, not DESIGN's 15 pt glance rule for faces; worth checking from the saddle before changing them.

**D127. Your data, and FIT both ways (2026-09-24).**
- **Backup and restore:** Settings → Your data → Back up to Files writes a folder in Files → On My iPad → Zmash → Backups: every rider's rides (samples included) as `rides.json`, the plan, campaign and route files, and the settings (riders, preferences, custom workouts). Restore picks such a folder and adds what this iPad doesn't have: rides by id, files by name, so restoring twice changes nothing. Riders and settings are restored only when asked, and take effect on the next launch. Upload tokens and keys stay in the keychain and aren't included.
- **Editing a saved ride:** how it felt (1–10) and its note can be added or changed from its page in History.
- **Apple Health for past rides:** a ride's page can save it to Health, and remembers that it's there, like uploads do. Rides saved to Health from the summary remember it too.
- **FIT export:** records carry altitude, climbed from each second's gradient and distance and starting at the route's real start height, so Strava and Garmin Connect show the ride's profile. A second without heart rate is written as FIT's "invalid", not 0 bpm. Pauses are still folded out: samples record active seconds only, so where the pauses fell isn't known.
- **FIT import:** files with developer fields (Connect IQ apps, Stryd) import correctly; their bytes were read as the next record's.
- **Files:** paths are read unencoded (`path(percentEncoded: false)`). Encoded, "Application Support" and "Zmash backup …" were never found.

**D128. "Ride this" rides; "Your ride" is one card (2026-09-24).**
- **"Ride this"** on the Today card starts the ride when a trainer is connected; without one, it sets the ride up on home, where the start bar asks to connect. A plan's "Ride this" does the same through the Siri path (`IntentRouter.ride`), which closes the sheets and waits a moment for the trainer.
- **"Your ride"** is one card: the options and the preview, split by a hairline, side by side when there's room and stacked otherwise.

**D129. Faces fill the width (2026-09-24).** The face canvas stays 834 pt tall, and its width follows the screen: 1194 on an iPad (the design), up to 3.4 × its height on a wider screen (`FaceCanvas.width(for:)`, carried as the `faceWidth` environment value). Faces lay out across it rather than letterboxing:
- **Stacks widen by themselves:** Paper, Kinetic (its numerals take 3/8 of the row each), Aura and the numbers on every face.
- **Artwork follows the width:** Horizon's and Night's ridges (`width / 60` a step), Night's streaks, Broadcast's profile (more road ahead at the same scale), Stem's card, Tarmac's road, and Piste's velodrome, whose straights lengthen.
- **Right-hand elements keep their place from the right edge:** Borne's stone, Groupset's drivetrain, the lap board, the right-hand number blocks. Moments follow: positions right of centre move with the right edge.
- **Safe areas:** on a phone, face content stays clear of the camera cutout and rounded corners at the sides, while the face's colour fills to the edges.

**D130. On an iPhone, faces ride on their side (2026-09-24).** Riding any face but Classic turns an iPhone to landscape (`OrientationLock`, through an app delegate), and faces only show on their side. Switching to Classic mid-ride lifts the lock; switching back turns again. Ending the ride lifts it without forcing the phone back. The iPad is unchanged: Split View still gets Classic.

**D131. The gallery on a phone (2026-09-24).** The gallery draws each face as it rides, on its side at the screen's size, then scales it into the frame.
- **Upright iPhone:** the face across the full width, with a short panel under it. The description is behind an ⓘ.
- **iPhone on its side:** the face on the left and a column of controls on the right (name, magic moment, dots, the rotation switch, Customise, Use).

**D132. The ride store is versioned (2026-09-24).** `RideSchemaV1` (1.0.0) and `RideMigrationPlan` (no stages yet) open the store. `RideSession` stays a top-level class, so the entity keeps its name. A later change SwiftData can't migrate by itself gets `RideSchemaV2` and a stage.
- **Tested in a fresh Simulator:**
  - rides seeded with the build from before this review (`e58f807`, unversioned, without `sentTo`) open under V1 with every ride and its samples;
  - they open again on a second launch;
  - a corrupted store is moved to Files and the app starts a new history, with the alert.
- **Recovery looked in the wrong place:** SwiftData keeps its default store in the App Group's container (the app has one for the widgets), so D123's recovery looked in the app's own Application Support and would have found nothing. It now looks in the group's. The alert is shown a moment after launch, since one presented during the first appear is dropped.

**D133. Pauses keep the wall clock (2026-09-24).** The engine notes how long each pause lasted on the first sample after it (`RideSample.pausedBefore`, inside the samples JSON, so the store's schema doesn't change). `RideTimeline` turns active seconds into wall-clock time.
- **FIT files:** records are timestamped as they happened, the timer stops and starts around each pause, and the elapsed time runs to the ride's real end while the timer time is the active time.
- **Apple Health:** samples on the wall clock, with pause and resume events.
- Rides from before this have no pauses noted and export as they did.

**D134. Every ride as FIT (2026-09-24).** Settings → Your data → Export rides as FIT writes the current rider's rides, one file each, to Files → Zmash → Exports, named by date, time and ride. `RideExport` makes the FIT for the share sheet, the uploads and this export alike.

**D135. Uploads that don't go through are tried again (2026-09-24).** Every upload is queued as it starts (per rider), so one cut off by the app being suspended or killed isn't lost.
- **Leaving the queue:** on success, or on an error that retrying won't fix (wrong keys, a bad file, a duplicate).
- **Retries:** no network, a timeout or the service being down (5xx, 429) waits 1 min, 5 min, 30 min, 2 h, then 12 h, then gives up and says so in the log. The queue is tried at launch, when the app comes back, and when the network returns (`NWPathMonitor`).
- **On screen:** the Uploads screen shows what's waiting, with "Try now", and a ride's page says "waiting to send".

**D136. The trainer's own gradient range (2026-09-24).** An FTMS trainer that says which gradients it can simulate (Supported Inclination Range, 0x2AD5) has the simulated gradient kept within that range, and never beyond the app's −10…+16 %. The range is logged and shown next to the protocol in Devices. A trainer that doesn't say gets −10…+16 %, as before. Not yet seen on hardware.

**D137. Text follows the text size setting (2026-09-24).** Text up to 24 pt scales with Dynamic Type (`UIFontMetrics`, body style), up to the second accessibility size. Titles and numbers above 24 pt stay as designed.
- **Fixed on the ride:** the ride screen and the face gallery keep the design sizes (`Design.RideFont`, and the `fixedType` environment for the labels and pills there), since they're read from the saddle and laid out to the point.
- **Redrawing:** home and the sheets are rebuilt when the setting changes (never the ride).
- **Layout pass** at the largest supported size, on iPhone and iPad:
  - the ride modes stack on a phone when three don't fit;
  - segmented tabs, tile labels and the start button shrink rather than cut words;
  - the iPad's top bar switches to the compact icon bar.
  - Everything is unchanged at the default size.

**D138. Increase Contrast (2026-09-24).** With it on:
- the quieter inks (`fg2`, `fg3`) and the hairlines (`border`, `borderStrong`) get stronger in both themes (`Color(light:dark:lightHigh:darkHigh:)`);
- every face switches to whichever of its palettes has the most contrast between ink and background (WCAG ratio), as DESIGN §4 asks.

**D139. Small improvements (2026-09-24).**
- **Borne on a wide canvas** (a phone on its side): the space between the numbers and the stone shows the next kilometres' gradients (up to six), coloured like the stones' caps, as on the boards at the foot of a climb. Only on a known course.
- **Tarmac's asphalt** is tiled across a wide canvas instead of stretched, and drawn at 2× rather than the screen's 3× (a third of the memory).
- **Aura** no longer blurs its full-screen mesh on every tick; the radial gradients are soft already.
- **Today's suggestion** is worked out once when home appears (the card and the widgets asked for it twice).
- **Ride-screen label sizes:** left until they've been checked from the saddle (TESTING.md, Ride 1).

**D140. Time in zones (2026-09-24).**
- **The zones:** power zones come from FTP (the faces' seven). Heart-rate zones are five, at 60 / 70 / 80 / 90 % of a maximum heart rate, which is now a per-rider setting (Settings → Rider). The setting suggests the highest heart rate held for 5 s in the last 90 days, only upwards: a ride can show the maximum is higher, never that it's lower. Until a maximum is set, heart-rate zones don't show.
- **Where they show:** a "Time in zones" card on the summary and on a ride's page (a stacked bar and the minutes per zone), and weekly hours per power zone on Progress, for the last 12 weeks.
- **How:** each ride's zones are worked out once and kept in `zones.json` (recomputed if FTP or the maximum changes), so Progress doesn't decode every ride. The store's schema doesn't change.

**D141. Routes from a link (2026-09-24).** Route picker → From a link takes a pasted link (or the clipboard, through a paste button, so iOS doesn't ask each time) and imports the route with its name.
- **Sources:** RideWithGPS routes and trips (public ones download as GPX), Komoot tours (public, or shared with a link: the share token is kept), Strava routes (through the API with the rider's own account), and any link to a GPX or FIT file.
- **Strava:** connecting now also asks to read routes (`read`); an account connected before is asked to reconnect.
- **Komoot** has no public API. The import uses the tour coordinates its website loads, so it could break if Komoot changes them.
- **How:** `RouteLink` (ZmashKit, tested on real link shapes) says what to download; the existing parsers read it.
- **Not tested:** against the real services from here (TESTING.md). A Share Extension ("Share → Zmash" from Safari or the Komoot app) is left for later.

**D142. Cadence: a quiet hint (2026-09-24).** The coach keeps to a cadence band rather than only noticing under 65 rpm, in ERG too, where a low cadence makes the trainer feel like a wall.
- **The band:** the rider's own (Settings → Coaching → Cadence, 80–95 rpm by default, moved 5 rpm at a time), or a workout step's. `.zwo` files carry it (`Cadence` ± 5, or `CadenceLow`/`CadenceHigh`; `CadenceResting` for recoveries), the builder can set it per step, and exports write it back.
- **When it speaks:** more than 3 rpm under or 5 over for 30 s of pedalling. Not in the first minute, the first 20 s of a step, or while sprinting or freewheeling. At most once every 3 minutes.
- **What it says:** one line in the band ("Cadence 72 · aim for 85–95"), with no sound and no buzz.

**D143. More training plans (2026-09-24).** Five more, on the same engine (your days, sessions that adapt):
- **Sweet spot base:** 6 weeks, 3 rides.
- **Short on time:** 4 weeks, 3 sessions of about 45 min.
- **Climber:** 6 weeks, a famous climb each weekend, ending on the Tourmalet.
- **Gran fondo:** 8 weeks, 3–4 rides, a long ride building to 3 hours, and Ventoux to finish.
- **Winter maintenance:** 4 weeks, 2 rides, to start again when it ends.

Plans now have a goal (Build, Climb, Endurance, Maintain), and the picker groups them by it. Each shows its weeks, rides a week and hours a week, and "Done before · 16 of 18" if you've been on it. Tests check that ids are unique, every week has at least two rides, Short on time stays under 50 minutes, and the gran fondo reaches 3 hours.

**D144. Home, revisited: three ways to ride, one place to choose (2026-09-24).** The big Today card pushed Free ride, Workout and Route into a narrow column, and the numbers on the four cards added nothing. Also, a free ride was set up on home, but a workout or route was chosen in a sheet.
- **No numbers** on the cards or the start bar.
- **The three ways to ride come first:** three equal cards across the width, each showing what's set up for it (the free ride's settings, the last workout or route) and its shape.
- **Today is a one-line strip** above them: why, the suggestion, its length and difficulty, and ↻, × and Ride this, which works as in D128.
- **The greeting and "This week" share a line.**
- **No sheet for choosing.** Switching to Workout or Route picks the last one this rider chose (or the library's first, and Mont Ventoux), so Start works straight away. "Your ride" shows the list on the left and the preview on the right:
  - **Workouts:** Plans (by goal), Library and Mine, with + for New and Import .zwo. A plan opens in the preview, where it's started. ERG or gradients sits under the workout's preview.
  - **Routes:** Climbs (by country), Races and Imported, with + for a GPX/FIT file or a link. A stage race lists its stages in place, with a back chevron, and its campaign opens in the preview.
  - **Which part of a route to ride** (full, or a window of 30 min to 2 h, dragged along the profile) is chosen in the preview. A long stage still starts on its last hour.
- **An iPad doesn't scroll.** On regular width, home fills the screen, and "Your ride" takes what's left: its list and preview scroll inside it if they need to. A phone, a narrow window or accessibility text sizes scroll as before.
- **Removed:** the workout and route pickers, the race and stage pages, and their debug screens. `-ZmashHomeShow plan|campaign` shows a plan or a campaign in home's preview instead.

**D145. History, Devices and Settings are pages, not sheets (2026-09-24).** The top bar's pills looked like navigation but opened a sheet over home. Now the four are peer pages:
- **The same top bar is on every page,** and its pill shows where you are. The wordmark goes home.
- **Each page has its own navigation stack,** so a ride, a setting or the riders list opens inside the page, with a back button.
- **On a phone:** the History and Settings icons light up on their page, and the device pill is outlined on Devices. Tapping the lit icon again goes home.
- **Riders, the face gallery, the hardware probe and first-run setup stay modal.** They're side trips, not places.
- **History is rebuilt when the rider changes,** since the rider menu is now on every page.

**D146. The face gallery is a page, with a slim bar under the face (2026-09-24).** It opened full screen over everything, and its lower part took nearly half the screen: the moments, big dots, a huge "02 Aura" with a paragraph, the mid-ride switch toggle and four large buttons.
- **A page inside Settings,** with the system back button to Settings. Use this face goes back too.
- **Two slim rows under the face:**
  - the moments (smaller) and the dots on one line;
  - the name, which face of how many and its magic moment, and the description (at most two lines), beside ‹ ›, Customise and Use.
- **The face gets the room back:** it's about a third larger on an upright iPad.
- **No number** before the name, as on home (D144).
- **"When switching faces mid-ride" moved into Customise:** it's a setting of the face, like its palette.

**D147. Home's top card is the training plan (2026-09-24).** The Today strip suggested a ride from your form. Now the card is only about the plan:
- **No plan:** "Pick a training plan". "Choose a plan" opens Workout → Plans in "Your ride", with the first plan in the preview, where it's started (days, this week or next). "Not now" (×) hides the card for this rider until a plan is started. The plans are still under Workout → Plans.
- **On a plan:**
  - the plan and week ("FTP Build · week 2 of 6") and this week's sessions as marks: done, today, to come, missed;
  - the next session, with "Today" or "Next · Thursday", its length, how it has adapted ("3 % harder") and its difficulty;
  - **Ride this** rides the next session not done, even a day ahead, and starts it with a trainer (D128);
  - **Plan** opens it in "Your ride", to see the week, change the days or leave. Starting another plan there says it ends the current one.
- **Plan finished:** "You finished <plan> · Pick the next one".
- **The readiness suggestions moved out of the view** (`Session/Today.swift`). Siri's "today's ride" and the Next up widget still use them, with the plan's session first.
- **The card follows plans started, left or ridden** through `PlanChanges`, bumped whenever an enrolment is saved.

**D148. Home is four cards, and each ride is chosen on its own page (2026-09-25).** Home had become busy (D144–D147): a plan strip, three mode cards, "Your ride" with a list and a preview, and a Start bar, all on one screen. Now one idea per screen:
- **Home asks *what kind of ride?*** Under the top bar and the greeting, it shows four cards and nothing else: Training plan, Free ride, Workout and Route. On an iPad they fill the screen two by two; on a phone or with large text they stack.
  - **Each card** has a title, one sentence about what it is and a picture (your last workout's shape, your last route's profile), and opens its page.
  - **The Training plan card is the hatch hero:** what a plan is, or, on one, the next session with this week's marks and **Ride this**. That's the only button on home, because it's the one ride already decided.
- **Each page asks *which one, exactly?*** It's pushed from home with the system bar (‹ Home, swipe back, the device dots on the right), and split into two cards: Choose on the left, the preview with Start (and ♡) on the right. The iPad page doesn't scroll; a phone stacks it, with Start pinned.
  - **Free ride:** Manual · Auto · Draw.
  - **Workout:** Workouts, the library in groups (Endurance, Tempo & sweet spot, Threshold, VO₂max, Sprints, Tests) · Favourites · Imported (was Mine). Plans are no longer here.
  - **Route:** Races · Favourites · Imported. The famous climbs left the page; they stay for Siri, Palmarès, the Climber plan and the suggestions.
  - **Training plan:** the plans by goal, and the plan in the preview (start it, or this week and Ride this).
- **Favourites are new:** ♡ on a row or by Start. They're kept per rider in UserDefaults, so the backup keeps them. A part of a route favourites the whole route.
- **The library grew from 9 to 19 workouts** (`Workout.Category`), so each group has 2–4. Existing ids didn't change, since plans refer to them.
- **Pages remember what you last chose,** and keep changes as they're made.
- **Siri, or a plan's Ride this without a trainer,** opens the ride on its page.
- **The monthly recap moved to History.**
- **Replaced:** `SetupView`, "Your ride", `ModeCard`, `StartBar`, `WorkoutBrowser`/`RouteBrowser` and the plan strip. Debug: `-ZmashOpen plan|free|workout|route`, with `-ZmashTab`.

## Known gaps (need the user's hardware)

Everything still to check on real hardware is in [TESTING.md](TESTING.md).
