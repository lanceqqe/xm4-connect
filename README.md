<p align="center">
  <img src="docs/icon.png" width="140" alt="XM Connect icon">
</p>

<h1 align="center">XM Connect</h1>

<p align="center">
  <b>Control your Sony WH-1000XM5 from the Mac menu bar — with a live 3D headset that reacts to every setting.</b>
</p>

<p align="center">
  <a href="#install"><b>Install</b></a> ·
  <a href="#features">Features</a> ·
  <a href="#troubleshooting">Troubleshooting</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#build-from-source">Build from source</a>
</p>

<p align="center">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white">
  <img alt="Apple silicon and Intel" src="https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-555">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue">
  <img alt="Languages" src="https://img.shields.io/badge/UI-English%20%7C%20Fran%C3%A7ais-6C63FF">
</p>

<p align="center">
  <img src="docs/screenshot.png" width="360" alt="XM Connect panel: 3D headset in noise cancelling mode and the equalizer">
  &nbsp;&nbsp;
  <img src="docs/menubar.png" width="380" alt="XM Connect opened from the macOS menu bar">
</p>

---

Sony's **Sound Connect** app only exists for phones. XM Connect brings the same controls to the Mac. It talks to the headphones directly over Bluetooth, using the same "MDR" protocol as Sony's app, and puts everything one click away in the menu bar.

There is no account, no server, no telemetry and no Electron. It is a small native Swift app that links only against frameworks that ship with macOS.

> XM Connect is an independent open-source project. It is **not affiliated with, endorsed by or supported by Sony.**

## Features

### Headphone controls

| | |
| --- | --- |
| 🎧 **Noise control** | Noise Cancelling, Ambient Sound or Off. Switch from the mode tiles, by clicking the 3D headset, or by right-clicking the menu bar icon |
| 🌬️ **Ambient sound** | Level 1–20 and Focus on Voice |
| 🎛️ **Equalizer** | All 9 Sony presets plus Manual, Custom 1 and Custom 2. On the editable ones, drag the points of a smooth curve (400 Hz, 1k, 2.5k, 6.3k, 16k) and the Clear Bass slider. 10-band models are supported too |
| ⏸️ **Pause when taken off** | Playback pauses when you take the headphones off and resumes when you put them back on ([details](#pause-when-taken-off)) |
| 💬 **Speak-to-Chat** | On or off |
| ✨ **DSEE Extreme** | On or off |
| ⏲️ **Auto power off** | 5 min to 3 h, or never |
| 🔋 **Battery** | Level and charging state in the panel and, if you want, next to the menu bar icon |
| ⏻ **Power off** | Turn the headphones off from the Mac |
| 🔄 **Two-way sync** | Press a button on the headphones and the app follows instantly |
| 🔌 **Auto-reconnect** | Turn the headphones off and on again; the app finds them by itself |

The app only shows and sends the settings your headphones announce. Other recent Sony models (WH-1000XM4/XM6, WF-1000XM4/XM5, LinkBuds…) generally work, with the subset of controls they support.

### The visual side

- **A real-time 3D headset** built in code with SceneKit. It floats, spins under your pointer with inertia and spring physics, and does a full turn every time the mode changes.
- **Noise cancelling** wraps it in a glowing energy bubble. Sound particles drift in from far away and burst against it.
- **Ambient sound** lets the particles flow through to the ears, and sound rings converge on the ear cups. Higher ambient levels make them denser.
- **Colour follows the mode**: the ear-cup lights, rim light, bloom and the drifting background all change together.
- **Tilt-on-hover mode tiles**, an equalizer curve that **morphs** between presets, and **trackpad haptics** on every step.
- **Four finishes** for the 3D headset: Black, Platinum, Midnight and Sand.
- **Reduce motion** option, which also follows the macOS accessibility setting.

### Everything else

- **English and French.** The app follows your macOS language; force one in *Options › Language*, and it switches instantly.
- **Demo mode**: a simulated WH-1000XM5, so you can try every control without headphones.
- **Open at login**, **battery in the menu bar** and **reduce motion** are all toggles in Options.

## Install

You need **macOS 13 Ventura or newer**, on Apple silicon or Intel.

### Option 1 — One line in Terminal (recommended)

Open **Terminal** (⌘-Space, type *Terminal*) and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/omidkrm/xm-connect/main/install.sh | bash
```

[The script](install.sh) is about 50 lines; read it before running it if you like. It:
1. downloads the latest release;
2. **checks its SHA-256** against the checksum published with the release;
3. copies *XM Connect* into `/Applications`;
4. opens it.

Installed this way, macOS opens the app without any warning.

### Option 2 — Installer or disk image

Download from the [**latest release**](https://github.com/omidkrm/xm-connect/releases/latest):

- **`XM-Connect-Installer.pkg`**: a standard macOS installer, in English and French. It installs into Applications and opens the app when done.
- **`XM-Connect.dmg`**: drag *XM Connect* into *Applications*.

XM Connect is not verified by Apple as coming from a registered developer, so macOS stops it the first time. Allow it once:

- **macOS 15 Sequoia and newer**:
  1. Open the file and click **Done** on the warning.
  2. Go to **System Settings › Privacy & Security** and scroll down to *"XM Connect… was blocked"*.
  3. Click **Open Anyway** and confirm with your password.
- **macOS 13–14**: **right-click** (or Control-click) the file, choose **Open**, then **Open** again.

### Option 3 — Build it yourself

You need the Xcode Command Line Tools. The full Xcode is not required.

```bash
xcode-select --install            # once
git clone https://github.com/omidkrm/xm-connect.git
cd xm-connect
make install                      # builds and copies "XM Connect.app" to /Applications
open "/Applications/XM Connect.app"
```

See [Build from source](#build-from-source) for more.

### First launch

1. Look for the **headphones icon** in the menu bar. There is no Dock icon and no window.
2. **Allow Bluetooth** when macOS asks. Without it, the app cannot talk to the headphones.
3. Make sure your headphones are **connected** to this Mac, not just paired. Connect them in *System Settings › Bluetooth* or from Control Center. The app picks them up within a few seconds.

### Uninstall

Quit the app (right-click the menu bar icon › **Quit XM Connect**), then delete *XM Connect* from Applications. To remove its settings and log as well:

```bash
defaults delete app.xmconnect.mac
rm -rf ~/Library/Logs/XM\ Connect
```

## Usage

| Action | How |
| --- | --- |
| Open the panel | **Left-click** the menu bar icon |
| Quick actions (mode, demo, open at login, quit) | **Right-click** the menu bar icon |
| Spin the 3D headset | **Drag** it |
| Next listening mode | **Click** the 3D headset |
| Close the panel | **Esc**, or click anywhere else |
| Turn the headphones off | **Turn off headphones** at the bottom, then confirm |
| Logs, demo mode, quit | **⋯** button at the bottom right |

The panel has three tabs:
- **Listening**: ambient level, Focus on Voice, Speak-to-Chat, pause when taken off.
- **Equalizer**: presets and the curve editor.
- **Options**: DSEE Extreme, auto power off, 3D finish, language, battery in the menu bar, open at login, reduce motion.

### Pause when taken off

The XM5 reports whether it is being worn through a secondary channel of its protocol ("table 2"). XM Connect listens to it, and the header shows *on your head* or *taken off*.

- **When you take the headphones off**, the Mac pauses whatever is playing: Music, Spotify, a browser… It sends an explicit *pause* command, not the play/pause key, so nothing ever starts by accident.
- **When you put them back on**, playback resumes, but only if XM Connect was the one that paused it. You can turn resuming off in the Listening tab.
- **If the headphones also have their own "pause when taken off" setting**, XM Connect sets it too and reads it back to confirm.

### Launch arguments

| Argument | Effect |
| --- | --- |
| `--demo` | Start with the simulated headset |
| `--open` | Open the panel right away |
| `--verbose` | Mirror the log to the terminal |

```bash
open "/Applications/XM Connect.app" --args --demo
```

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| *"Connect the headphones to this Mac"* | They are paired but not connected. Connect them from the Bluetooth menu or Control Center |
| *"Headphones not found"* | Turn the headphones on; make sure they appear in System Settings › Bluetooth |
| Nothing ever connects | System Settings › Privacy & Security › **Bluetooth**: XM Connect must be allowed |
| Controls work on the phone but not on the Mac | Multipoint: make sure the headphones are actively connected to the Mac too |
| A setting jumps back | The headphones rejected it; the app re-reads their state so it never shows a value they do not have. Please open an issue with the log |
| Pause when taken off does nothing | Open the log and look for the lines starting with `Table 2:`, `Capabilities:` and `Table-2 event:`; include them in an issue |
| macOS says the app can't be verified | Install with [Option 1](#option-1--one-line-in-terminal-recommended), or allow it once with *Open Anyway* ([steps](#option-2--installer-or-disk-image)) |

The log is at `~/Library/Logs/XM Connect/app.log`; open it from **⋯ › Open the log**. It contains the raw protocol traffic, which is the most useful thing to attach to a bug report.

## How it works

The headphones expose a classic-Bluetooth **RFCOMM** service, UUID `956C7B26-D49A-4BA8-B03F-B17D393CB6E2`. XM Connect opens it with IOBluetooth. Over that channel, the app and the headphones exchange frames:

```
3E | type | seq | length (4 bytes, big-endian) | payload | checksum | 3C
```

- Bytes `3C`, `3D` and `3E` inside the frame are escaped with `3D`.
- The checksum is the 8-bit sum of everything between the markers.
- Every data frame is acknowledged with an `ACK` (`type 01`) carrying the next sequence number.
- Type `0C` carries main ("table 1") messages and `0E` carries secondary ("table 2") ones.

On connection, the app runs a short handshake:
1. it asks for the **protocol info** (`00 00`);
2. it asks for the list of **supported functions** (`06 00`);
3. it only ever sends commands for functions the headphones announced.

A few of the messages:

| Function | Read | Write |
| --- | --- | --- |
| Noise cancelling / ambient (XM5) | `66 17` | `68 17 01 <on> <ambient> <voice> <level>` |
| Equalizer preset | `56 00` | `58 00 <preset> 00` |
| Equalizer bands (Clear Bass + 5) | `56 00` | `58 00 <preset> 06 <cb> <b1>…<b5>` (value + 10) |
| Battery | `22 00` | — |
| Power off | — | `24 03 01` |
| Speak-to-Chat | `F6 0C` | `F8 0C <on=00/off=01> 01` |
| Pause when taken off | `F6 01` | `F8 01 <on=00/off=01>` |
| DSEE Extreme | `E6 01` | `E8 01 <off=00/auto=01>` |
| Auto power off | `26 04` | `28 04 <timer> 00` |
| Wearing status (table 2) | `F2 00` | notifications `F5 00 <00 worn, 02–04 off>` |

The protocol core (`SonyProtocolKit`) is pure Swift with no platform dependencies, and is covered by a test suite (`make test`).

### Project layout

```
Sources/
  SonyProtocolKit/      framing, commands, payload parsing (pure Swift, tested)
  SonyProtocolTests/    protocol test suite (no XCTest needed)
  XMConnect/
    Bluetooth/          IOBluetooth RFCOMM transport, session, reconnect loop
    Model/              app state, translations, demo headset, media pause, logging
    Scene/              the 3D headset and its effects (SceneKit)
    UI/                 menu bar panel, controls, equalizer, tabs
Resources/              Info.plist, localized InfoPlist.strings, app icon
installer/              .pkg screens (EN/FR), install scripts, disk image background
scripts/                icon renderer (Python), disk image window layout
install.sh              one-line installer
```

## Build from source

You need the **Xcode Command Line Tools** (`xcode-select --install`). The full Xcode is not required: the Makefile drives `swiftc` directly.

| Command | Result |
| --- | --- |
| `make` | `build/XM Connect.app` for this Mac |
| `make run` | Build and launch |
| `make demo` | Build and launch in demo mode |
| `make install` | Copy to `/Applications` |
| `make test` | Run the protocol test suite |
| `make universal` | Apple silicon + Intel build |
| `make pkg` | `build/XM Connect Installer.pkg` |
| `make dmg` | `build/XM Connect.dmg` |
| `make zip` | `build/XM-Connect-macos.zip` (what `install.sh` downloads) |
| `make clean` | Remove `build/` |

`Package.swift` is there so you can browse and edit the code in Xcode. Run the real app with `make`, though: macOS only shows the Bluetooth prompt for a proper `.app` bundle with its `Info.plist`.

The app icon is drawn by `scripts/render_icon.py` (Pillow + NumPy). The generated PNGs are committed, so Python is not needed to build.

### Releasing

Bump `CFBundleShortVersionString` in `Resources/Info.plist` (for example to `1.2.0`) and push to `main`. Pushing a `v1.2.0` tag works too.

When `main` carries a version that has no release yet, the [release workflow](.github/workflows/release.yml):
1. runs the tests;
2. builds the universal app, zip, installer and disk image;
3. publishes them as a GitHub release, creating the `vX.Y.Z` tag.

## Contributing

Issues and pull requests are welcome, especially:

- **Reports from other Sony models**: open an issue with the `Capabilities:` line from the log.
- **New settings**, such as multipoint, touch controls or the NC/AMB button setting. Please add a test in `Sources/SonyProtocolTests` with the exact bytes.
- **Translations**: every string is written as `L("English", "Français")` at its call site, so adding a language is a matter of extending `Localization.swift`.

## Credits

XM Connect would not exist without two open-source projects, both MIT-licensed:

- **[sony-tray](https://github.com/abhiinhii/sony-tray)** by Abhinav ([@abhiinhii](https://github.com/abhiinhii)) and contributors. It provided the framing, noise control, equalizer, battery, the IOBluetooth transport, the session and reconnect logic, and the test suite, all verified on a WH-1000XM5. Files taken from it are marked at the top.
- **[SonyHeadphonesClient](https://github.com/mos9527/SonyHeadphonesClient)** by mos9527, Amr Satrio and contributors. It provided the message layouts for Speak-to-Chat, DSEE, pause when taken off, auto power off and the wearing status.

Their licences are in [`THIRD_PARTY_LICENSE_sony-tray.txt`](THIRD_PARTY_LICENSE_sony-tray.txt) and [`THIRD_PARTY_LICENSE_SonyHeadphonesClient.txt`](THIRD_PARTY_LICENSE_SonyHeadphonesClient.txt).

## Disclaimer

XM Connect is not affiliated with, endorsed by or supported by Sony Group Corporation. "Sony", "WH-1000XM5", "Sound Connect", "DSEE Extreme", "Speak-to-Chat" and "Clear Bass" are trademarks of Sony Group Corporation, used here only to describe compatibility.

The software is provided as is, without warranty. It only sends the documented commands the headphones announce support for, but use it at your own risk.

## License

[MIT](LICENSE)
