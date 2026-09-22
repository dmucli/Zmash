# Zmash — Development Brief

A full-screen ride display for the **Zwift Ride** controllers and a **Wahoo KICKR CORE 2**. It has no Zwift subscription, no account and no world map, just a small set of numbers that look good on an iPad propped on the handlebars.

> Status: pre-development. This brief is the source of truth for the MVP. Anything not listed under **MVP scope** is out of scope until a later phase.

---

## 1. Goals and non-goals

**Goals**
- Connect directly to the Zwift Ride (buttons) and KICKR CORE 2 (power, cadence, resistance) over Bluetooth LE.
- Show speed, watts, cadence, calories, elapsed time, current gear and terrain grade, full screen and beautifully.
- Provide realistic virtual speed, virtual shifting (24 gears) and terrain grade, either manual or auto-generated.
- Keep the screen awake during a ride. Keep working in Split View / Slide Over / Stage Manager, and keep recording when fully backgrounded.
- Offer a pre-ride setup, a post-ride save modal and a session history (list + calendar).
- Offer light and dark themes.

**Non-goals (MVP)**
- Routes, maps, GPS, avatars, multiplayer, social.
- Structured workouts / ERG workouts / FTP tests.
- Accounts, cloud sync, backend.
- Heart-rate straps, other trainers or other controllers (the architecture must not prevent them; see Phase 3).
- A web version (see §2).

---

## 2. Feasibility verdict

| Capability | Verdict | Notes |
|---|---|---|
| Read Zwift Ride buttons (shifters, D-pad, A/B/Y/Z, paddles) | ✅ Can | Protocol is **unencrypted** protobuf over BLE, well reverse-engineered (Makinolo, bikecontrol, Zword). Known good on firmware **≤ 1.2.0**, and the user's controllers are on **1.2.0**. |
| Zwift Ride haptic feedback | ✅ Can | Single write, see §5.1. |
| Read power + cadence from KICKR CORE 2 | ✅ Can | Standard **FTMS** (Bluetooth SIG). Fallback: Cycling Power service. |
| Set terrain grade on KICKR CORE 2 | ✅ Can | FTMS *Set Indoor Bike Simulation Parameters*. CORE 2 simulates up to ~16 %. |
| Virtual shifting | ✅ Can, with caveats | Two paths: the **Zwift trainer protocol** (native feel, needs hardware verification on CORE 2) or **FTMS + our own gear model** (guaranteed, needs tuning). See §5.2 and §6. |
| Realistic speed from watts + terrain | ✅ Can | Our own physics model, the same kind Zwift uses. See §6. |
| Screen stays on while riding | ✅ Can | `UIApplication.shared.isIdleTimerDisabled = true` while a session is active. |
| Split View / Slide Over / Stage Manager next to YouTube | ✅ Can | The app remains foreground-active and visible. The layout must adapt to compact widths (§10). |
| Keep running when fully backgrounded (YouTube full screen) | ⚠️ Partial | `bluetooth-central` background mode keeps BLE connected and delivers notifications, so the session keeps recording and resistance keeps updating. **But** the UI is invisible, timers are suspended (physics must tick on BLE notifications), and iOS *may* terminate the app under memory pressure (mitigated by autosave). |
| See metrics while another app is full screen | ⚠️ Phase 2 | Only possible via Picture-in-Picture fed with rendered frames (`AVSampleBufferDisplayLayer`). It's technically proven but hacky and carries some App Review risk. Split View covers the use case for the MVP. |
| Web version | ❌ Drop | Web Bluetooth doesn't exist on iPadOS: every iOS browser uses WebKit, so a web app cannot talk to the devices on the iPad. It would only work in desktop Chrome/Edge. The native iPad app runs **unmodified on Apple Silicon Macs** ("Designed for iPad"), which covers the desktop need for free. |
| Zwift Ride with newer, locked firmware | ❌ Risk | bikecontrol flags Ride firmware **> 1.2.0** as "server-locked", i.e. it stops working with third-party apps. Zwift already did this to the Click V2 (24 h unlock via the Zwift app). **Do not update the Ride firmware.** The on-screen controls are the fallback. |

---

## 3. Platform and tech stack

- **Swift 6, SwiftUI, iPadOS 18+.** Landscape first; portrait and compact widths are supported.
- **CoreBluetooth** directly. No third-party BLE library.
- **SwiftData** for persistence. **`@Observable`** view models.
- **Protobuf:** hand-rolled minimal varint/length-delimited encoder and decoder (the messages are tiny and use a handful of fields). Swap to SwiftProtobuf only if the message count grows.
- **Icons:** [Lucide](https://lucide.dev), imported as SVG template images into the asset catalog (preserve vector data, render as template). No SF Symbols, no emoji.
- **Fonts:** SF Pro Display / SF Pro Rounded with `.monospacedDigit()` for all live numbers.
- No backend, no analytics, no account.
- **Info.plist:** `NSBluetoothAlwaysUsageDescription`, `UIBackgroundModes = [bluetooth-central]`, `UIRequiresFullScreen = NO` (multitasking), all orientations on iPad.
- Distribution: personal device / TestFlight first.

---

## 4. Architecture

```
App/
  ZmashApp.swift              // scene, theme, idle-timer policy
BLE/
  BLECentral.swift            // single CBCentralManager, state restoration, scan/connect/reconnect
  DeviceRegistry.swift        // remembered peripheral UUIDs, auto-reconnect
  Ride/ZwiftRideClient.swift  // handshake, keypad decode, battery, haptics
  Ride/RideButtons.swift      // bitmask table, edge detection, hold-repeat
  Trainer/TrainerClient.swift // protocol: metrics stream + setGrade/setGear/start/stop
  Trainer/FTMSTrainer.swift
  Trainer/ZwiftProtocolTrainer.swift
  Proto/Varint.swift          // tiny protobuf reader/writer
  Demo/                       // fake Ride + fake trainer for Simulator and UI work
Physics/
  RiderModel.swift            // mass, CdA, Crr, air density
  SpeedModel.swift            // integrates v from power and grade
  Gears.swift                 // 24-gear table
  EffectiveGrade.swift        // FTMS virtual-shifting resistance
Session/
  SessionEngine.swift         // state machine, tick, auto-pause, controls routing
  TerrainEngine.swift         // manual grade + auto generator
  Recorder.swift              // 1 Hz samples, aggregates, autosave
Persistence/
  Models.swift                // SwiftData: Session, Sample, AppSettings
UI/
  Setup/, Ride/, Summary/, History/, Settings/, Debug/
  DesignSystem/               // colours, type scale, spacing, motion
```

Principles:
- **One source of truth:** `SessionEngine` owns the live state (speed, gear, grade, time). The UI only renders it, and BLE clients only feed it.
- **Input abstraction:** Ride buttons, on-screen buttons and (Mac) keyboard shortcuts all emit the same `RideCommand` enum (`shiftUp`, `shiftDown`, `gradeUp`, `gradeDown`, `pauseToggle`, `endSession`, `toggleTheme`).
- **Trainer abstraction:** `TrainerClient` hides whether the Zwift protocol or FTMS is in use.
- **Demo devices are mandatory.** CoreBluetooth does not work in the iOS Simulator. A `DemoTrainer` that synthesises power/cadence (with a slider or a scripted rider) and a `DemoRide` keyboard map let the whole UI be built without hardware.
- **Debug screen** (hidden: long-press the logo in Settings): live raw hex log per characteristic, decoded values, and FTMS control-point responses. It's essential for the M0 spike and for field bugs.

---

## 5. Device protocols

### 5.1 Zwift Ride (controllers)

Sources: [Makinolo — Zwift Ride protocol](https://www.makinolo.com/blog/2024/07/26/zwift-ride-protocol/), `bikecontrol-main/lib/bluetooth/devices/zwift/constants.dart` and `zwift_ride.dart`, `Zword_ZwiftRide-to-BLE-Keyboard-main/Zword_v0-0-1.ino`.

- **Only the LEFT controller is a BLE peripheral.** The right one links through it. Advertised name `Zwift SF2`, manufacturer ID `0x094A` (Zwift, Inc.), manufacturer data byte `0x08` = Ride left (`0x07` = right).
- **Service:** `0000FC82-0000-1000-8000-00805F9B34FB` (firmware from Jan 2025). Legacy: `00000001-19CA-4651-86E5-FA29DCDD09D1`. Scan for both.
- **Characteristics:**
  - `00000002-19CA-4651-86E5-FA29DCDD09D1`: async, **notify** (button events, battery, keep-alives)
  - `00000003-19CA-4651-86E5-FA29DCDD09D1`: sync RX, **write without response** (commands)
  - `00000004-19CA-4651-86E5-FA29DCDD09D1`: sync TX, **indicate** (command responses)
- **Handshake:** subscribe to 0002 (notify) and 0004 (indicate), then write ASCII `RideOn` (`52 69 64 65 4F 6E`) to 0003. The device answers `RideOn…` on 0004. No encryption.
- **Messages on 0002:** first byte = opcode, rest = protobuf.
  - `0x23` **keypad status**: field 1 = `buttonMap` (uint32, **inverse logic: bit = 0 means pressed**), field 3 = repeated analog paddle `{location (0 = left, 1 = right), analogValue (−100..100)}`. All released = `23 08 FF FF FF FF 0F …`.
  - `0x15`, `0x19`: keep-alive / status. Ignore them.
  - Battery notification: opcode `BATTERY_NOTIF` in bikecontrol's proto (`newPercLevel`). Show it in setup.
- **Button bitmask** (bit cleared = pressed):

  | Button | Mask | Side |
  |---|---|---|
  | D-pad left | `0x00001` | L |
  | D-pad up | `0x00002` | L |
  | D-pad right | `0x00004` | L |
  | D-pad down | `0x00008` | L |
  | A | `0x00010` | R |
  | B | `0x00020` | R |
  | Y | `0x00040` | R |
  | Z | `0x00080` | R |
  | Shift up L | `0x00100` | L |
  | Shift down L | `0x00200` | L |
  | Power-up L | `0x00400` | L |
  | On/off L | `0x00800` | L |
  | Shift up R | `0x01000` | R |
  | Shift down R | `0x02000` | R |
  | Power-up R | `0x04000` | R |
  | On/off R | `0x08000` | R |
  | Paddle L / R | analog, \|value\| ≥ 25 | L / R |

- **Frames repeat** while a button is held. Diff each frame against the previous one, fire on the **press edge**, and track hold duration for hold-repeat and long-press.
- **Haptics:** write `12 12 08 0A 06 08 02 10 00 18 20` to 0003 (no response). Rate-limit it to ≤ 5/s.
- **Constraints:**
  - The controller pairs with **one app at a time**. If Zwift or Zwift Companion is connected, we can't see it.
  - Power on left first, then right.
  - Firmware updates only happen through Zwift Companion. **Warn the user not to update past 1.2.0.** Read firmware from the Device Information Service (`0x180A`/`0x2A26`) and show a warning if it's > 1.2.0.

### 5.2 KICKR CORE 2 (trainer)

The Zwift Ride smart frame drives a KICKR CORE 2 fitted with a Zwift Cog, so there's **one fixed physical gear**. All shifting is virtual.

#### Path B — FTMS (guaranteed, build first)

- Service **Fitness Machine** `0x1826`.
- **Indoor Bike Data** `0x2AD2` (notify, ~1–4 Hz). Flags are uint16 little-endian, and fields appear in flag order:
  - bit 0 = *More Data* (**0 means Instantaneous Speed present**, uint16 × 0.01 km/h)
  - bit 1 avg speed
  - bit 2 **instantaneous cadence** (uint16 × 0.5 rpm)
  - bit 3 avg cadence
  - bit 4 total distance (uint24)
  - bit 5 resistance level (sint16)
  - bit 6 **instantaneous power** (sint16 W)
  - bit 7 avg power
  - bit 8 expended energy (uint16 + uint16 + uint8)
  - bit 9 heart rate (uint8)
  - bit 10 MET
  - bit 11 elapsed time
  - bit 12 remaining time

  The parser must walk every flag, even unused ones, to find the offsets.
- **Fitness Machine Control Point** `0x2AD9` (write + **indicate**). Subscribe to indications *before* writing.
  - `0x00` Request Control → then `0x07` Start/Resume.
  - `0x11` Set Indoor Bike Simulation Parameters: `wind sint16 (0.001 m/s)`, `grade sint16 (0.01 %)`, `Crr uint8 (0.0001)`, `Cw uint8 (0.01 kg/m)`. Always send our own Crr and Cw so the trainer's model matches ours.
  - `0x08` Stop/Pause (param `0x01` stop, `0x02` pause).
  - Response `0x80, <request opcode>, <result>`. Results: `0x01` success, `0x02` not supported, `0x03` invalid parameter, `0x04` failed, `0x05` **control not permitted** (another app owns control: show "Trainer in use by another app").
- **Fitness Machine Status** `0x2ADA` (notify): react to "control lost" (`0xFF`) by re-requesting control.
- Fallback for metrics: **Cycling Power** `0x1818` / Measurement `0x2A63` (power + crank revolution data → cadence).
- Throttle simulation writes to **≤ 4 Hz**, and send only when the value changes by ≥ 0.1 %.

#### Path A — Zwift trainer protocol (spike, use if it works)

Source: [Makinolo — Zwift trainer protocol](https://www.makinolo.com/blog/2024/10/20/zwift-trainer-protocol/). It's documented on Zwift Hub and KICKR CORE (v1). The CORE 2 ships "Zwift virtual shifting ready", so it very likely supports it. **Verify in M0.**
- Same custom service/characteristics family as the Ride (`…0002` notify, `…0003` control point). Service UUID and handshake to be confirmed with the packet logger. Try `RideOn` as for the Ride.
- **`0x04` trainer control** (protobuf):
  - `PhysicalParam { GearRatioX10000 (f2), BikeWeightx100 (f4), RiderWeightx100 (f5) }`
  - `SimulationParam { Wind m/s×100 (f1), InclineX100 (f2), CWa×10000 (f3, Zwift sends 5100), Crr×100000 (f4, Zwift sends 400) }`
  - `PowerTarget (f3)` for ERG. Not used.
- **`0x03` riding data** (notify): `Power (f1)`, `Cadence (f2)`, `SpeedX100 (f3)`, `HR (f4)`.
- The trainer then handles gear feel natively: we just send gear ratio and incline. Keep CWa/Crr at Zwift's values, since Makinolo warns that other values cause erratic behaviour.

**Selection:** Settings → Advanced → *Trainer protocol: Auto / Zwift / FTMS*. Auto tries Path A if the service is present and the first `0x04` write produces sane data. Otherwise it uses FTMS. The M0 spike decides the default. **Until then the default is FTMS** (guaranteed path); Auto waits 4 s for Zwift riding data before falling back to FTMS.

---

## 6. Physics, gears and metrics

### 6.1 Speed model (drives the displayed speed in both paths)

Integrate every tick (on each trainer notification, and at 10 Hz via a display link while in the foreground):

```
F_grav = m·g·sin(θ)
F_roll = m·g·Crr·cos(θ)
F_aero = ½·ρ·CdA·v²
a      = (P / max(v, 0.5) − F_grav − F_roll − F_aero) / m_eff
v      = max(0, v + a·dt)
```

- Defaults: rider 75 kg (setting), bike 9 kg (setting), `m_eff = m + 1 kg` (wheel inertia), CdA 0.32 m², Crr 0.004, ρ 1.225 kg/m³, g 9.81. θ = atan(grade/100).
- Effects: realistic acceleration, coasting on descents with zero watts, deceleration on climbs, stopping when pedalling stops on the flat.
- Use `dt` from real timestamps and clamp `dt` to ≤ 2 s. After a long background gap, don't integrate a huge jump: treat it as a pause.
- Distance = ∫v dt. Elevation gain = ∫ max(0, v·sin θ) dt.

### 6.2 Virtual gears

- 24 gears, Zwift-like ratios from **0.75 to 5.49**: `0.75 0.87 0.99 1.11 1.23 1.38 1.53 1.68 1.86 2.04 2.22 2.40 2.61 2.82 3.03 3.24 3.49 3.74 3.99 4.24 4.54 4.84 5.14 5.49` (small steps low, bigger steps high; an approximation of Zwift's table). Start gear: **12** (2.40). Source of truth: `ZmashKit/Gears.swift`.
- Wheel circumference 2.105 m (700×25c).
- Cadence-implied speed: `v_gear = cadence/60 · ratio · 2.105`.
- Shifting at the ends of the ladder is a no-op, with a short "limit" haptic and a UI shake.

### 6.3 Resistance

- **Path A:** send `GearRatioX10000 = ratio × 10000` and `InclineX100 = grade × 100` on every change. The trainer does the rest.
- **Path B (FTMS):** we want the power needed at the current cadence in the chosen gear to equal the physics power for that speed:

  ```
  P_req  = v_gear · (m·g·(sinθ + Crr·cosθ) + ½·ρ·CdA·v_gear²)
  v_t    = trainer-reported speed (flywheel, fixed physical gear)
  grade' = ((P_req / v_t) − ½·ρ·CdA·v_t²) / (m·g) − Crr        → as %
  ```

  Clamp grade' to **[−10 %, +16 %]**. Low-pass it (τ ≈ 1 s) so shifts feel crisp but not jerky. Below 20 rpm / 3 km/h, send the terrain grade unmodified. In very high gears on steep climbs the clamp will bind. That's acceptable, and the gear ladder shows a subtle "max resistance" state.
- **ERG fallback** (hidden setting): send `P_req` as target power (FTMS `0x05`). ERG lag makes this the last resort.
- Tuning of Path B **needs a real rider**. Budget time for it in M2.

### 6.4 Metrics shown

| Metric | Source | Display |
|---|---|---|
| Speed | §6.1 model | km/h (default; mph in settings), 1 decimal below 10, integer above |
| Watts | trainer | 3 s rolling average by default (setting: instant / 3 s / 10 s), integer |
| Cadence | trainer | rpm, integer; shows `—` after 3 s without data |
| Calories | ∫P dt | **kcal ≈ kJ of work** (standard cycling convention: ~24 % gross efficiency × 4.184 ≈ 1) |
| Elapsed | session clock | `m:ss` / `h:mm:ss`; active time excludes pauses |
| Remaining | timed sessions | secondary, counting down |
| Gear | engine | `n / 24` + ladder |
| Grade | engine | `+4.5 %`, with the mini elevation strip in Auto mode |

- Sanitise inputs: clamp power to 0–2000 W and cadence to 0–200 rpm, and drop single-sample spikes (> 3× the rolling median).

---

## 7. Controls mapping (MVP default, not configurable yet)

| Input | Action |
|---|---|
| Right **shift up** / right paddle | Harder gear (+1) |
| Right **shift down** | Easier gear (−1) |
| Left **shift up** / **shift down** / left paddle | Easier gear (−1). Zwift convention: left = easier |
| Left **D-pad up / down** | Manual mode: grade ±0.5 %, clamped to **−10 % … +16 %**. Auto mode: bias ±0.5 %. Hold → repeat at 4 Hz after 400 ms |
| **A**, **Z**, left or right **on/off** (short press < 600 ms) | Pause / resume |
| **B** held 1 s, or left **power-up** held 1 s | End session → save modal |
| **Y** | Toggle light/dark |
| D-pad left/right, right power-up | Unassigned (reserved) |

- **On/off buttons:** a long hold on on/off powers the controller down, so only a short press counts (fired on release). It's never mapped to a hold action. If the controller disconnects within 2 s of an on/off press, treat it as a power-off, not a pause.
- **Pause/resume** gives a single long buzz. The **end-session hold** gives a buzz at 1 s and then opens the save modal.
- Haptic buzz on each shift (setting). A different, double buzz fires at a gear limit.
- **On-screen controls always exist:** gear −/+, grade −/+ (manual) and pause. They're large touch targets along the bottom edge and auto-hide after 4 s without touch while riding. Tapping anywhere reveals them. They're the full fallback if the Ride fails.
- On Mac: arrow keys and `[`/`]` for the same commands.

---

## 8. Pre-ride setup screen

- **Duration:** 15 / 30 / 45 / 60 / 90 min / Free ride (segmented control).
- **Terrain:** Manual | Auto.
  - Auto → **Effort:** Easy / Medium / Hard.
  - Auto → **Type:** Flat / Rolling / Hilly / Mountain.
  - Auto shows a preview of the generated elevation profile for the chosen duration and a "reroll" button (new seed).
- **Devices:** two chips. *Ride* (L/R presence, battery %) and *Trainer* (connected, protocol A/B). Tapping a chip opens pairing and forget.
- **Start** is enabled when the trainer is connected. The Ride is optional (on-screen controls).
- Start → 3-2-1 countdown → the ride screen shows `0:00` with a subtle "pedal to start" pulse on the time. **The clock starts on the first pedal stroke** (cadence > 0 or power > 0 for ≥ 1 s). If the rider is already pedalling during the countdown, the clock starts at the end of the countdown. The terrain profile and recording start with the clock.
- Entry points to **History** and **Settings** live only here, not during a ride.
- The last-used setup is remembered.

---

## 9. Auto terrain generator

- **Seeded RNG** (e.g. SplitMix64). The seed is stored with the session, so every ride is reproducible and "reroll" is free.
- **Time-based profile:** grade is a function of elapsed *active* time, so the profile always fits the chosen duration. A distance-based profile would stretch when climbing and overrun the session.
- **Structure:** 3 min warm-up (0 → 1 %), body, 2 min cool-down (→ 0 %). Sessions ≤ 15 min use a 2 min warm-up and 1 min cool-down.
- **Body:** a sequence of segments 45 s–6 min long, chosen from per-type tables.

  | Type | Grade range | Character |
  |---|---|---|
  | Flat | −1 … +2 % | short, gentle undulations |
  | Rolling | −3 … +4 % | 1–3 min bumps |
  | Hilly | −5 … +7 % | 2–5 min climbs, matching descents |
  | Mountain | −6 … +10 % | 1–3 long climbs (≥ 25 % of body) with steady ramps, descents between |

- **Effort multiplier** on positive grades and climb share: Easy ×0.6, Medium ×1.0, Hard ×1.35 (still capped at 16 %). Hard also shortens recoveries.
- **Smoothing:** grade changes ramp at ≤ 0.5 %/s. There are no instant jumps.
- **Guarantees:** net climbing ≥ net descending (it should feel like work). No descent in the last 30 s before cool-down. The max grade is hit at most once in Easy.
- **Free ride + Auto:** generate rolling 10 min blocks ahead of time, with no cool-down until the user ends the session.
- **D-pad in Auto** adds a bias (−5 … +5 %) on top of the profile, shown as a small `+1.0` badge next to the grade.
- **Ride screen:** a mini elevation strip shows the next ~5 min, with a marker for "now".

---

## 10. Ride screen — UI spec

**Layout, landscape iPad (full width):**

```
┌──────────────────────────────────────────────────────────── ● ● ┐
│                                                                  │
│   248              ┌──────────────────────┐          24:13       │
│   w                │         34.6         │          −05:47      │
│                    │         km/h         │                      │
│   92               └──────────────────────┘          312         │
│   rpm                                                kcal        │
│                                                                  │
│  ▁▂▃▅▆▇▇▆▅▃▂▁▁▂▃ (elevation, auto)        +4.5 %                 │
│  ▏▏▏▏▏▏▏▏▏█▏▏▏▏▏▏▏▏▏▏▏▏▏▏  10/24                                 │
└──────────────────────────────────────────────────────────────────┘
```

- **Hero:** speed, centred, largest type (≈ 30 % of screen height). Secondary numbers are about ⅓ of the hero size.
- **Labels:** units only, small, lowercase, low contrast. No words like "Speed" or "Power".
- **Connection dots** top-right: Ride, trainer. They turn amber while reconnecting and red when lost. There's no text unless the user taps them.
- **Gear ladder:** 24 thin ticks with the current one filled. It animates on shift with a spring.
- **Grade:** signed with one decimal. The accent hue shifts subtly: cool on descents, neutral on flat, warm on climbs. The hue shift is the only colour in the UI.
- **Paused state:** numbers dim to 40 %, with a single pause icon (Lucide `pause`) in the centre.
- **Compact widths** (Split View ⅓ or ½, Slide Over, small Stage Manager windows): switch at `horizontalSizeClass == .compact` to a 2×3 grid (speed, watts / rpm, time / kcal, grade), with gear and grade as a bottom row. Everything stays readable at 320 pt wide.
- **Portrait:** hero on top, 2×2 grid below.
- **Motion:** numbers interpolate between samples (`contentTransition(.numericText())` or a custom tween at 60 fps). There's no bouncing and no confetti.
- **Theme:** Light / Dark / System (Settings). Y on the Ride toggles light/dark. Backgrounds are near-black `#0B0B0C` and near-white `#F5F5F2`, never pure black or white. Text uses two contrast levels only.

**Taste rules (avoid slop):**
- No decorative gradients, glassmorphism, drop shadows or cards-within-cards.
- No emoji, no exclamation marks, no motivational copy, no "Great job!".
- No explanatory sentences on the ride screen. Setup copy is limited to a few labels.
- One typeface family and one accent. All icons are Lucide, same stroke width (1.5).
- Every screen must still look intentional as a screenshot with the numbers at zero.

---

## 11. Session lifecycle and edge cases

**States:** `setup → countdown → riding ⇄ paused → finished → (saved | discarded)`.

| Situation | Behaviour |
|---|---|
| No pedalling for 5 s | **Auto-pause** (setting, default on). Resume on cadence > 0. |
| Timed session reaches 0 | A soft "done" state shows the timer at `0:00` with two buttons: *Finish* or *Keep riding* (switches to open-ended; the count-up continues). Auto terrain moves into cool-down/flat. |
| App killed or crashed mid-ride | Autosave the in-progress session every 10 s (and on every background transition). On next launch, show "Unfinished ride — Recover / Discard". |
| Trainer disconnects | The session keeps running and power is treated as 0, so speed decays naturally. The trainer dot turns amber and auto-reconnect runs with backoff. After 60 s without the trainer, the session auto-pauses. On reconnect: re-request control and re-send grade and gear. |
| Ride disconnects | Auto-reconnect. On-screen controls stay available, and the gear and grade are kept. |
| Only the right controller is on | It can't connect alone. The setup hint says: "Turn on the left controller first." |
| Ride paired to Zwift/Companion | Not found in scan. The hint says: "Close Zwift and Zwift Companion." |
| Ride firmware > 1.2.0 | A one-time warning. Buttons may not work, so use the on-screen controls. |
| Trainer controlled by another app (`0x05` control not permitted) | Show a hint to close the other app, and offer a retry. Metrics still work read-only. |
| Bluetooth off / permission denied | Full-screen state with one sentence and a button (open Settings). The ride can't start. |
| Backgrounded while riding | Keep BLE running and recording. Advance physics on BLE notifications. On return, catch up the UI. |
| Backgrounded while paused | Stay paused. After 10 min in the background, disconnect devices to save their batteries, and reconnect on return. |
| Low Ride battery (< 15 %) | Amber dot plus a percentage in setup. Never shown during the ride. |
| iPad Low Power Mode | No behaviour change. Keep the idle timer disabled. |
| Screen lock | Can't happen while riding (idle timer disabled). A manual lock is treated as backgrounded. |
| Session shorter than 60 s at finish | The save modal pre-selects *Discard*. |
| Clock changes / timezone | Store UTC timestamps. The calendar uses the local day of the start time. |

---

## 12. End-of-session modal

- **Summary:** duration (active), distance, avg / max watts, avg cadence, avg speed, kcal, elevation gain, and mode/terrain used.
- **Effort evaluation:** a 1–10 perceived-effort (RPE) selector as a single row of 10 segments, with one word under the ends only ("easy", "max").
- An optional one-line note.
- **Save** (primary) and **Discard** (secondary). Discard asks for confirmation.
- After saving: back to setup, with the new session highlighted in History.

---

## 13. History

- Available from setup only, not during a ride.
- **List view:** reverse chronological rows showing date, duration, distance, avg W, kcal and an RPE dot.
- **Calendar view:** month grid. Days with rides get a dot sized by duration. Weekly totals (time, kcal) sit in a side column. Swipe between months.
- Toggle between the views with a segmented control, and remember the choice.
- **Detail:** the full summary plus the setup used (duration, mode, effort, terrain, seed), and a "Ride this again" action that reuses the seed. Delete with confirmation.
- Empty state: one line, no illustration.

---

## 14. Data model (SwiftData)

```swift
@Model final class Session {
  var id: UUID
  var startedAt: Date            // UTC
  var endedAt: Date
  var activeSeconds: Int
  var plannedSeconds: Int?       // nil = free ride
  var terrainMode: String        // manual | auto
  var effort: String?            // easy | medium | hard
  var terrainType: String?       // flat | rolling | hilly | mountain
  var seed: UInt64?
  var distanceM: Double
  var elevationGainM: Double
  var kcal: Double
  var avgPowerW: Int; var maxPowerW: Int
  var avgCadence: Int; var avgSpeedKph: Double
  var rpe: Int?                  // 1–10
  var note: String?
  var isComplete: Bool           // false while autosaving an in-progress ride
  @Relationship(deleteRule: .cascade) var samples: [Sample]
}

@Model final class Sample {       // 1 Hz, ~3.6k rows/hour
  var t: Int                     // seconds since start (active)
  var powerW: Int; var cadence: Int
  var speedKph: Double; var gradePct: Double; var gear: Int
}
```

Settings live in `@AppStorage`: rider kg, bike kg, units, theme, haptics, auto-pause, watts smoothing, trainer protocol, remembered peripheral UUIDs, and the last setup. Samples are stored from day one so the Phase-2 graphs need no migration.

---

## 15. Settings

Rider weight, bike weight, units (**km/h default** · mph), theme (system / light / dark), haptics on shift, auto-pause, watts smoothing (instant / 3 s / 10 s), trainer protocol (auto / Zwift / FTMS), forget devices, and the hidden debug screen.

---

## 16. Risks and mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Zwift pushes Ride firmware that locks third parties | Medium | Tell the user not to update. Warn on firmware > 1.2.0. On-screen controls work regardless. |
| CORE 2 doesn't accept the Zwift trainer protocol from us | Medium | FTMS path B is built first and is sufficient. |
| FTMS effective-grade shifting feels laggy or wrong | Medium | Tune τ and the clamp with a real rider. ERG fallback. |
| iOS kills the app while backgrounded | Low–medium | Autosave every 10 s plus recovery on relaunch. |
| Physics ticks stall in the background | Certain | Tick on BLE notifications, not on timers. Clamp `dt`. |
| Trainer and Ride both need a BLE connection while the iPad has other BLE devices | Low | iPads handle many connections. Keep an eye on it in M0. |
| Trademark / App Store | Low | Don't use "Zwift" in the app name or icon. Describe it as "works with". Personal/TestFlight distribution first. |
| bikecontrol licence (Non-Commercial) | — | Use it as protocol reference only. **Don't copy code.** Reimplement from the facts documented here and from Makinolo's write-ups. |

---

## 17. Milestones

Each milestone ends with a working build on the iPad.

**M0 — Hardware spike (go/no-go)**
- A bare SwiftUI app with a scanner, connect, and a raw hex log for every characteristic.
- Acceptance:
  - Ride handshake works and every button in §5.1 is identified in the log.
  - CORE 2 FTMS power and cadence stream.
  - `0x11` grade changes are felt on the pedals.
  - Path A is tried and its outcome is recorded (works / doesn't), which sets the default protocol.
  - The Ride firmware version is read.

**M1 — BLE layer + demo devices**
- `BLECentral`, `ZwiftRideClient`, `FTMSTrainer` (and `ZwiftProtocolTrainer` if M0 is green), auto-reconnect, remembered devices, and demo devices.
- Acceptance: devices reconnect after power-cycling. The full UI can be driven in the Simulator with demo devices.

**M2 — Physics, gears, ride screen**
- Speed model, gear table, resistance path, the ride screen (landscape and compact), on-screen controls, and keeping the screen on.
- Acceptance:
  - Shifting changes the feel within ≤ 1 s.
  - Speed behaves plausibly: ~30–35 km/h at 200 W on flat for 75 kg, and it coasts on descents.
  - The screen never sleeps while riding.

**M3 — Setup + terrain**
- The setup screen and the manual and auto terrain engine, with preview and reroll.
- Acceptance:
  - The auto profile fits the duration exactly.
  - The same seed gives the same profile.
  - Grade ramps are smooth on the trainer.
  - D-pad bias works.

**M4 — Session end, persistence, history**
- Recorder, autosave and recovery, the save modal, and history list, calendar and detail.
- Acceptance: kill the app mid-ride, relaunch, and the ride is recovered. Sessions persist across launches.

**M5 — Multitasking and polish**
- Split View / Slide Over / Stage Manager layouts, background recording, light/dark theme, motion, the taste pass, and TestFlight.
- Acceptance: a 30 min ride next to YouTube in Split View, and a 10 min ride with YouTube full screen, both record correctly.

---

### Implementation status (2026-09-22)

All milestones and phases are implemented. Decisions, deviations and what still needs the user's hardware are in **`DECISIONS.md`**.

| Milestone / phase | Where | Verified |
|---|---|---|
| M0 hardware probe | `Zmash/Probe/` (Settings → Hardware probe) | checklist not yet run on hardware |
| M1 BLE layer + demo devices | `Zmash/Devices/` | Ride + KICKR CORE 2 connect, reconnect and control on the user's iPad |
| M2 physics, gears, ride screen | `ZmashKit/SpeedModel.swift`, `Zmash/Session/`, `Zmash/UI/Ride/` | on device (FTMS shifting "very gradual"); Simulator screenshots |
| M3 setup + auto terrain | `ZmashKit/Terrain.swift`, `Zmash/UI/Setup/` | unit tests; Simulator |
| M4 save, persistence, history | `Zmash/Persistence/`, `Zmash/UI/Summary/`, `Zmash/UI/History/` | Simulator (incl. crash recovery) |
| M5 multitasking + polish | compact/portrait layouts, background ticking + autosave, idle timer, close button | Simulator (compact at 375 pt) |
| Phase 2 | wind background, session charts + table, PiP overlay | wind/charts in Simulator; PiP starts, content to confirm on device |
| Phase 3 | UI customisation, button mapping, FIT export, Apple Health, heart-rate strap, Mac build | FIT decoded by `fitdecode`; others unit-tested/compiled; Health + HR need device |
| Phase 4 | Zwift Play (1.x/2.x), Zwift Click v1, any FTMS trainer; Click v2 excluded (locked by Zwift) | decoders unit-tested; no hardware |

## 18. Future phases (now implemented — see status above)

- **Phase 2**
  - Speed-reactive background: wind particles streaming towards the rider, with density and velocity tied to speed. Metal or SwiftUI `Canvas` + `TimelineView`, capped at 60 fps, auto-off in Low Power Mode.
  - Per-session graphs of speed, watts, cadence and grade, built from the stored samples.
  - A PiP metrics overlay.
- **Phase 3**
  - Full UI customisation: font, sizes, which metrics go where, colours, background motion.
  - Configurable button mapping.
  - Apple Health workout export, FIT/TCX export, Strava upload.
  - Heart-rate strap support.
- **Phase 4**
  - Other trainers (generic FTMS) and other controllers (Zwift Play, Click).

---

## 19. Decisions (answered 2026-09-22)

| Question | Decision |
|---|---|
| Ride firmware | **1.2.0** on both controllers. Supported; stay on it and don't update. |
| Units | **km/h** by default (mph available in settings). |
| Clock start | On the **first pedal stroke** after the countdown (§8). |
| Pause/end on other Ride buttons | **Yes.** Pause/resume on A, Z and a short press of either on/off; end on hold B or hold left power-up (§7). |
| Manual descents steeper than −10 % | **No.** Manual grade is clamped to −10 % … +16 %. |

---

## References

- Makinolo — [Zwift Ride protocol](https://www.makinolo.com/blog/2024/07/26/zwift-ride-protocol/) · [Zwift trainer protocol](https://www.makinolo.com/blog/2024/10/20/zwift-trainer-protocol/)
- `bikecontrol-main/lib/bluetooth/devices/zwift/` — constants, Ride keypad decoding, haptics (reference only, Non-Commercial licence)
- `Zword_ZwiftRide-to-BLE-Keyboard-main/Zword_v0-0-1.ino` — minimal Ride handshake
- Bluetooth SIG — Fitness Machine Service (FTMS) 1.0 specification
- [DC Rainmaker — Rouvy adds Zwift virtual shifting](https://www.dcrainmaker.com/2025/02/rouvy-adds-zwift-cog-click-ride-virtual-shifting-battle-royale-begins.html) (third-party use of the Zwift trainer protocol)
- [BikeControl — Click V2 lock explained](https://bikecontrol.app/blog/zwift-click-v2-with-other-trainer-apps/)
- [KickrShiftr](https://github.com/jvivenot/KickrShiftr) — alternative Wahoo wheel-circumference shifting trick (not used; kept as a last-resort idea)
- Apple — Core Bluetooth background processing (`bluetooth-central`)
