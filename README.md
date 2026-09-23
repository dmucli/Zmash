# Zmash

An app for indoor cycling, made for the iPad and also running on iPhone and Mac. It connects to a Zwift Ride controller and a trainer over Bluetooth and shows your ride on a full-screen display. It handles virtual shifting and gradient on its own, without Zwift and without a subscription.

![The Paper face](design/screenshots/screenshot2.png)

It's a personal project, built for a Wahoo KICKR CORE 2 and a Zwift Ride (firmware 1.2.0) on an iPad in landscape.

## What it does

- **Live numbers:** speed, power, cadence, heart rate, time, distance, calories and climbing.
- **Speed that behaves like a bike:** speed comes from a physics model that accounts for your weight, the gradient and air resistance, so you accelerate, coast and slow down realistically.
- **Virtual shifting:** shift with the Ride's paddles and buttons. You can choose 3 to 24 gears.
- **Gradient control:**
  - *Manual:* set the gradient with the D-pad.
  - *Auto:* ride a generated course. Pick its length, terrain type and effort, and you can re-roll it.
- **Faces:** choose how the ride screen looks, the way you'd pick a watch face.
  - Eleven designs: Paper, Aura, Night, Horizon, Kinetic, Borne, Stem card, Piste, Groupset, Broadcast and Tarmac, plus a Classic dashboard.
  - Every face can be customised: pick its palette and which numbers it shows.
  - Switch faces mid-ride with the D-pad or a swipe.
  - A band along the bottom shows the whole course's profile (zoomable), your route or workout, and short messages for each kilometre, summit and best.
- **Workouts:**
  - A built-in library of structured workouts, including a ramp test.
  - Imports Zwift `.zwo` workout files.
  - The trainer can follow each target in ERG mode, or the targets become gradients.
  - An FTP estimate from your rides, and a ramp test if you want to measure it.
- **Routes:**
  - Ride by distance on a real elevation profile instead of a clock.
  - Real races: every stage of the 2025 and 2026 Tour de France, the 2026 Giro and Vuelta, ten 2026 stage races and sixteen classics, each with its profile, climbs and an estimated time at your pace. Ride a whole stage or just a segment of it (e.g. the last hour).
  - Twenty famous climbs as they were raced, cut from those races' files: Alpe d'Huez, Ventoux from Bédoin, the Tourmalet from both sides, the Galibier, the Loze, the Giau, the Poggio, the Paterberg and more.
  - Imports GPX and FIT files.
  - Race the ghost of your quickest previous attempt.
- **History:**
  - Every ride is saved on the iPad, with a list and a calendar view.
  - Each ride has charts, and a Progress tab with your power curve, weekly load and weekly time.
  - Share a ride as a card.
- **Export:** FIT files for anything that reads them, Apple Health, and direct upload to Strava and intervals.icu with your own account.
- **Picture in Picture:** keep your numbers in a floating window while you watch something else on the iPad.
- **Remappable controls:** every Ride button can be reassigned.
- **Diagnostics:** export a connection log from Settings.

## Hardware

| Device | How it connects |
|---|---|
| Zwift Ride (also Zwift Play and Click) | Zwift's controller protocol |
| Wahoo KICKR CORE 2, or any FTMS smart trainer | FTMS (standard), or Zwift's trainer protocol where supported |
| Older Wahoo trainers (KICKR, SNAP, CORE before FTMS) | Wahoo's own trainer control |
| Older Tacx trainers (Neo, Flux, Vortex, Genius) | ANT+ FE-C over Bluetooth |
| Basic (non-smart) trainers | Power worked out from wheel speed and the trainer's power curve; needs a speed sensor |
| Power meter | Standard Cycling Power; can be the source of your power numbers, with ERG matched to it |
| Speed or cadence sensor | Standard Cycling Speed and Cadence |
| Heart-rate strap | Standard Bluetooth heart-rate service |

Only the KICKR CORE 2 and the Zwift Ride have been tested on real hardware. The other trainers and sensors follow the published specifications and are covered by unit tests.

The Zwift Ride can only be connected to one app at a time, so close Zwift (and Zwift Companion) before riding with Zmash. Newer Ride firmware may change the protocol, so this app is tested with firmware 1.2.0.

There's also a demo mode, which simulates a trainer and a rider so you can try the app without any hardware.

## Building

You need:

- a Mac with Xcode 16 or later;
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`);
- an iPad or iPhone running iOS 18 or later, or an Apple silicon Mac (it runs as the iPad app).

```sh
make test          # run the unit tests (protocols, physics, workouts, routes, FIT export)
make races         # rebuild the bundled race catalog from gpx/ (kept locally, not committed)
make build-sim     # build for the Simulator, iPad or iPhone (the demo mode runs there; Bluetooth doesn't)
make build-mac     # build the Mac version (run it from Xcode: destination "My Mac (Designed for iPad)")
make devices       # list connected devices to find your iPad's identifier
make install DEVICE=<id>   # build, install and launch on the iPad
make open          # generate the Xcode project and open it
```

To install on your own iPad, set `DEVELOPMENT_TEAM` in `project.yml` to your own team. A free Apple account works. Apps signed that way stop launching after 7 days, and running `make install` again renews them.

## Project layout

```
Zmash/                 the iPad app (SwiftUI)
  Devices/             Bluetooth: controllers, trainer, heart rate, demo devices
  Session/             the live ride: timing, physics, trainer control, Picture in Picture
  UI/Faces/            the ride-screen faces
  Persistence/         saved rides (SwiftData), Apple Health export
Packages/ZmashKit/     protocol decoding, physics, gears, terrain, workouts, FIT writer, with tests
design/                the face designs the app is built from
```

Most of the logic lives in `ZmashKit`, a plain Swift package that is tested on the Mac without a device.

## Documents

- [BRIEF.md](BRIEF.md): the original spec. It covers the protocols, the physics and every screen.
- [DESIGN.md](DESIGN.md): the brief for the ride-screen faces.
- [DECISIONS.md](DECISIONS.md): the decisions made along the way, and why.
- [ROADMAP.md](ROADMAP.md): what's done and what's next.

## Credits

The protocol details come from public write-ups of the Zwift Ride and Zwift trainer protocols, and from the Bluetooth FTMS specification. No code from other projects is included.

The fonts (Archivo, Newsreader, Outfit, Roboto Flex) are used under the SIL Open Font License, and the icons come from [Lucide](https://lucide.dev).

Not affiliated with Zwift or Wahoo.
