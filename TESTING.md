# Zmash — testing on real hardware

Most of the app has only run in the Simulator and in unit tests. This file lists everything still to check on the iPad, the iPhone, the Watch and the bike.

Tick a box when a check passes. When one doesn't, write down what you saw next to it and export the diagnostics (see below).

- **Last updated:** 2026-09-24, after D147.
- **Hardware assumed:** KICKR CORE 2, Zwift Ride (firmware 1.2.0), iPad, and an iPhone and Apple Watch if you have them.

---

## Before you start

- [ ] **Back up.** Settings → Your data → Back up to Files, then copy the folder somewhere off the iPad (AirDrop to the Mac, or iCloud Drive). This build opens your rides with the new versioned store (D132). It passed an upgrade test in the Simulator, but it's still your only copy.
- [ ] **Install** with `make install DEVICE=<id>`, and open the app once before riding.
- [ ] **Rides still there:** History shows your rides, and one opens with its charts. If they don't open, the app shows "Your rides couldn't be opened" and keeps the old store in Files → Zmash → Recovered rides. Stop there and send it.
- [ ] **Close Zwift and Zwift Companion.** The Ride controller only talks to one app at a time.

### After each ride

- **Export diagnostics:** Settings → Export diagnostics, then share to Notes or AirDrop. It holds the connection log, the protocol used, pauses, uploads and anything that went wrong.
- **Notes:** write a line per failed check here: what you did, what you expected, what happened.

---

## Ride 1 — faces (about 45 min)

**Set-up:** Free ride → Auto terrain, Hilly, 45 min. Switch face every 5–8 minutes with the D-pad, through all eleven.

**Reading from the saddle** (iPad on the bars, about 80 cm):

- [ ] The main number reads at a glance, mid-effort, on every face.
- [ ] Gear and gradient read without leaning in.
- [ ] Labels (the small mono text: WATTS, RPM, the band's labels). They're 10–12 pt; DESIGN asks for 15. Note any face or place where they're too small. This decides whether they're made larger.
- [ ] Classic (the Live ride) reads at a glance, and so does its controls panel (press A).
- [ ] Band messages: kilometre splits, summits and coaching notes read at a glance (they're now 15 pt).

**Motion and battery:**

- [ ] Aura and Night move smoothly the whole time.
- [ ] Battery: note the level at the start and end. Target: no more than 15 % above the screen being on.
- [ ] Pause the ride: the moving faces (Piste, Groupset, Tarmac, Night's streaks) stand still until you pedal again.

**Moments:**

- [ ] Kilometre splits, summits and "session best" appear, and feel earned rather than noisy.
- [ ] A kilometre that falls while another message is showing still appears right after it (D122).

**Floating window:**

- [ ] Leave the app mid-ride with YouTube or music playing: the floating window appears, and the video's or music's sound keeps playing (D122).
- [ ] Its play/pause button pauses the ride.

---

## Ride 2 — trainer (about 45 min)

**Protocols:**

- [ ] 20 min on the Zwift trainer protocol (Devices → Advanced → Trainer protocol → Zwift), then 20 min on FTMS. Compare how shifting feels.
- [ ] Devices → Trainer shows its gradient range, e.g. "FTMS · −10 to +20 %", and the diagnostics log has a "gradient range" line (D136). If there's no range, the trainer doesn't report one, which is fine.

**Starting and stopping:**

- [ ] The ride starts on the first pedal stroke.
- [ ] Stop pedalling on the flat: after about 5 s the ride auto-pauses, and the cadence shows 0 rather than your last cadence (D122).
- [ ] Coast down a descent: the ride doesn't auto-pause while you're rolling.
- [ ] Resume after a pause: speed picks up from a standstill, not from where it was (D122).

**Power:**

- [ ] Sprint from easy spinning (about 100 W) to over 400 W: the 3 s watts follow you up and don't freeze at the low value (D122).

**Cadence** (Settings → Coaching messages → Cadence on):

- [ ] Ride 30 s well below your band (Settings shows it, 80–95 by default): one quiet line in the band ("Cadence 72 · aim for 80–95"), no sound, and not again for 3 minutes (D142).

**ERG** (a workout with Targets: ERG, e.g. Sweet spot):

- [ ] The trainer holds each target.
- [ ] The shifters nudge the intensity ±5 %.
- [ ] Stop pedalling during an effort, then restart: the restart isn't against the full target (D122).
- [ ] At the end of an ERG workout, the trainer lets go: resistance drops to a flat road, even on the summary screen (D122).

**Routes:**

- [ ] A route's end: finish a short climb, choose Keep riding, and the road goes flat rather than staying at the last gradient (D122).

**Calibration:**

- [ ] Devices → Calibrate (spin-down): each step shows, and success sets the date.

---

## Ride 3 — edges (about 40 min)

**Losing the trainer and the controller:**

- [ ] Turn the trainer off mid-ride. The ride keeps going at zero power and auto-pauses after a minute. Turn it back on: it reconnects and the ride goes on.
- [ ] Hold B (end) and turn the controller off before the ring fills: the ring goes away (D122).

**Leaving the app:**

- [ ] Background the app for 10 minutes mid-ride, then come back: the ride is still there, and the time adds up.
- [ ] Let the controller battery run low, if convenient: below 15 % the controller's status on home turns amber ("Battery 12 %"), and the on-screen controls still work.

**Pauses and uploads:**

- [ ] Pause for 3–5 minutes on purpose, ride on, finish, and save. Upload to Strava: its elapsed time includes the pause, and its moving time doesn't (D133). Then export the FIT (from the ride's page) and open it in Garmin Connect or intervals.icu: the same holds.

**Sound:**

- [ ] With ride sounds on, connect AirPods mid-ride (or take a phone call): the sounds come back after (D122).

**Apple Health:**

- [ ] Settings → Save rides to Apple Health, decline when asked: the switch stays off and says where to allow it (D123). Then allow it.
- [ ] After a ride, the Fitness app shows an indoor cycling workout, with the pause in it (D133).
- [ ] A ride saved before Health was on: open it in History → Save to Apple Health, and it says "In Apple Health" (D127).

---

## Away from the bike

### Your data

- [ ] Settings → Your data → Export rides as FIT: the folder in Files has one `.fit` per ride, and one opens in Strava or Garmin Connect (D134).
- [ ] Restore from a backup: pick the backup folder, and it says "0 rides" added (everything is already there). Restoring twice changes nothing (D127).
- [ ] Deleting a ride asks first. If it counted for today's plan session, that session is back to do (D123).
- [ ] Change how a ride felt (History → a ride → Edit how it felt) (D127).

### Uploads

- [ ] Strava: connect (the callback domain on strava.com/settings/api must be `localhost`), send a ride, and it appears on Strava (D123).
- [ ] Send the same ride again: Strava's "duplicate" comes back as an error rather than "sent".
- [ ] intervals.icu: send a ride, and Disconnect works.
- [ ] Retry queue: turn on Airplane mode, save a ride with auto-upload on. Uploads shows "1 upload waiting to send". Turn the network back on: it goes through within a minute (D135).

### Zones and plans

- [ ] After a ride with the heart-rate strap, Settings → Rider suggests "Set N bpm" for the max heart rate. Set it, and a ride's page shows time in power and heart-rate zones (D140).
- [ ] Progress shows weekly time in zones under Weekly time.
- [ ] Home → Workout → Plans: grouped by goal, with hours a week. Start "Short on time" on your days from the preview, and check the week looks right (D143).

### Routes from a link

- [ ] Home → Route → + → From a link: paste a public RideWithGPS route, a Komoot tour (public, or shared with its link), and a Strava route. Each imports with its name and profile (D141).
- [ ] Strava: an account connected before this asks to reconnect ("Zmash now also asks to read your routes"); after reconnecting, the Strava route imports.
- [ ] A private route says so, rather than failing silently.

### Home

- [ ] No plan: the top card says "Pick a training plan". Choose a plan opens Workout → Plans with a plan in the preview; start one, and the card shows its next session straight away (D147).
- [ ] On a plan: "Ride this" on the card with the trainer on starts the session straight away. With the trainer off, it sets it up on home, and the start bar asks to connect (D128). The plan's own "Ride this" does the same.
- [ ] Ride the session and save: its mark on the card fills in, and the card moves on to the next session, without restarting the app. "This week" updates too (D123).
- [ ] "Plan" on the card opens the plan in the preview. Choosing another plan there warns that it ends the current one.
- [ ] × on "Pick a training plan" hides the card for this rider only; another rider still sees it.
- [ ] On the iPad, on its side and upright: home fits without scrolling, and the Start bar and all of "Your ride" are in view (D144).
- [ ] Switch between Free ride, Workout and Route: Workout and Route pick the last one you chose, and Start works straight away. The lists open on what's chosen.
- [ ] Route → Races → a Grand Tour: the stages list in place, and ‹ goes back. Choose a stage: the preview offers Full or a part; drag the window along the profile, and Start rides that part.
- [ ] A stage race's "Ride it as a campaign" opens in the preview; "Ride stage N" sets it up, and × goes back to the route.
- [ ] History, Devices and Settings open as pages under the same top bar, not sheets. A ride in History and Settings → Rider open inside the page with a back button. On the iPhone, the wordmark or the lit icon goes home (D145).
- [ ] Switch rider from the rider menu while on History: the list shows the new rider's rides.
- [ ] Workout → + → New workout and Import a .zwo file both land on Mine with the new workout chosen. Long-press one of yours → Delete asks first.

### Several riders

- [ ] Add a second rider, ride as them, and switch back. Each sees only their own rides, plan, campaigns and Strava account.
- [ ] Remove the second rider: their uploads accounts go with them (D123).

### Settings and setup

- [ ] Settings → Set up again asks first. "Keep things as they are" leaves the flow without changing anything (D126).
- [ ] First-run setup, on a fresh install: pairing each device from the flow, and the first spin's gradient felt on the trainer.
- [ ] Settings → Hardware probe: run it once and export the log.

### Text size and contrast

- [ ] iPad Settings → Accessibility → Display & Text Size → Larger Text, near the largest: home, Settings and History are still usable. The ride screen stays as designed (D137).
- [ ] Increase Contrast on: grey text and lines are stronger, and faces use their most readable palette (D138).

---

## iPhone, Watch and widgets

### iPhone

- [ ] Start a ride on a face other than Classic with the phone upright: it turns to landscape by itself, and the face fills the width, clear of the camera cutout (D129, D130).
- [ ] Switch to Classic mid-ride: the phone can go upright again. Switch back to a face: it turns again.
- [ ] End the ride: the app turns freely again.
- [ ] Settings → Faces, upright: the face across the width, and ⓘ shows its description. On its side: the face on the left, the controls on the right (D131).
- [ ] Settings → Faces opens as a page with a back button. Use this face goes back to Settings. Customise → "When switching faces mid-ride" off: the D-pad skips that face mid-ride, and turning off all but one says to keep two (D146).

### Live Activity

- [ ] Start a ride on the iPhone and lock it: the ride is on the lock screen and in the Dynamic Island, and it ends with the ride. Force-quit the app mid-ride and open it again: the leftover activity goes away (D123).

### Apple Watch

- [ ] Turn it on in Devices, and start a ride on the iPhone. The Watch opens Zmash (allow Health once), heart rate appears on the iPhone, tapping pauses, and the crown shifts.
- [ ] Afterwards there's one workout in Health.
- [ ] The Watch's End workout button works. If the iPhone goes silent for 3 minutes, the Watch ends its workout by itself (D123).

### Widgets

- [ ] Add This week, Next up and Form to the home and lock screens. They match the app after a ride, and This week empties on Monday morning without opening the app (D123).

### Siri and Shortcuts

- [ ] Say the phrases on the iPad: today's ride, a workout by name, a climb by name, how much you rode this week.
- [ ] Say "Start today's ride" with the app closed: it opens, waits for the trainer, and starts (D123).

### Mac

- [ ] Launch the Mac build from Xcode ("My Mac (Designed for iPad)"), and pair over the Mac's Bluetooth.

---

## Hardware you may not have

Only needed if you get to try one. These follow the published specifications and are unit-tested.

- [ ] **Zwift Play / Click:** pair both sides of a Play; buttons and shifting work.
- [ ] **Heart-rate strap:** pairs, the reading shows, and it disappears within 5 s of taking the strap off (D122).
- [ ] **Power meter:** pair it, check the readings in Devices, and check ERG with the power meter as the source settles on the target.
- [ ] **Speed/cadence sensor:** pairs, and cadence shows in Devices.
- [ ] **Basic (non-smart) trainer:** with a speed sensor, the power looks plausible for the trainer model chosen.
- [ ] **Older Wahoo (KICKR, SNAP) or Tacx (Neo, Flux):** the diagnostics log names the protocol, gradient changes are felt, and ERG holds.

---

## What to send back

- The diagnostics export from each ride.
- The failed checks, with a line each.
- Anything that felt wrong even if no check covers it: a number hard to read, a moment that's too much, a button in the wrong place.

The fixes go in one session, and the findings go into `DECISIONS.md`.
