# Zmash · Design Brief: Faces (round 2)

Make the ride screen beautiful, keep it minimal, and let riders choose how it looks, the way they change an Apple Watch face.

**Status:** Round 1 is built: Paper, Aura, Night, Horizon and Kinetic (from the Claude Design prototype in design/), plus the original dashboard as "Classic". Build decisions: DECISIONS.md D37–D47. The round 1 avenues are archived in the prototype. This brief proposes eight new directions for round 2, each taken from the world of cycling itself: its roads, races, tracks, equipment and rituals.

## 1. Why

The current ride screen does its job: big numbers, quiet chrome, one accent. It's also deliberately plain. It shows you're riding, but it doesn't make you feel anything.

A 45-minute indoor ride is long, repetitive and staring at one screen. The display is the only scenery. It should:

- Read at a glance from the saddle, mid-effort, sweat in the eyes.
- Feel alive: the screen should visibly respond to your legs, the terrain and your gears.
- Surprise, gently: a few rare, earned moments that make you smile, never gimmicks you tire of.
- Belong to the rider: pick a face that matches the mood of today's ride: a mountain stage, a track session, a race against yourself, a long day out.

## 2. The idea: faces

A face is a complete, self-contained look for the ride screen: its own layout, typography, colour, graphics and motion. Faces aren't themes: switching face can move everything, not just recolour it.

Every face draws from the same live data (the existing RideReadout) and must handle the same states (countdown, waiting for first pedal stroke, riding, paused, done, trainer lost). What a face shows, and how, is entirely its own.

Like watch faces:

- A gallery to browse faces full-screen with live, animated sample data, and swipe between them.
- Per-face customisation: a few options each (its "complications" and a palette), never a settings dump.
- Switch mid-ride: D-pad left/right on the Ride cycles faces with a soft transition and a one-second name tag. Remembered per rider.

## 3. Design principles

- **Numbers first, art second.** Every face must pass the glance test (§4) before anything decorative is judged. Beauty never costs legibility.
- **Motion means something.** Anything that moves is driven by the ride: speed, cadence, power, grade, gear, time. No idle animation, no loops for their own sake.
- **One surprise per face, earned.** Each face has one signature "magic moment" (§7) tied to something the rider did. Rare enough to stay special.
- **Quiet by default.** Minimal chrome, generous negative space, a restrained palette per face. Colour carries meaning (effort, terrain, state) or it isn't there.
- **Numbers stay still.** Values never jump position as they change: tabular figures, fixed slots, no layout shift. Motion lives in graphics and backgrounds, not in the digits' positions.
- **From the sport, not from apps.** Take cues from real cycling objects and places (col markers, race slates, stem cards, velodromes, drivetrains, painted roads) rather than generic app UI. No cards, no glass, no drop shadows on data.
- **Respect the room.** Every face works in a dim garage at night and in a bright room by day. It declares whether it has light and dark variants or is dark-only by nature.

The brief's original "avoid slop" rules still hold: no emoji, no motivational copy, no confetti, no decorative gradients. Gradients are allowed when they encode data (effort, terrain, time of ride). No race or team trademarks: the references are the culture, not the brands.

## 4. Hard constraints

| Constraint | Requirement |
|---|---|
| Viewport | Landscape iPad first: 11" (1194×834 pt) and 13" (1376×1032 pt). Portrait and Split View get a sensible fallback (§8), not a bespoke design. |
| Viewing distance | 60–90 cm, often while moving. |
| Glance test | The hero value is readable in < 0.5 s. Hero numerals ≥ 180 pt on 11"; secondary values ≥ 56 pt; units/labels ≥ 15 pt. |
| Contrast | Data ≥ 7:1 against its background (AAA) in its default palette; ≥ 4.5:1 in every palette option. Test in daylight on the device. |
| Stability | No value changes position as it updates. Tabular digits wherever a number updates. |
| Frame rate | 60 fps sustained on an 11" iPad Pro, with the wind layer on. Graphics use Canvas/TimelineView or Metal; no per-frame SwiftUI layout churn. |
| Energy | A 60-minute ride shouldn't drain more than ~15 % of battery above the screen-on baseline. Heavy faces offer a "calm" motion level. |
| Accessibility | Reduce Motion: all ambient motion stops; data transitions become cross-fades. Increase Contrast: faces switch to their highest-contrast palette. |
| States | Countdown, waiting for pedal stroke, riding, auto-pause, manual pause, trainer lost, timed "done", and the close/controls overlay must all look native to each face. |
| Data refresh | Trainer data arrives at ~4 Hz; the engine ticks at 10 Hz. Faces interpolate graphics between samples, never the digits. |
| Picture-in-Picture | Each face provides a 16:9 PiP card in its own style (or uses the default card). |

## 5. What a face can use

From RideReadout today:

- Speed: now. Power: instant and 3 s average. Cadence and heart rate.
- Time: elapsed and remaining. Distance, calories, climbed.
- Grade (current), the auto-terrain bias, and the gear out of the gear count.
- Profile: the upcoming grade (next 5 min). Paused and waiting states.
- FTP, power zones Z1–Z7 and the zone colour ramp, whole-ride profile with progress, session bests and milestones, cadence phase (added in round 1).

New data some round 2 faces would need (small engine additions):

- **Climbs:** detect climbs in the profile and rate them the way road races do (Cat 4 to HC, from length × average grade). For the current climb: distance to summit, metres still to climb, average grade of the next kilometre. Borne, Stem card and Broadcast use it.
- **Ghost:** a reference to race against: the rider's previous ride on the same profile, their best on it, or a target pace (average power or speed) when there's no previous ride. Gives a live time gap. Ardoise uses it.
- **Laps:** distance folded into laps of a chosen track length (250 m default), plus the best 200 m time of the session. Piste uses it.
- **Coasting:** speed above zero with cadence at zero, for freewheel moments. Groupset uses it.

## 6. Avenues to explore

Eight directions, each built on one thing every cyclist recognises. Each sketch is landscape.

### A. Borne: the kilometre stone

On Alpine and Pyrenean climbs, a stone marker stands at every kilometre: white with a coloured cap, telling you how far to the summit and how steep the next kilometre is. Riders read them like scripture. This face is that stone.

```
┌───────────────────────────────────────────────────────────────┐
│                                            ┌───────────────┐  │
│  31.4                                      │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│  │
│  km/h                                      │  SUMMIT       │  │
│                                            │  3 km         │  │
│  212 w      88 rpm                         │ ───────────── │  │
│  24:22      −05:38                         │  +312 m       │  │
│                                            │  next km 7 %  │  │
│  GEAR 14/24                                └───────────────┘  │
│ ▁▁▂▂▃▃▄▄▅▅▆▆▇▇  ·    ·    ·    ·  (stones ahead)             │
└───────────────────────────────────────────────────────────────┘
```

- **Layout:** the stone stands on the right, large and upright. Live numbers on the left. A thin roadside strip along the bottom shows the next stones as small marks, sliding toward you at real speed; each time you pass a kilometre, the big stone is "replaced" by the next one.
- **Type:** the stencil-like grotesk painted on real markers (a DIN-style condensed, heavy), black on white. Speed and power in the same family, larger.
- **Colour:** stone white, black lettering (naturally above 7:1), cap colour by the climb's category: yellow for Cat 3–4, orange for Cat 1–2, red for HC. Night variant: the stone lit by a headlamp, everything else dark.
- **Graphics:** the stone has real weathering (chips, lichen at the base) but the lettering is crisp. On flat ground it shows the distance to the next climb and its category instead. Manual-grade rides show metres climbed so far.
- **Motion:** the stone swaps once per kilometre (a short slide, like passing it). Nothing else moves except the roadside strip.
- **Magic moment: Summit.** At the top of a climb, the stone is replaced by a summit sign with the total metres climbed and the climb's category, and it stays for a few seconds as you roll past.
- **Why it's good:** the most legible idea in the set, made for auto-terrain, and it tells you the one thing a climber actually wants to know: how far, how steep.
- **Risk:** half the ride can be flat. The "next climb" state must look as good as the climbing state.

### B. Stem card: the profile taped to the bars

Before a stage, pros tape a strip of paper to their stem: the profile, the climbs, the kilometre marks, a few handwritten notes. This face is that strip, at iPad scale, with you on it.

```
┌───────────────────────────────────────────────────────────────┐
│  31.4 km/h        212 w        88 rpm        24:22   −05:38   │
│ ╔═══════════════════════════════════════════════════════════╗ │
│ ║[tape]                     C2                 C4           ║ │
│ ║                       ▗▟███▙         ✓                    ║ │
│ ║          ●         ▗▟███████▙▖    ▗▟█▙▖                    ║ │
│ ║ ▁▁▂▂▃▃▄▄▄▄▅▅▆▆▇▇▇███████████████▙▟██████▙▁▁▁▁▁▂▂▂▃▃▄▄    ║ │
│ ║ 0     5     10     15     20     25     30     35   [tape]║ │
│ ╚═══════════════════════════════════════════════════════════╝ │
└───────────────────────────────────────────────────────────────┘
```

- **Layout:** live numbers across the top. Below, a long paper strip taped at both ends shows the whole ride: filled elevation profile, kilometre scale, each climb labelled with its category. A marker dot shows where you are.
- **Type:** the numbers in a clean, heavy sans (SF Pro Display). Notes on the card in a marker-pen style, used only for short labels (C2, KOM, km marks), never for data that updates.
- **Colour:** off-white paper, black print, one felt-tip colour (red by default) for your position and the handwritten marks. Dark variant: the card under a dim cockpit light.
- **Graphics:** the profile is printed, crisp. Clear tape at the ends catches a little light. The section you've ridden gets slightly darker, like a card that's been sweated on.
- **Motion:** the marker dot moves with distance. Otherwise, nothing.
- **Magic moment: Tick.** When you crest a categorised climb, a felt-tip tick is drawn over it on the card, in one stroke.
- **Why it's good:** shows the whole ride at a glance, the view you'd want on a structured or timed ride. Instantly recognisable to anyone who's watched a race start.
- **Risk:** free rides have no known end; the card extends in sections, like a second card taped next to the first.

### C. Ardoise: the race slate

In road races, a motorbike rides ahead of the riders carrying a man with a chalk slate: the gap to the chase, rewritten by hand. This face races you against a ghost, and the gap comes on the slate.

```
┌───────────────────────────────────────────────────────────────┐
│   31.4                  ┌───────────────────────┐             │
│   km/h                  │                       │   212 w     │
│                         │       + 0:12          │   88 rpm    │
│   24:22                 │    ─────────────      │             │
│   −05:38                │   ghost · km 14       │   +3.5 %    │
│                         └───────────────────────┘   14/24     │
│   ● you ──────────────────────────────────────○ ghost          │
└───────────────────────────────────────────────────────────────┘
```

- **Layout:** the slate sits in the centre with the time gap as its main figure. Speed on the left, power and cadence on the right. A thin line along the bottom shows you and the ghost on the road, spaced by the gap.
- **Type:** the gap in a chalk rendering of a clear sans (not handwriting, so it stays legible); speed and power in a plain sans on the surrounding dark.
- **Colour:** dark-only. Slate grey-black, chalk white. The gap turns pale green when you're ahead, pale red when behind (the sign always carries the meaning too).
- **Graphics:** the gap is rewritten every kilometre (or every minute on timed rides), the old figure smudged away with a palm wipe. The ghost's position on the road line updates continuously.
- **Motion:** the rewrite, once per interval; the road line; chalk dust settling after each wipe.
- **Magic moment: Catch.** When you pass the ghost (the gap flips sign), the slate is wiped clean in one stroke and the new gap is written with a small underline.
- **Why it's good:** gives every ride a race without any motivational copy: the number does the talking. Makes riding the same auto-terrain profile twice worthwhile.
- **Risk:** needs a ghost (§5). With no previous ride on the profile, the ghost is a target pace, and the slate says so.

### D. Broadcast: the race on TV

The graphics package of a live bike race: telemetry bar, 3D profile with the rider on it, kilometres to go, the red kite at the last kilometre. You're the rider on the broadcast.

```
┌───────────────────────────────────────────────────────────────┐
│ LIVE                                         12.4 KM TO GO    │
│                                                 ▗▄▟█▙▄        │
│   31.4                                    ▗▄▟████████▙▄  ▲    │
│   km/h                         ●  ▗▄▄▟███████████████████▙▄▖  │
│                       ▄▄▄▄▟█████████████████████████████████  │
│ ┌──────────────────────────────────────────────────────────┐  │
│ │ 212 W │ 88 RPM │ +3.5 % │ 24:22 │ GEAR 14/24 │ ♥ 152     │  │
│ └──────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

- **Layout:** a 3D-extruded profile of the whole ride across the middle, camera slowly following your marker. Speed large on the left. A telemetry bar across the bottom. Kilometres to go (or time to go) top right.
- **Type:** a broadcast sans, bold and condensed (SF Pro Condensed heavy), white on deep blue panels, figures tabular.
- **Colour:** deep navy panels, white text, one accent (yellow) for your marker and the kilometres-to-go figure. The profile shaded by gradient, green to red.
- **Graphics:** the profile is a real 3D mesh with climb categories flagged on each summit. The telemetry bar is fixed; values update in place.
- **Motion:** the camera drifts along with you, slow enough to feel like a helicopter shot. On climbs it tilts a few degrees to show the slope.
- **Magic moment: Flamme rouge.** At one kilometre to go (or the last minute of a timed ride), the red kite arch passes over your marker and the countdown switches to metres.
- **Why it's good:** everyone who watches racing knows how to read it; turns the last kilometre of a solo ride into a finish.
- **Risk:** TV graphics can get busy. Hold the telemetry bar to five values, never more, and keep broadcaster branding out.

### E. Piste: the velodrome

A 250 m wooden track seen from above: pine boards, blue band, black and red lines. You're the dot going round. Laps, the lap board, the bell.

```
┌───────────────────────────────────────────────────────────────┐
│      ╭─────────────────────────────────────────╮     ┌────┐   │
│    ╭─╯                                         ╰─╮   │ 37 │   │
│   │        31.4 km/h          212 w   88 rpm     │   └────┘   │
│   │                                              ●   laps     │
│    ╰─╮     24:22   −05:38     best 200 m 13.9  ╭─╯            │
│      ╰─────────────────────────────────────────╯              │
└───────────────────────────────────────────────────────────────┘
```

- **Layout:** the oval fills most of the screen; the numbers sit in the infield, where the scoreboard would be. A flip-digit lap board stands to the right: laps done, or laps to go on timed rides.
- **Type:** scoreboard numerals (a dot-matrix-free, clean condensed sans) for the infield; the lap board in large flip digits.
- **Colour:** light variant: pale pine boards, blue band, black measurement line, red sprinter's line, white infield. Dark variant: the track under evening floodlights.
- **Graphics:** the track is drawn to real proportions, banking shown by shading on the turns. Your dot rides the black line; it moves up the banking when you slow down and drops to the line when you accelerate, like a rider swooping.
- **Motion:** the dot circles at your real speed (a lap every 18 s at 50 km/h). The lap board flips once per lap.
- **Magic moment: Flying 200.** A new best 200 m time appears on the infield scoreboard and the last 200 m of track lights up behind your dot for a second.
- **Why it's good:** constant, readable motion that maps exactly to speed; a lap counter is a great way to chop a long ride into pieces.
- **Risk:** the circling dot can pull the eye. Keep it small and the track muted so the infield numbers win.

### F. Groupset: the drivetrain

Your gears, as they'd look on a real bike: a cassette with the right number of cogs, a chainring, cranks turning at your cadence, a derailleur that moves when you shift.

```
┌───────────────────────────────────────────────────────────────┐
│                                                               │
│  31.4                            ╭────╮          ║║║║║║║▌║║║   │
│  km/h                           ╱  ◉   ╲ ─────── ║║║║║║║▌║║║   │
│                                 ╲      ╱ ─────── ║║║║║║║▌║║║   │
│  212 w   88 rpm                  ╰────╯          14 / 24      │
│  24:22   −05:38   +3.5 %                                      │
└───────────────────────────────────────────────────────────────┘
```

- **Layout:** the drivetrain in side view on the right: chainring and crank, chain, cassette. Numbers on the left.
- **Type:** a precise, engineered sans (SF Pro Display medium), laser-etched labels on the parts.
- **Colour:** machined aluminium and black anodised parts on a dark workshop background. One accent (a single rider-picked anodised colour) on the current cog. Light variant: parts on a white workstand backdrop.
- **Graphics:** real part rendering. The cassette shows the rider's actual gear count; the current cog is highlighted. The chain links move along at a speed that matches cadence and gear.
- **Motion:** the crank turns at your cadence (crank phase). On a shift, the derailleur swings across and the chain climbs onto the new cog in about 150 ms, with the haptic. When you coast, the cranks stop and the freehub pawls tick.
- **Magic moment: Spin-up.** Hold 120 rpm or more for 5 s and the crank blurs into a motion disc; the chain stays sharp.
- **Why it's good:** gear feedback you can read without reading, and a joy for anyone who loves bikes as machines.
- **Risk:** realistic rendering is costly to draw well; stay close to a technical illustration style rather than photoreal.

### G. Tarmac: the road from above

A top-down view of a mountain road scrolling under you at your real speed, with everything a race road carries: centre dashes, painted kilometre markers, chevrons on the hairpins.

```
┌───────────────────────────────────────────────────────────────┐
│ ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ │
│                                                               │
│   ───    ───    ───    ───   2 KM   ───    ───    ───    ───  │
│  31.4                                             212 w       │
│  km/h                                             88 rpm      │
│   ───    ───    ───    ───    ───    ───    ───    ───    ─── │
│ ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ │
└───────────────────────────────────────────────────────────────┘
```

- **Layout:** the road runs horizontally across the screen, verges top and bottom. The numbers sit on the tarmac in fixed positions, as if painted on it, while the markings scroll underneath.
- **Type:** road-marking lettering, tall and condensed, in painted white.
- **Colour:** dark asphalt grey with a subtle aggregate texture, white paint, yellow for the grade on climbs. The verge colour follows terrain: green on flats, grey rock on climbs.
- **Graphics:** centre dashes and kilometre markers scroll at real speed, so speed is felt before it's read. On climbs, chevrons appear in the verge, one per percent of grade.
- **Motion:** the scroll, always at your speed; it stops dead when you stop.
- **Magic moment: Painted road.** Over the last 500 m of a categorised climb, the tarmac fills with fan paint (abstract white brush marks and flags, no words), as on the great climbs, and it clears once you're over the top.
- **Why it's good:** the simplest, strongest speed sensation of all the faces, and cheap to render.
- **Risk:** the numbers sit on a scrolling surface; the scroll must stay low-contrast so the painted numbers always win.

### H. Brevet: the randonneur's card

Long-distance randonneurs carry a folded card stamped at each control along the route. This face is a brevet card for long, steady rides: controls every 15 minutes or 10 km, each one stamped as you reach it.

```
┌───────────────────────────────────────────────────────────────┐
│  31.4 km/h       212 w       88 rpm        1:24:22            │
│ ┌──────────┬──────────┬──────────┬──────────┬──────────┐      │
│ │ CONTROL 1│ CONTROL 2│ CONTROL 3│ CONTROL 4│ CONTROL 5│      │
│ │  (stamp) │  (stamp) │  (stamp) │   next   │          │      │
│ │  0:15:02 │  0:29:48 │  0:45:10 │  in 4:38 │          │      │
│ │ 29.4 km/h│ 30.1 km/h│ 28.8 km/h│          │          │      │
│ └──────────┴──────────┴──────────┴──────────┴──────────┘      │
└───────────────────────────────────────────────────────────────┘
```

- **Layout:** live numbers across the top; the card below, a row of control boxes. Each stamped box holds the time and the average speed and power for that section.
- **Type:** the live numbers in a plain sans; the card printed in a classic serif; stamped times in a rubber-stamp style that stays legible.
- **Colour:** cream card, black print, each stamp in a different ink (blue, violet, red, green), as real controls use their own. Dark variant: the card read under a head torch.
- **Graphics:** stamps land slightly crooked, with uneven ink. The card folds at its creases for longer rides and a new panel opens.
- **Motion:** one stamp per control; the "next" box counts down.
- **Magic moment: Homologué.** At the end of a ride of 2 hours or more, the card receives a final validation stamp across the whole row.
- **Why it's good:** makes long endurance rides legible as a series of splits, and shows pacing at a glance (each stamp shows whether you held steady).
- **Risk:** niche culture; the stamps must read as splits to someone who's never heard of randonneuring.

## 7. Shared delight system

Moments every face can express in its own way. The engine emits the event; the face decides how it looks.

| Event | Trigger | Examples |
|---|---|---|
| Countdown | Ride start | Piste: the start gate lights count down. Broadcast: the start flag drops. Borne: the first stone slides in. |
| First stroke | Clock starts | A single, face-specific "go" gesture (e.g. the crank's first turn on Groupset). |
| Shift | Gear change | Always within 100 ms, paired with the haptic. Never more than a small, local animation. |
| Summit | Top of a climb ≥ 60 s and ≥ 3 % | A pause-worthy flourish, at most once per climb. |
| Session best | New max power (5 s / 1 min) or top speed | Quiet acknowledgment, ≤ 2 s. |
| Milestone | Each km (or mile), halfway, last minute | Subtle marks; the last minute can count down (Piste rings the bell). |
| Pause / resume | Auto or manual | The face "rests" (the cranks stop, the slate is lowered, the road stops scrolling); resume reverses it. |
| Done | Timed ride complete | The face's own finish, then the summary "postcard" (§9). |

Rules:

- **Budget:** at most one moment on screen at a time, ≤ 2 s, and never covering the hero value.
- **Frequency:** milestones can be disabled per face; nothing fires more often than once a minute (except shifts).
- **Sound:** none by default. Optional later: the Piste bell, the Groupset freehub tick when coasting.
- **Haptics:** the Ride's buzz stays the only haptic; faces don't add more.

## 8. Fallbacks

- **Split View / Slide Over (compact):** faces may provide a compact variant; otherwise they fall back to the shared compact grid with their own typeface and palette.
- **Portrait:** same rule; the default portrait layout, restyled.
- **PiP card:** each face supplies a 16:9 card in its own style, or uses the default.
- **Reduce Motion / Low Power Mode:** ambient motion stops; faces must still look finished when still.

## 9. Beyond the ride screen

Faces should carry through the rest of the app where it counts, without restyling every screen:

- **Summary postcard:** the end-of-ride screen renders a still of the face with your final numbers and ride profile, as a shareable image (e.g. for Strava or Messages). Stem card and Brevet make natural postcards: the finished card, ticked or stamped.
- **Setup:** the Start button area previews the selected face, live with sample data.
- **History:** each ride remembers which face it was ridden with, and its postcard uses that face.
- The rest (Settings, Devices, History lists) stays in the neutral system style.

## 10. The face gallery

- **Entry:** a face preview on the setup screen, plus Settings → Faces.
- **Browsing:** full-screen horizontal paging, one face per page, animated with a looping 30-second sample ride so you see it move (speed changes, a shift, a short climb). The name and a single line of description sit under it.
- **Choose:** "Use" sets it; the last used face is the default for new rides.
- **Customise (per face, 2–4 options max):**
  - a palette (2–4 curated options);
  - which metric goes in each complication slot;
  - motion level (Full / Calm);
  - face-specific options (e.g. Ardoise ghost: last ride, best ride or target pace; Piste track length: 250 or 333 m; Brevet control interval).
- **Mid-ride:** D-pad left/right cycles through a rider-picked shortlist (default: 3 faces). The transition is a 300 ms cross-dissolve with a brief name tag. Numbers never go blank during a switch.

## 11. Architecture sketch

- A RideFace protocol:
  - an id, a name and a description;
  - a body rendering the landscape face from RideReadout + FaceOptions + an event stream;
  - an optional compactBody and pipCard;
  - its options schema;
  - whether it supports light and dark.
- RideReadout grows the round 2 data from §5 (climbs and categories, ghost gap, laps, coasting).
- FaceEvents: an async stream of the §7 moments, emitted by the engine.
- Shared building blocks, so faces stay consistent and cheap to make:
  - numeral renderers (tabular, chalk, flip, stamp);
  - the terrain path (profile → smoothed Bézier), in 2D and extruded 3D;
  - a climb annotator (category flags, summit marks);
  - gear indicators;
  - a zone colour ramp;
  - a motion clock.
- Heavy graphics in Canvas / TimelineView(.animation), and Metal shaders (.layerEffect, .colorEffect) for textures (chalk, paper, asphalt) and the 3D profile.

## 12. Evaluation

| Face | Legibility | Delight | Distinctness | Build cost | Energy |
|---|---|---|---|---|---|
| A. Borne | ★★★★★ | ★★★★☆ | ★★★★☆ | Low | Low |
| B. Stem card | ★★★★★ | ★★★★☆ | ★★★★☆ | Low | Low |
| C. Ardoise | ★★★★☆ | ★★★★★ | ★★★★★ | Medium | Low |
| D. Broadcast | ★★★★☆ | ★★★★☆ | ★★★☆☆ | High | Medium |
| E. Piste | ★★★★☆ | ★★★★☆ | ★★★★☆ | Medium | Low |
| F. Groupset | ★★★★☆ | ★★★★☆ | ★★★★☆ | Medium–High | Medium |
| G. Tarmac | ★★★★☆ | ★★★☆☆ | ★★★☆☆ | Low | Low |
| H. Brevet | ★★★★☆ | ★★★☆☆ | ★★★★☆ | Low | Very low |

Recommendation for round 2 (3 faces):

- **Borne** for climbing: the most legible face in the set, and the best companion to auto-terrain.
- **Ardoise** for racing: a ghost gives every repeat ride a purpose, with nothing but a number.
- **Stem card** for the whole ride: the full profile at a glance, cheap to build, a great postcard.

Then Piste (laps for long sessions) and Groupset (gear feedback). Broadcast, Tarmac and Brevet stay in the backlog unless one of them wins the prototype round.

## 13. Process

1. **Prototype stills.** Build each shortlisted face as a static SwiftUI view on RideReadout.sample. Screenshot at 11" and 13" landscape, light and dark, and compare side by side with the round 1 faces. Kill fast.
2. **Pick three.** Choose with the rider (you): legibility test from the bike at 80 cm, then taste.
3. **Slot into the face system (§11).** The protocol, gallery and switcher exist; add the §5 engine data (climbs first, then ghost) and the new shared renderers.
4. **Motion pass.** Add motion and magic moments one face at a time, each tested on the bike during a real ride.
5. **Energy and accessibility pass.** Profile a 60-minute ride per face; check Reduce Motion, Increase Contrast and Low Power Mode.
6. **Postcards and PiP cards.**

## 14. Open questions for you

- Should one of the round 2 faces replace Paper as the default?
- Ghost (Ardoise): do auto-terrain profiles repeat, so a previous ride can be the ghost? If not, is a target pace good enough?
- Climb categories: use the race convention (Cat 4 to HC), or plain difficulty labels?
- Borne and Brevet carry French words by nature (Sommet, Homologué). Keep them in French everywhere, or localise?
- Is any avenue an immediate no or an immediate yes?
