# Zmash — Roadmap

What comes after the MVP and the faces. `BRIEF.md` is the original spec (all of it is built), `DESIGN.md` covers the faces, and `DECISIONS.md` records how things were built. This file plans what's next.

Status legend: **Now** (next up) · **Next** · **Later** · **Maybe**.

---

## Where we are (2026-09-22)

**Built:** everything in the brief, phases 1–4, and five ride faces plus Classic.

**Proven on the iPad:** Ride + KICKR CORE 2 over FTMS, shifting, reconnect and the floating window.

**Not yet proven:**
- faces from the saddle;
- Apple Health;
- the Zwift trainer protocol;
- heart-rate straps, Zwift Play/Click and ERG (no hardware);
- multi-ride reliability.

**Not in place:**
- version control;
- a distribution path beyond 7-day free signing.

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
| 17 | Everywhere | Live Activity, widgets, Apple Watch | Next |
| 10 | Release | TestFlight for friends, then maybe the App Store | **Skipped** (personal use, no paid account) |
| — | Ideas parking lot | Worth keeping, not planned | **Maybe** |

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

The protocol below is ready to run; nothing more can be built for it from here. Findings go into `DECISIONS.md`, fixes into a session after the rides.

Everything that's only been checked in the Simulator gets checked on the bike, with a short protocol so each ride tests something specific.

**Ride 1 — faces.** 45 min, Auto terrain, Hilly; switch face every ~8 min with the D-pad. Check:
- Readability at ~80 cm, mid-effort: hero number, gear, grade.
- Aura/Night smoothness, and battery drop over the ride (target ≤ 15 % above screen-on).
- Events: kilometre splits, summits, session best (do they feel earned or noisy?).
- The floating window with YouTube: does the sound keep playing?

**Ride 2 — trainer.**
- 20 min with the **Zwift trainer protocol**, then 20 min on FTMS, to compare shifting feel.
- Pedal-stroke start and auto-pause on descents.

**Ride 3 — edges.**
- Turn the trainer off mid-ride, background the app for 10 min, let the controller battery run low.
- Save to Apple Health, then check the Fitness app.

**Then fix what the rides reveal.** Budget one session. Likely candidates:
- face font sizes for distance;
- FTMS effective-grade tuning;
- event thresholds;
- energy (lower the frame rate of heavy faces).

**Done when:** all three rides are logged and the issues found are fixed or recorded in `DECISIONS.md`.

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

**Not built, and why** (D64–D66): iCloud sync needs the paid account; TrainingPeaks' upload API is partner-only; the Watch app and Live Activity need a second target, a watch, and duplicate the floating window.

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

## Phases 13–17 — From working to loved *(13–16 done, 2026-09-23)*

The full scope, with what each feature does and how, is in the plan agreed on 2026-09-23. In short:
- **13, a reason to ride:** Draw rides as steep as you draw (D89), the Today card (D90), Palmarès (D91), recaps (D92), first-run setup (D93).
- **14, the Tour:** stage races as campaigns against 20 invented rivals, with general and mountains classifications and a podium card (D96); gentle coaching in the band (D97). Also a 1–5 difficulty rating on the ride card (D94) and Stop session (D95).
- **15, alive:** ride sounds synthesised live (D98); spin-down calibration for FTMS and Tacx (D99); Siri and Shortcuts (D100).
- **16, coach:** training plans that adapt, on your days and the calendar (D101); a workout builder with .zwo export (D102).
- **17, everywhere:** Live Activity on iPhone, widgets (if the free account allows App Groups), Apple Watch heart rate and rings.

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
- **Sound:** subtle optional cues (interval start, summit), off by default.
- **Cadence coaching:** a gentle hint when cadence drifts from a target band.
- **Multi-rider:** profiles on a shared iPad.
- **Chronograph, Tape, Segments faces:** skipped; revive only on demand.

---

## Where the work goes next

1. **Phase 8:** GPX/FIT import → climb library → Horizon on the real route → ghost.
2. **Phase 9:** Strava and intervals.icu upload. iCloud sync needs the paid account, so it waits.
3. **Phase 6** whenever you ride: the protocol is ready, and fixes follow your notes.
