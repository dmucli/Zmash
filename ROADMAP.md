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
| 5 | Foundations | Protect the work; ride longer than 7 days | **Now** |
| 6 | Ride-proofing | Turn Simulator-verified into bike-verified | **Now** |
| 7 | Training value | Give each ride a purpose beyond "ride for 45 min" | **Next** |
| 8 | Real routes | Ride real climbs, not just generated terrain | **Next** |
| 9 | Ecosystem | Your rides end up where your other training lives | **Later** |
| 10 | Release | TestFlight for friends, then maybe the App Store | **Later** |
| — | Ideas parking lot | Worth keeping, not planned | **Maybe** |

---

## Phase 5 — Foundations *(Now, ~1 session)*

Low effort, high protection. Nothing visible, everything safer.

1. **Git + GitHub** (private repo).
   - `.gitignore` already excludes generated and build files.
   - Reference folders (`bikecontrol-main`, `Zword…`) move out of the repo or into `reference/`, ignored, because bikecontrol's licence forbids redistribution.
   - First commit, then small commits per change from here on.
2. **CI:** a GitHub Action that runs `swift test` for ZmashKit and a Simulator build on each push. It catches regressions without the iPad.
3. **Apple Developer Program** (€99/yr, your call). It ends the 7-day re-install and unlocks TestFlight (Phase 10). Nothing in the code depends on it.
4. **Crash and diagnostic capture:**
   - an in-app "Export diagnostics" (last ride's log + device and firmware info), extending the probe log;
   - so a bug found on the bike can be sent without Xcode.

**Done when:** the code is on GitHub, CI is green, and an install lasts a year (if the account is bought).

---

## Phase 6 — Ride-proofing *(Now, 2–3 real rides + fixes)*

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

## Phase 7 — Training value *(Next)*

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

**Open questions:**
- Grade-driven or ERG workouts first?
- Is a ramp test something you'd actually do?

---

## Phase 8 — Real routes *(Next)*

The auto-terrain generator becomes one option among several.

1. **GPX / FIT route import** (Files, or share from Komoot/Strava/RideWithGPS).
   - Grade by distance, smoothed.
   - The ride then follows the route's **distance** rather than time, and faces show the real profile.
   - Remaining distance replaces remaining time.
2. **A curated climb library** bundled offline: Alpe d'Huez, Ventoux, Stelvio, Tourmalet and a few flat classics. Profiles only; no maps or video.
3. **Horizon gets the route:** the ridge becomes the real climb, with a summit marker at the real top, km-to-go and altitude.
4. **Ghost of your last attempt** on the same route: ahead or behind in seconds. It's a quiet line in Paper and a second dot in Horizon and Night.

**Open question:** worth adding map/Street View imagery later, or keep it strictly abstract? (The recommendation is abstract; it's the brand.)

---

## Phase 9 — Ecosystem *(Later)*

1. **Strava direct upload** (OAuth; needs a Strava API app registration). An auto-upload toggle, with the FIT export kept as a fallback.
2. **intervals.icu / TrainingPeaks:** upload, and for TrainingPeaks, pull the planned workout of the day into Phase 7's workout player.
3. **iCloud sync of ride history** (SwiftData + CloudKit) across iPad, iPhone and Mac.
4. **Apple Watch heart rate** via a small watchOS companion, for riders without a strap.
5. **Live Activity / Lock Screen:** a compact ride status on the iPhone or iPad Lock Screen during a ride.

---

## Phase 10 — Release *(Later)*

Only if you want Zmash beyond your own bike.

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

- **Per-face customisation:** palettes and complication slots per face (`DESIGN.md` §10); Classic already has it.
- **Face-styled floating window:** each face renders its own PiP card.
- **Sound:** subtle optional cues (interval start, summit), off by default.
- **Cadence coaching:** a gentle hint when cadence drifts from a target band.
- **Multi-rider:** profiles on a shared iPad.
- **Chronograph, Tape, Segments faces:** skipped; revive only on demand.

---

## Suggested order

1. **Phase 5** now (one session).
2. **Phase 6** over your next three rides.
3. **Phase 7:** FTP estimate → power curve and PBs → structured workouts → postcard.
4. **Phase 8:** GPX import → climb library → ghost.
5. **Phases 9–10** as needed.

## Decisions needed from you

1. Set up **git + a private GitHub repo** now? (Recommended.)
2. Buy the **Apple Developer Program**?
3. After ride-proofing, which next: **Phase 7 (training)** or **Phase 8 (routes)**?
4. Workouts: **grade-driven**, **ERG**, or both?
5. Is Zmash **just for you**, or should Phase 10 (TestFlight, and maybe the App Store) stay on the table?
