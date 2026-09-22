# Zmash — Design Brief: Faces

> Make the ride screen beautiful, keep it minimal, and let riders choose how it looks, the way they change an Apple Watch face.

Status: **Paper, Aura, Night, Horizon and Kinetic are built** (from the Claude Design prototype in `design/`), plus the original dashboard as "Classic". Chronograph, Tape and Segments are **skipped** (decision 2026-09-22); the prototype keeps them for reference. Build decisions: `DECISIONS.md` D37–D47.

---

## 1. Why

The current ride screen does its job: big numbers, quiet chrome, one accent. It's also deliberately plain. It shows you're riding, but it doesn't make you feel anything.

A 45-minute indoor ride is long, repetitive and staring at one screen. The display is the only scenery. It should:

- **Read at a glance** from the saddle, mid-effort, sweat in the eyes.
- **Feel alive**: the screen should visibly respond to your legs, the terrain and your gears.
- **Surprise, gently**: a few rare, earned moments that make you smile, never gimmicks you tire of.
- **Belong to the rider**: pick a face that matches the mood of today's ride: calm, focused, playful, nostalgic.

## 2. The idea: faces

A **face** is a complete, self-contained look for the ride screen: its own layout, typography, colour, graphics and motion. Faces aren't themes: switching face can move everything, not just recolour it.

Every face draws from the same live data (the existing `RideReadout`) and must handle the same states (countdown, waiting for first pedal stroke, riding, paused, done, trainer lost). What a face shows, and how, is entirely its own.

Like watch faces:

- **A gallery** to browse faces full-screen with live, animated sample data, and swipe between them.
- **Per-face customisation**: a few options each (its "complications" and a palette), never a settings dump.
- **Switch mid-ride**: D-pad left/right on the Ride (currently unassigned) cycles faces with a soft transition and a one-second name tag. Remembered per rider.

## 3. Design principles

1. **Numbers first, art second.** Every face must pass the glance test (§4) before anything decorative is judged. Beauty never costs legibility.
2. **Motion means something.** Anything that moves is driven by the ride: speed, cadence, power, grade, gear, time. No idle animation, no loops for their own sake.
3. **One surprise per face, earned.** Each face has one signature "magic moment" (§7) tied to something the rider did. Rare enough to stay special.
4. **Quiet by default.** Minimal chrome, generous negative space, a restrained palette per face. Colour carries meaning (effort, terrain, state) or it isn't there.
5. **Numbers stay still.** Values never jump position as they change: tabular figures, fixed slots, no layout shift. Motion lives in graphics and backgrounds, not in the digits' positions.
6. **Physical, not digital.** Take cues from real objects (instruments, paper, light, landscapes, dials) rather than generic app UI. No cards, no glass, no drop shadows on data.
7. **Respect the room.** Every face works in a dim garage at night and in a bright room by day. It declares whether it has light and dark variants or is dark-only by nature.

The brief's original "avoid slop" rules still hold: no emoji, no motivational copy, no confetti, no decorative gradients. **Gradients are now allowed when they encode data** (effort, terrain, time of ride), because some faces need them.

## 4. Hard constraints

| Constraint | Requirement |
|---|---|
| Viewport | **Landscape iPad first**: 11" (1194×834 pt) and 13" (1376×1032 pt). Portrait and Split View get a sensible fallback (§8), not a bespoke design. |
| Viewing distance | 60–90 cm, often while moving. |
| Glance test | The **hero value is readable in < 0.5 s**. Hero numerals ≥ 180 pt on 11"; secondary values ≥ 56 pt; units/labels ≥ 15 pt. |
| Contrast | Data ≥ 7:1 against its background (AAA) in its default palette; ≥ 4.5:1 in every palette option. Test in daylight on the device. |
| Stability | No value changes position as it updates. Tabular digits wherever a number updates. |
| Frame rate | 60 fps sustained on an 11" iPad Pro, with the wind layer on. Graphics use `Canvas`/`TimelineView` or Metal; no per-frame SwiftUI layout churn. |
| Energy | A 60-minute ride shouldn't drain more than ~15 % of battery above the screen-on baseline. Heavy faces offer a "calm" motion level. |
| Accessibility | Reduce Motion: all ambient motion stops; data transitions become cross-fades. Increase Contrast: faces switch to their highest-contrast palette. |
| States | Countdown, waiting for pedal stroke, riding, auto-pause, manual pause, trainer lost, timed "done", and the close/controls overlay must all look native to each face. |
| Data refresh | Trainer data arrives at ~4 Hz; the engine ticks at 10 Hz. Faces interpolate graphics between samples, never the digits. |
| Picture-in-Picture | Each face provides a 16:9 PiP card in its own style (or uses the default card). |

## 5. What a face can use

From `RideReadout` today:

- **Speed:** now. **Power:** instant and 3 s average. **Cadence** and **heart rate.**
- **Time:** elapsed and remaining. **Distance**, **calories**, **climbed.**
- **Grade** (current), the **auto-terrain bias**, and the **gear** out of the gear count.
- **Profile:** the upcoming grade (next 5 min). Paused and waiting states.

New data some faces would need (small engine additions):

- **FTP** (a new Settings value, default 200 W), giving **power zones Z1–Z7** and a zone colour ramp. Several faces use effort colour.
- **The whole-ride profile, with a progress fraction** (auto terrain, timed rides), for faces that show the full route.
- **Session bests** (max power, top speed) and **milestones** (each km, halfway, summit of a climb), which trigger magic moments.
- **Cadence phase**: a continuous crank angle from cadence, for pedal-synced motion.

## 6. Avenues to explore

Eight directions, deliberately far apart. Each sketch is landscape.

---

### A. Paper — *Swiss editorial*

The current screen, finished properly. A printed race-programme page: rigorous grid, confident type, hairline rules, ink on warm paper.

```
┌───────────────────────────────────────────────────────────────┐
│ 01 SPEED                         │ 02 POWER      │ 03 CADENCE │
│                                  │  212          │  88        │
│  31.4                            │  w            │  rpm       │
│  km/h                            ├───────────────┴────────────┤
│                                  │ 24:22     −5:38     301 kcal│
│──────────────────────────────────┴────────────────────────────│
│ ▁▁▂▃▄▅▅▆▆▇▇▆▅▄▃▂▂▁  +3.5 %     GEAR ▏▏▏▏▏▏▏▏▏▏▏▏▏█▏▏▏▏▏▏▏▏▏  14│
└───────────────────────────────────────────────────────────────┘
```

- **Type:** a grotesk with character, e.g. *Inter Display* or *Söhne-like* (licensable alternative: *Inter*, *Geist*), with figures at 300–600 weights. Small caps and numbered labels ("01 SPEED").
- **Colour:** warm paper `#F2EFE8`, ink `#141414`, one vermilion for the current gear and the grade when climbing. The dark variant is "carbon paper".
- **Graphics:** hairline rules, a stepped elevation histogram, a gear ruler like a printed scale.
- **Motion:** almost none. Values tick; the profile scrolls one pixel at a time; rules draw in once at the start.
- **Magic moment:** *Proof print.* At the end of the ride, the page "prints" your summary into the same grid, like a finished page coming off the press.
- **Why it's good:** timeless, supremely legible. The safe default. **Risk:** too close to today; it must be visibly more crafted.

---

### B. Horizon — *the landscape is the display*

You're riding into a minimalist landscape. The terrain profile becomes a ridge line crossing the screen; a small dot (you) sits on it; the sky above holds the numbers.

```
┌───────────────────────────────────────────────────────────────┐
│                                                   212 w   88 rpm│
│   31                                                            │
│   km/h                                  ___                     │
│                                  ______/   \__         24:22    │
│                        ●________/             \______  +3.5 %   │
│  ________________/                                  \_______   │
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
└───────────────────────────────────────────────────────────────┘
```

- **Layout:** the ridge spans the full width, showing the next ~5 minutes of terrain, scaled to feel real. You ride at the left third; the terrain scrolls towards you at your actual speed. Numbers sit in the sky, left and right.
- **Type:** light, airy, high-contrast serif or humanist sans for the hero (*New York*, *Fraunces* light), small tracked caps for labels.
- **Colour:** sky gradient keyed to **ride time**: dawn at the start, midday in the middle, dusk near the end, night during free rides past the plan. The ground is a flat shape one step darker.
- **Graphics:** layered parallax hills (2–3 depths, distant ones slower); the grade shown as the slope under the dot.
- **Motion:** parallax scroll at real speed; sky hue drifts over the whole ride (you only notice it looking back). Distant hills move slowly enough to be calming.
- **Magic moment:** *Summit.* Cresting the top of a climb, the view opens: the far layer rises, the sky brightens a notch, and a thin line marks the summit you just took, fading behind you.
- **Why it's good:** the most emotional, and it makes auto-terrain tangible. **Risk:** manual-grade rides have no future profile; show the last 5 minutes behind you instead.

---

### C. Chronograph — *a precision instrument*

Watchmaking on a dashboard. A large dial for speed with a sweeping needle, sub-dials for cadence and power, fine tick marks, luminous details.

```
┌───────────────────────────────────────────────────────────────┐
│          .  '  .  '  .                                          │
│      '                  '         ◜‾‾◝ 88      ◜‾‾◝ 212        │
│    .     ╲    31.4        .        ◟__◞ rpm      ◟__◞ w          │
│   '        ╲  km/h         '                                     │
│   .          ●              .     24:22                          │
│    '                       '      −05:38   ·   301 kcal          │
│      .  '  .  '  .  '  .          GEAR 14/24   +3.5 %            │
└───────────────────────────────────────────────────────────────┘
```

- **Type:** a slightly condensed instrument face, *SF Pro Condensed* or *Barlow Semi Condensed*; engraved-style small caps on the dial.
- **Colour:** dark-only by nature. Near-black dial `#0A0B0C`, off-white ticks, needle and one "lume" accent (pale green or amber, rider's choice). The power sub-dial arc is coloured by zone.
- **Graphics:** a 270° speed dial (0–60 km/h, adaptive to the rider's range), minute track, sub-dials with arcs, a bezel ring that fills with **ride progress** like a timer bezel.
- **Motion:** the needle sweeps with spring damping, a mechanical feel with a tiny overshoot on hard acceleration. Sub-dial needles are smooth and interpolated. Shifting gears clicks the bezel one notch (with the haptic).
- **Magic moment:** *Lume.* When you pause, the dial dims and the markers glow softly, like a watch in the dark, until you pedal again.
- **Why it's good:** satisfying, tactile, very "object". **Risk:** reading a needle is slower than digits. The digital speed stays in the dial; the needle is the feeling, the number is the fact.

---

### D. Aura — *ambient colour of effort*

No instruments at all. The whole screen is a soft, living colour field that is your effort. One enormous number floats in it.

```
┌───────────────────────────────────────────────────────────────┐
│░░░░░░░▒▒▒▒▒▒▒▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░│
│░░░░▒▒▒▒▒▒▓▓▓▓▓▓▓▓▓            ▓▓▓▓▓▓▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░│
│░░▒▒▒▒▓▓▓▓▓▓▓▓▓▓      212 w     ▓▓▓▓▓▓▓▓▓▓▓▒▒▒▒▒▒▒░░░░░░░░░░░░░│
│░░▒▒▒▓▓▓▓▓▓▓▓▓▓▓               ▓▓▓▓▓▓▓▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░│
│░░░▒▒▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░│
│  31 km/h        88 rpm        24:22        +3.5 %        14/24  │
└───────────────────────────────────────────────────────────────┘
```

- **Hero:** power by default (it's the effort face), speed as an option.
- **Colour:** a mesh gradient (iOS 18 `MeshGradient`) whose hues follow **power zone**: deep blues (Z1–2), teal and green (Z3), gold (Z4), orange (Z5), magenta and red (Z6–7). Transitions are slow (several seconds) so the room light changes like weather, not like a strobe.
- **Type:** big and soft: *SF Pro Rounded* heavy, or a variable font (*Recursive*, *Fraunces*) whose weight grows with power.
- **Motion:** the mesh points "breathe" in time with **cadence**: one gentle swell per pedal stroke, amplitude by power. Barely perceptible at easy effort, visibly pulsing at threshold.
- **Magic moment:** *Bloom.* A new session best (e.g. 1-minute power) blooms a ring of light outwards from the number and settles.
- **Why it's good:** the most "magical"; lights up a dark room; pairs beautifully with a video in Split View. **Risk:** colour must never be the only carrier of meaning; the number and zone label stay explicit. Cap brightness at night.

---

### E. Tape — *cockpit flight display*

An aircraft primary flight display for a bike. Vertical tapes scroll behind fixed read-out windows; an artificial horizon tilts with the grade.

```
┌───────────────────────────────────────────────────────────────┐
│  ┌──┐ 35                      ─────────                ┌──┐ 240 │
│  │  │ 33                ─────        ─────              │  │ 220 │
│  │31│◀  km/h        ─────  ╲  +3.5 %  ╱  ─────      w  ▶│212│   │
│  │  │ 29                ───────────────────             │  │ 200 │
│  └──┘ 27                                               └──┘ 180 │
│   88 rpm      GEAR ◀ 13 [14] 15 ▶        24:22   −05:38   301 kcal│
└───────────────────────────────────────────────────────────────┘
```

- **Layout:** a speed tape on the left, a power tape on the right (with zone bands painted on it), and a central horizon tilting to the real grade angle, exaggerated for readability. Gears appear as a drum counter.
- **Type:** *SF Mono* or *JetBrains Mono*, tabular throughout; small green-on-black or clean black-on-white variants.
- **Colour:** dark "glass cockpit" default with cyan/green/magenta semantics (targets magenta, as in avionics), plus a light "paper chart" variant.
- **Motion:** tapes scroll continuously (interpolated at 60 fps between samples) so trends are visible before the number changes. The drum counter rolls on shift.
- **Magic moment:** *Trend vectors.* A small arrow on each tape predicts where speed and power will be in 5 s. When you hold steady, they vanish; the display "locks on".
- **Why it's good:** shows trends, not just values; nerdy and precise. **Risk:** dense; needs discipline to stay minimal.

---

### F. Kinetic — *typography that rides*

Type is the only graphic. The numbers themselves respond to the ride: weight, width and slant are live data.

```
┌───────────────────────────────────────────────────────────────┐
│                                                               │
│   𝟯𝟭                      2 1 2                 88            │
│   km/h                     w                     rpm           │
│                                                               │
│   (weight ∝ power · width ∝ speed · slant ∝ grade)            │
│   24:22  −05:38            gear 14                +3.5 %        │
└───────────────────────────────────────────────────────────────┘
```

- **Type:** one variable font with weight, width and slant axes (*Recursive*, *Roboto Flex*, or SF Pro with `.width` and `.weight`). Power drives weight; speed drives width (digits stretch as you go faster); grade drives slant (climbs lean back, descents lean forward).
- **Colour:** monochrome with one accent. Black on white by day, white on black by night.
- **Motion:** axis values ease continuously. Digits don't move position, their shapes change. A shift snaps the weight for a beat (like a sharp breath) and relaxes.
- **Magic moment:** *Sprint.* Above 150 % FTP, all numerals go to maximum weight and width at once and hold while the effort lasts. The screen visibly "shouts".
- **Why it's good:** very original, pure, and cheap to render. **Risk:** width changes must stay within fixed slot bounds (stability rule). Test legibility at extreme axis values.

---

### G. Segments — *the cycling computer, remembered*

Nostalgia done with taste: a 1990s bike computer and LCD watch, rebuilt at iPad scale with modern restraint.

```
┌───────────────────────────────────────────────────────────────┐
│ ┌───────────────────────────────────────────────────────────┐ │
│ │ SPD          ▗▄▖ ▗▄▖ ▗▄▖         PWR   ▗▄▖▗▄▖▗▄▖   CAD ▗▄▖▗▄▖ │ │
│ │  km/h         ▐▌▐▌ ▐▌▐▌ ▐▌         W      ▐▌▐▌▐▌     rpm ▐▌▐▌ │ │
│ │ ▮▮▮▮▮▮▮▮▮▮▮▮▮▯▯▯▯▯▯▯▯▯▯ GEAR 14  ▲ 3.5%   TIME 24:22   ◐ 88% │ │
│ └───────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
```

- **Type:** a 7/14-segment display font (*DSEG*, OFL) with unlit "ghost" segments visible behind the digits. That detail makes it real.
- **Colour:** Reflective LCD (grey-green, dark segments) by day; backlit amber or ice-blue on black by night, with the backlight coming on when you pause (a nod to pressing "light").
- **Graphics:** segment bar graphs for gear and effort; fixed printed labels; a thin bezel.
- **Motion:** none beyond segment flips, which is the point. Optionally a 1 Hz colon blink.
- **Magic moment:** *Lap.* Every kilometre, the display flashes "LAP 12" with the split time for two seconds, exactly like the old computers did.
- **Why it's good:** delightful, a little funny, instantly understood. **Risk:** kitsch if overdone; keep the frame thin and the palette real.

---

### H. Night — *light in the dark*

A dark face made of light: glowing lines, the wind streaks as the star of the show, numbers that look lit from within.

- **Layout:** the current layout, but every element is a light source on black. The hero glows softly (bloom), the gear ladder is a row of LEDs, the terrain is a single luminous line.
- **Colour:** black, with one cool light colour (ice white, cyan) and the grade accent warming it on climbs.
- **Motion:** the wind field becomes a tunnel of light streaks at speed. Bloom intensity follows power.
- **Magic moment:** *Warp.* Passing a speed milestone (e.g. a new top speed), the streaks stretch briefly into a tunnel, then relax.
- **Why it's good:** gorgeous in a dim room, pairs with the existing wind layer. **Risk:** bloom costs GPU; check energy.

---

## 7. Shared delight system

Moments every face can express in its own way. The engine emits the event; the face decides how it looks.

| Event | Trigger | Examples |
|---|---|---|
| **Countdown** | Ride start | Paper: rules draw in. Chronograph: bezel winds up. Aura: colour rises from black. |
| **First stroke** | Clock starts | A single, face-specific "go" gesture (e.g. the needle lifts off zero). |
| **Shift** | Gear change | Always within 100 ms, paired with the haptic. Never more than a small, local animation. |
| **Summit** | Top of a climb ≥ 60 s and ≥ 3 % | A pause-worthy flourish, at most once per climb. |
| **Session best** | New max power (5 s / 1 min) or top speed | Quiet acknowledgment, ≤ 2 s. |
| **Milestone** | Each km (or mile), halfway, last minute | Subtle marks; the last minute can count down. |
| **Pause / resume** | Auto or manual | The face "rests" (dims, glows, stills); resume reverses it. |
| **Done** | Timed ride complete | The face's own finish, then the summary "postcard" (§9). |

Rules:

- **Budget:** at most one moment on screen at a time, ≤ 2 s, and never covering the hero value.
- **Frequency:** milestones can be disabled per face; nothing fires more often than once a minute (except shifts).
- **Sound:** none by default. Optional subtle ticks for Chronograph and Segments later.
- **Haptics:** the Ride's buzz stays the only haptic; faces don't add more.

## 8. Fallbacks

- **Split View / Slide Over (compact):** faces may provide a compact variant; otherwise they fall back to the shared compact grid with their own typeface and palette.
- **Portrait:** same rule; the default portrait layout, restyled.
- **PiP card:** each face supplies a 16:9 card in its own style, or uses the default.
- **Reduce Motion / Low Power Mode:** ambient motion stops; faces must still look finished when still.

## 9. Beyond the ride screen

Faces should carry through the rest of the app where it counts, without restyling every screen:

- **Summary postcard:** the end-of-ride screen renders a still of the face with your final numbers and ride profile, as a shareable image (e.g. for Strava or Messages).
- **Setup:** the Start button area previews the selected face, live with sample data.
- **History:** each ride remembers which face it was ridden with, and its postcard uses that face.
- The rest (Settings, Devices, History lists) stays in the neutral system style.

## 10. The face gallery

- **Entry:** a face preview on the setup screen, plus Settings → Faces.
- **Browsing:** full-screen horizontal paging, one face per page, animated with a looping 30-second sample ride so you see it move (speed changes, a shift, a short climb). The name and a single line of description sit under it.
- **Choose:** "Use" sets it; the last used face is the default for new rides.
- **Customise** (per face, 2–4 options max):
  - a palette (2–4 curated options);
  - which metric goes in each complication slot;
  - motion level (Full / Calm);
  - face-specific options (e.g. Chronograph dial range, Horizon time-of-day on or off).
- **Mid-ride:** D-pad left/right cycles through a rider-picked shortlist (default: 3 faces). The transition is a 300 ms cross-dissolve with a brief name tag. Numbers never go blank during a switch.

## 11. Architecture sketch

- A `RideFace` protocol:
  - an `id`, a name and a description;
  - a `body` rendering the landscape face from `RideReadout` + `FaceOptions` + an event stream;
  - an optional `compactBody` and `pipCard`;
  - its options schema;
  - whether it supports light and dark.
- `RideReadout` grows the new data from §5 (zone, FTP, whole profile, progress, bests, crank phase).
- `FaceEvents`: an async stream of the §7 moments, emitted by the engine.
- Shared building blocks, so faces stay consistent and cheap to make:
  - numeral renderers (tabular, variable-axis, segment);
  - the terrain path (profile → smoothed Bézier);
  - gear indicators;
  - a zone colour ramp;
  - a motion clock.
- Heavy graphics in `Canvas` / `TimelineView(.animation)`, and Metal shaders (`.layerEffect`, `.colorEffect`) for bloom, mesh and LCD effects.

## 12. Evaluation

| Face | Legibility | Delight | Distinctness | Build cost | Energy |
|---|---|---|---|---|---|
| A. Paper | ★★★★★ | ★★☆ | ★★☆ | Low | Low |
| B. Horizon | ★★★★☆ | ★★★★★ | ★★★★★ | High | Medium |
| C. Chronograph | ★★★☆☆ | ★★★★☆ | ★★★★☆ | Medium | Low |
| D. Aura | ★★★★☆ | ★★★★★ | ★★★★★ | Medium | Medium |
| E. Tape | ★★★★☆ | ★★★☆☆ | ★★★★☆ | Medium | Low |
| F. Kinetic | ★★★☆☆ | ★★★★☆ | ★★★★★ | Low–Medium | Low |
| G. Segments | ★★★★☆ | ★★★★☆ | ★★★★☆ | Low | Very low |
| H. Night | ★★★★☆ | ★★★★☆ | ★★★☆☆ | Medium | Medium–High |

**Recommendation for the first set (3 faces):**

1. **Paper** as the default: the polished evolution of today, and the legibility reference.
2. **Aura** for magic: the most striking, and effort-driven.
3. **Horizon** for story: it turns the terrain into a landscape you ride through.

Then **Segments** (cheap and charming) and **Chronograph** (instrument lovers). Tape, Kinetic and Night stay in the backlog unless one of them wins the prototype round.

## 13. Process

1. **Prototype stills.** Build each shortlisted face as a static SwiftUI view on `RideReadout.sample`. Screenshot at 11" and 13" landscape, light and dark, and compare side by side. Kill fast.
2. **Pick three.** Choose with the rider (you): legibility test from the bike at 80 cm, then taste.
3. **Build the face system** (§11): the protocol, the gallery and the mid-ride switcher, with the three faces.
4. **Motion pass.** Add motion and magic moments one face at a time, each tested on the bike during a real ride.
5. **Energy and accessibility pass.** Profile a 60-minute ride per face; check Reduce Motion, Increase Contrast and Low Power Mode.
6. **Postcards and PiP cards.**

## 14. Open questions for you

1. Should the **default face** be the polished Paper, or something more expressive?
2. Are you willing to set an **FTP** (or have one estimated from rides)? Aura, Tape and the zone colours depend on it.
3. **Mid-ride switching** on D-pad left/right: yes, or keep those buttons free?
4. Are **custom fonts** acceptable? They'd be open-licensed and bundled, adding ~1–3 MB. Or should we stay with the SF family (Rounded, Condensed, Expanded, Mono, New York), which already covers a lot?
5. Is any avenue an immediate **no** or an immediate **yes**?
