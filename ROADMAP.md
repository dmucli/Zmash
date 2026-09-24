# Zmash — Roadmap

What comes after the MVP and the faces. `BRIEF.md` is the original spec (all of it is built), `DESIGN.md` covers the faces, and `DECISIONS.md` records how things were built. This file plans what's next.

Status legend: **Now** (next up) · **Next** · **Later** · **Maybe**.

---

## Where we are (2026-09-24)

**Built:** everything in the brief, phases 1–4 and 11–19: eleven ride faces plus Classic (now the design system's Live ride), with the whole app in the Zmash Design System, then a full review (bugs, performance, cleanup, backup).

**Proven on the iPad:** Ride + KICKR CORE 2 over FTMS, shifting, reconnect and the floating window.

**Not yet proven:**
- faces from the saddle;
- Apple Health;
- the Zwift trainer protocol;
- heart-rate straps, Zwift Play/Click and ERG (no hardware);
- multi-ride reliability.

**Not in place:**
- a distribution path beyond 7-day free signing.

The code is on GitHub, and CI (ZmashKit tests and a Simulator build with the newest Xcode) has been green since 2026-09-24.

The next phases, in order:

| Phase | Theme | Why now | Status |
|---|---|---|---|
| 5 | Foundations | Protect the work; ride longer than 7 days | **Done** (2026-09-22) |
| 6 | Ride-proofing | Turn Simulator-verified into bike-verified | **Waiting on rides** |
| 7 | Training value | Give each ride a purpose beyond "ride for 45 min" | **Done** (2026-09-22) |
| 8 | Real routes | Ride real climbs, not just generated terrain | **Done** (2026-09-22) |
| 9 | Ecosystem | Your rides end up where your other training lives | **Done** (2026-09-22) |
| 11 | Face customisation | Make all six faces yours, not just Classic | **Done** (2026-09-22) |
| 12 | Reach and polish | Real climbs, no overlaps anywhere, more trainers and sensors, iPhone and Mac | **Done** (2026-09-23) |
| 13 | A reason to ride | Draw fix, Today card, palmarès, recaps, first-run setup | **Done** (2026-09-23) |
| 14 | The Tour | Grand Tour campaigns, gentle coaching | **Done** (2026-09-23) |
| 15 | Alive | Sound, trainer calibration, Siri and Shortcuts | **Done** (2026-09-23) |
| 16 | Coach | Training plans, workout builder | **Done** (2026-09-23) |
| 17 | Everywhere | Live Activity, widgets, Apple Watch | **Done** (2026-09-23; Watch unverified on hardware) |
| 18 | Design system | The whole app in the Zmash Design System; Classic as the Live ride | **Done** (2026-09-23) |
| 19 | Review | Bugs, performance, cleanup, backup, from a read of the whole app | **Done** (2026-09-24) |
| 20 | Riding with purpose | Time in zones, routes from a link, a cadence hint, more plans | **Planned** |
| 10 | Release | TestFlight for friends, then maybe the App Store | **Skipped** (personal use, no paid account) |
| — | Ideas parking lot | Worth keeping, not planned | **Maybe** |

---

## Phase 20 — Riding with purpose *(Planned)*

Four features, in this order. Each is its own commit and DECISIONS entry, with unit tests for the logic in ZmashKit and a Simulator check of the screens.

### 20.1 Time in zones

The rides already record power and heart rate every second; nothing shows where the effort went.

- **Power zones** come from FTP, as the faces already use (`PowerZones`, 7 zones).
- **Heart-rate zones** need a maximum:
  - a per-rider "Max heart rate" in Settings → Rider, next to FTP and weight;
  - suggested from the highest reading of the last 90 days, with a "Set 186 bpm" button like the FTP estimate on Progress;
  - five zones at 60 / 70 / 80 / 90 % of max;
  - until it's set, heart-rate zones don't show.
- **Where they show:**
  - the summary after a ride, and a ride's page in History: a "Time in zones" card, one stacked bar per kind (power; heart rate when recorded), with minutes per zone underneath;
  - Progress: weekly time in each power zone for the last 12 weeks, as stacked bars under Weekly time.
- **How:**
  - `Zones.seconds(samples:ftp:)` and `Zones.heartSeconds(samples:maxHR:)` in ZmashKit, with tests;
  - per-ride results kept in a small file cache keyed by ride (the samples don't change once saved), so Progress doesn't decode every ride's samples;
  - no change to the ride store's schema.

### 20.2 Import a route from a link

Today a route comes from a GPX or FIT file saved to Files first. Pasting its link should be enough.

- **Where:** Route picker → "From a link". The field fills in from the clipboard when it holds a link it knows (a paste button, so iOS doesn't ask each time).
- **Sources:**
  - **RideWithGPS** routes: public ones download as GPX from `ridewithgps.com/routes/<id>.gpx`.
  - **Komoot** tours: public tours, and private ones shared with a link (the `share_token` is kept), come from Komoot's tour coordinates (latitude, longitude, altitude).
  - **Strava** routes: through the API with the rider's own Strava account. That needs Strava's `read` permission, so connecting asks for it; accounts connected before get a "Reconnect" prompt.
  - **Any link ending in .gpx or .fit.**
- **How:**
  - `RouteLink` in ZmashKit turns a link into what to download (source, id, URL), tested on real link shapes (with and without language prefixes and query strings);
  - the download goes through the existing parsers (`GPXParser`, `FITRouteReader`) and `RouteStore.save`;
  - the route keeps its name from the source.
- **Errors, in words:** "This route is private", "No elevation in this route", "Not a route link".
- **Later, if wanted:** a Share Extension, so "Share → Zmash" works from Safari and the Komoot app.

### 20.3 Cadence: a subtle hint

The coach already says something when cadence sits under 65 rpm for a minute, outside ERG. It becomes a target band, and it works in ERG too (where low cadence makes the trainer feel like a wall), but stays discreet.

- **The band:**
  - a per-rider cadence target in Settings → Coaching, 80–95 rpm by default;
  - a workout step can set its own: `.zwo` files carry `Cadence` / `CadenceLow` / `CadenceHigh`, which the importer keeps (`Workout.Step.cadence`), and the builder can set it per step.
- **When it speaks:**
  - out of the band (by more than a few rpm) for 30 s of pedalling;
  - not in the first minute, not in the 20 s after a step changes, not while freewheeling or sprinting;
  - at most once every 3 minutes.
- **What it says:** one line in the band, e.g. "Cadence 72 · aim for 85–95". No sound and no buzz. It replaces today's "under 65" rule.
- **Tests:** in `CoachTests`: the band, the quiet times, the spacing, ERG and not.

### 20.4 More training plans

The plan engine (weeks of sessions on your days, adapting after each one) is there; there are four plans.

- **New plans:**
  - **Sweet spot base** (6 weeks, 3 rides): sweet spot sets that lengthen, one endurance ride, a lighter week 4.
  - **Climber** (6 weeks, 3 rides): long threshold and over-unders, with a famous climb as the weekend ride, ending on the Tourmalet.
  - **Gran fondo** (8 weeks, 3–4 rides): endurance building to 3 hours, tempo, and a long stage segment as the rehearsal.
  - **Short on time** (4 weeks, 3 × 45 min): VO₂ and threshold packed into short sessions.
  - **Winter maintenance** (4 weeks, 2 rides, repeatable): enough to keep FTP through a busy month.
- **The plan picker:**
  - groups plans by goal (Build, Climb, Endurance, Maintain);
  - shows weeks, rides a week and hours a week for each;
  - says which one you've done before, and how it went.
- **How:**
  - plans are data in `TrainingPlans` (ZmashKit);
  - the existing test that every session points at a real workout or climb covers them;
  - a test checks each plan's weekly hours.

**Done when:** each of the four is in the app, tested, and noted in DECISIONS.

---

## Phase 5 — Foundations *(Done, 2026-09-22)*

Low effort, high protection. Nothing visible, everything safer.

1. **Git + GitHub** (private repo).
   - `.gitignore` already excludes generated and build files.
   - Reference folders (`bikecontrol-main`, `Zword…`) move out of the repo or into `reference/`, ignored, because bikecontrol's licence forbids redistribution.
   - First commit, then small commits per change from here on.
2. **CI:** a GitHub Action that runs `swift test` for ZmashKit and a Simulator build on each push. It catches regressions without the iPad.
3. ~~**Apple Developer Program**~~ — **declined**: personal use only, so installs are renewed with `make install` every 7 days. Phase 10 is off the table with it.
4. **Crash and diagnostic capture:**
   - an in-app "Export diagnostics" (last ride's log + device and firmware info), extending the probe log;
   - so a bug found on the bike can be sent without Xcode.

**Done when:** the code is on GitHub, CI is green, and an install lasts a year (if the account is bought).

---

## Phase 6 — Ride-proofing *(Waiting on your rides)*

Everything only checked in the Simulator gets checked on the bike. The protocol (three rides, then the checks away from the bike, the iPhone, Watch and widgets, and hardware you may not have) is in [TESTING.md](TESTING.md). Findings go into `DECISIONS.md`, and the fixes into one session after the rides.

**Done when:** the rides are logged in TESTING.md, and the issues found are fixed or recorded in `DECISIONS.md`.

---

## Phase 7 — Training value *(Done, 2026-09-22)*

All four parts are built and in the app: FTP estimate and ramp test, the workout library with `.zwo` import and both ERG and gradient targets, the shared target layer on every face, the Progress tab (power curve, PBs, weekly load) and the shareable postcard. Details in `DECISIONS.md` D48–D55. What's left for the bike: ERG has only been exercised against the demo trainer.


The app records well; now it should make you fitter, with the same minimal style. The effort data (power, FTP, zones) is already there.

1. **FTP from rides.**
   - Estimate FTP from your best 20-minute power (× 0.95) across saved rides.
   - Offer an update when it changes by more than 3 %.
   - An optional guided **ramp test** (1-min steps, ERG, stop when cadence drops); FTP = 75 % of the best 1-minute power.
2. **Structured workouts.**
   - A small library (endurance, tempo, sweet spot, VO₂ intervals, over-unders).
   - Two ways to drive the trainer:
     - **Grade-driven:** hills as intervals. The rider keeps shifting, so it stays on-brand.
     - **ERG-driven:** fixed power. The trainer holds the target and shifting is disabled.
   - The faces get a **target** layer: target power and time left in the interval, styled per face (Aura is target-zone colour vs actual, Paper is a stepped bar, Night a glowing band).
   - An import format: `.zwo` (Zwift's workout XML, widely shared) for bringing in existing workouts.
3. **Records and trends.**
   - A power curve (best 5 s, 1 min, 5 min, 20 min, 60 min), all-time and 90-day.
   - Personal bests celebrated in the summary.
   - Weekly totals (time, kcal, TSS) in History, and a TSS / fitness trend.
4. **Summary postcard** (from `DESIGN.md` §9): the end-of-ride screen rendered in the face you rode with, shareable as an image.

**Built both ways** (ERG where the trainer supports it, gradients otherwise), and the ramp test is in the library.

---

## Phase 8 — Real routes *(Done, 2026-09-22)*

Built: GPX and FIT import, seven bundled routes (five famous climbs, two invented), distance-based rides with the real profile on every face, and the ghost of your quickest attempt. Details in `DECISIONS.md` D56–D62.


The auto-terrain generator becomes one option among several.

1. **GPX / FIT route import** (Files, or share from Komoot/Strava/RideWithGPS).
   - Grade by distance, smoothed.
   - The ride then follows the route's **distance** rather than time, and faces show the real profile.
   - Remaining distance replaces remaining time.
2. **A curated climb library** bundled offline. Profiles only; no maps or video. (Since D82: real profiles cut from the race files, not approximations.)
3. **Horizon gets the route:** the ridge becomes the real climb, with a summit marker at the real top, km-to-go and altitude.
4. **Ghost of your last attempt** on the same route: ahead or behind in seconds. It's a quiet line in Paper and a second dot in Horizon and Night.

**Settled:** no map or Street View imagery. The profile is the picture.

---

## Phase 9 — Ecosystem *(Done, 2026-09-22)*

**Built:** Strava upload (your own API app, OAuth) and intervals.icu upload (athlete ID + API key), per ride or automatically on save, with the FIT export kept as the fallback. Settings → Uploads.

**Not built, and why** (D64–D66): iCloud sync needs the paid account; TrainingPeaks' upload API is partner-only. (The Watch app and Live Activity, set aside here, came in Phase 17.)

**Untested:** neither upload has run against a real account yet — that needs your Strava API app and intervals.icu key.

---

## Phase 11 — Face customisation *(Done, 2026-09-22)*

Built: per-face palettes (three or four each, light and dark), per-face metric slots, and a Customise sheet in the gallery that edits the face live. Details in `DECISIONS.md` D67–D70.


Today only Classic is customisable. Every face should be: its palette, its numbers and how much it moves — without losing what makes each one itself.

1. **Per-face settings**, edited from the gallery: a palette (each face's own set, plus light/dark), the metrics in its secondary slots, and its accent.
2. **What stays fixed:** each face's layout and typeface. Customising a face shouldn't turn it into another face.
3. **Presets:** each face ships with two or three palettes; "reset to default" is always one tap away.
4. **Storage:** per-face settings in `Preferences`, keyed by face, with sensible defaults, so an unconfigured face looks exactly as it does today.

---

## Phase 18 — The design system *(Done, 2026-09-23)*

`design/Zmash Design System/` is the app's look from now on. The 11 faces keep theirs; everything around them follows the system, and so do the band and controls panel under them.
1. **Tokens and components** (D113, D114): bone to tarmac with vermilion and team blue, Archivo bib numerals, JetBrains Mono labels, pills, cards with bib indexes, hatch, grain and the tri-stripe.
2. **Home** (D115): the prototype's top bar, greeting and hero card, with the three ways to ride as cards 02–04.
3. **Pickers, Devices, Settings, setup** (D116): card grids, Settings in two columns, forms in the system's look.
4. **History, summary and the rest** (D117): the summary after the prototype, Palmarès, recaps, plans, campaigns and the builder in the system's spirit.
5. **The ride** (D118): Classic rebuilt as the Live ride; the band, panel and prompts always tarmac.
6. **Widgets, Live Activity, Watch, and an audit** (D119).

---

## Phases 13–17 — From working to loved *(done, 2026-09-23)*

The full scope, with what each feature does and how, is in the plan agreed on 2026-09-23. In short:
- **13, a reason to ride:** Draw rides as steep as you draw (D89), the Today card (D90), Palmarès (D91), recaps (D92), first-run setup (D93).
- **14, the Tour:** stage races as campaigns against 20 invented rivals, with general and mountains classifications and a podium card (D96); gentle coaching in the band (D97). Also a 1–5 difficulty rating on the ride card (D94) and Stop session (D95).
- **15, alive:** ride sounds synthesised live (D98); spin-down calibration for FTMS and Tacx (D99); Siri and Shortcuts (D100).
- **16, coach:** training plans that adapt, on your days and the calendar (D101); a workout builder with .zwo export (D102).
- **17, everywhere:** Live Activity on iPhone (D103), widgets through an App Group (D104), Apple Watch heart rate and controls (D105).

---

## Phase 12 — Reach and polish *(Done, 2026-09-23)*

1. **Real climbs** (D82): twenty famous climbs cut from the race files by their summits; the approximate ones are gone.
2. **One band for ride context** (D83): route, workout, events and links under the face; nothing floats over it.
3. **SwiftUI hygiene and a screen audit** (D84, D85): stable identity everywhere; equal-width number rows; portrait home; honest flat cards.
4. **Older trainers** (D86): Wahoo's pre-FTMS control and Tacx FE-C. **Sensors** (D87): power meters with ERG matched to them, speed/cadence sensors, basic trainers from wheel speed.
5. **iPhone and Mac** (D88): the same app; faces in landscape, the compact dashboard upright; the Mac runs the iPad build.

Not proven on hardware: the Wahoo and Tacx protocols, power meters, sensors and basic trainers (Phase 6 covers them).

---

## Phase 10 — Release *(Skipped)*

You've decided Zmash is for your own bike, with free signing and no paid account, so TestFlight and the App Store are out. Kept below for the day that changes.

1. **TestFlight** for a handful of Zwift Ride / KICKR owners, with a feedback form. This is the best way to find controller and trainer firmware differences you can't test.
2. **App Store readiness:**
   - **Name & icon:** no "Zwift" branding in the name, icon or screenshots; "works with Zwift Ride" wording only.
   - **Onboarding:** first-run pairing flow, Bluetooth permission copy, and a demo mode for reviewers without hardware.
   - **Privacy:** a privacy manifest ("data not collected"); the Health usage text reviewed.
   - **Localisation:** at least English + French.
   - **Accessibility audit:** VoiceOver on setup, history and settings; Dynamic Type outside the ride screen.
   - **Pricing:** free, one-time purchase or subscription. A decision for later.
3. **Risk to accept:** Zwift can change controller firmware at any time (see U1). Store users will update their firmware; you won't. Mitigations:
   - on-screen controls always work;
   - a firmware-version warning is already in place;
   - FTMS keeps the trainer working regardless.

---

## Ideas parking lot *(Maybe)*

- **Face-styled floating window:** each face renders its own PiP card.
- **Chronograph, Tape, Segments faces:** skipped; revive only on demand.

Built since the review (D128–D138): faces on the iPhone, pauses in FIT and Health, exporting every ride as FIT, an upload retry queue, the trainer's own gradient range, a versioned ride store, Dynamic Type and Increase Contrast.

---

## Where the work goes next

1. **Phase 6** whenever you ride: everything to check is in [TESTING.md](TESTING.md).
2. **A backup** from Settings → Your data, now and then, copied off the iPad.
3. **Phase 20:** time in zones, routes from a link, a cadence hint, more plans.
