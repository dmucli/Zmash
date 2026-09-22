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

## Known gaps (need the user's hardware)

| Item | What to check |
|---|---|
| M0 probe checklist | Run Settings → Hardware probe once; export the log. |
| Zwift trainer protocol on CORE 2 | Devices → Advanced → Trainer protocol → Zwift: does shifting feel native? |
| PiP audio | YouTube sound plays normally with the floating window up. |
| Apple Health | Turn on, ride, check Fitness shows an indoor cycling workout. |
| Zwift Play / Click, HR strap, ERG | No hardware here; decoders are unit-tested only. |
| Faces on device | Legibility of each face from the saddle at ~80 cm; Aura and Night smoothness and energy over a real ride. |
