# Zmash Design System

Zmash is a simple app for riding a smart trainer at home: connect your trainer and sensors, shift virtual gears, follow structured ERG workouts, free ride with live numbers, ride virtual routes, review your history, and map controller buttons. The primary surface is a **landscape tablet or TV on the handlebars**, viewed from about 1 m away while you're out of breath.

**Source:** local codebase `Zmash/bikecontrol-main` (Flutter, shadcn_flutter, Lucide icons). This system is a from-scratch redesign, not a recreation of that UI. Only the feature scope and icon family came from the code.

## Index
- `styles.css`: entry point (imports only)
- `tokens/`: `colors.css` (light + `[data-theme="dark"]`), `typography.css`, `spacing.css`, `textures.css`, `fonts.css`
- `guidelines/*.card.html`: foundation specimen cards (Colors, Type, Spacing, Brand)
- `Zmash Components.dc.html`: the component sheet, light and dark side by side
- `Zmash Tablet App.dc.html`: click-through prototype: Home, Workouts/Routes picker, Devices, Live ride, Summary (History), Settings. Includes a theme toggle.
- `Zmash Directions.dc.html`: exploration history (turn 1: 1a/1b/1c, turn 2: 2a = chosen)
- `SKILL.md`: agent-skill entry

## Content fundamentals
- **Voice:** a calm teammate on race day. Short, direct, second person ("Pedal a few strokes to wake your trainer."). No hype, no exclamation marks, no emoji.
- **Casing:** Sentence case for titles and buttons ("Start ride", "Ride route"). UPPERCASE only for mono labels (POWER, ROUTE OF THE WEEK).
- **Numbers carry the message:** lead with the number, and keep the unit small and quiet ("287 W", "21.0 km"). Use the ′ prime for minutes in workout names ("4 × 8′ Threshold").
- **Microcopy examples:** "Ready when you are, Léa." · "Just pedal." · "Shift freely. Nothing to follow." · "Zmash remembers devices and reconnects on its own next time."
- Cycling vocabulary is welcome (ERG, FTP, TSS, W/kg). Don't explain it in the UI.

## Visual foundations
- **Mood:** energetic but restrained. Race-bib numerals and jersey stripes give it energy; flat surfaces, hairlines and a lot of bone and tarmac hold it back.
- **Colour:** warm neutral ramp from Bone (#F4F1EC) to Tarmac (#121110). Two accents share L=0.64 and C=0.19: **vermilion** means effort (primary action, hard intervals, ridden distance) and **team blue** means terrain (elevation, aerobic zones). Status green, amber and red always come with a label. Power zones run stone → blue → vermilion; the palette is deliberately not a rainbow.
- **Themes:** light and dark are equals, and all semantic tokens swap under `[data-theme="dark"]`. The **live-ride screen and HUD chips are always tarmac**, whatever the theme.
- **Type:** Archivo for everything. Numerals use Archivo at 62% width, weight 800 (the "bib" voice), tracked slightly tight. Headings are 700 with negative tracking. JetBrains Mono is used for uppercase labels (+0.14em) and clocks.
- **Bib numbers:** cards carry a big index (01, 02…) in `--fg-ghost`. It turns vermilion when the card is hero or selected.
- **Textures:** 1) fine **grain** over every screen background (multiply on light, screen on dark), 2) diagonal **bar-tape hatch** on hero cards and media placeholders, 3) **lane dashes** for free ride and distance, 4) the **tri-stripe** (vermilion 6 : ink or bone 1 : blue 2), 5px tall, on the top edge of each screen. Never use gradients as decoration.
- **Elevation profile:** a 1.5px bone/ink line over a blue fill, with the ridden portion filled vermilion and the rider shown as a bone dot with a 4px tarmac halo.
- **Cards:** 16px radius, 1px `--border`, no shadow. Selected = 2px vermilion ring (box-shadow). Hero = hatch with bone text. Sunk tiles (`--surface-sunk`, 12px radius) sit inside cards.
- **Shape:** pills (999) for every button, chip and nav item. Radii are 4 (key caps), 8, 12 (HUD chips, tiles), 16 (cards) and 22 (device/sheet).
- **Layout:** 32px screen gutter, 14–16px gaps between cards, top bar at 20px vertical padding. Nothing is fixed except the ride HUD.
- **Transparency and blur:** only for HUD chips over scenery (`rgba(18,17,16,.78)` + 12px blur) and glass pills in the top bar.
- **Shadows:** only on sheets and devices (`--shadow-sheet`).
- **Motion:** ease-out `cubic-bezier(.2,.7,.2,1)` at 140ms for press and toggle, 220ms for screens. Press = scale(.97). No bounces. Live numbers update without animating.
- **Hover:** borders step up to `--border-strong`. Colour doesn't change on hover.
- **Imagery:** route scenery is warm, a little grainy, at dusk or golden hour. Until real media exists, use the hatch placeholder with a mono caption.

## Iconography
- **Lucide** (the same family the codebase uses), loaded from CDN as the `lucide-static` icon font: `<i class="icon-heart">`. 1.5–2px stroke, sized 13–20px, inheriting `currentColor`.
- Icons used: play, pause, square, plus, minus, arrow-left, chevron-right, heart, zap, bike, bluetooth, gamepad-2, refresh-cw, share-2, sun, moon.
- Use icons sparingly: numbers and words come first. No emoji. Unicode ▲▼ are used only on controller key caps.
- **Logo:** there is no logo mark. The wordmark is "ZMASH" set in Archivo 80% width, 900 weight, italic. Don't invent a mark.
- **App icon:** "Sprint" (`design/app-icon/zmash-icon.svg`): a road bike with a vermilion frame, bone wheels, saddle and bars, trailing the tri-stripe as speed lines, on tarmac. It's the icon only: inside the app, the wordmark stays.

## Intentional additions
Everything is new: the source app's shadcn look was replaced at the user's request.
