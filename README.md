# HiDPI Mirror

**Crisp, Retina-style scaling on non-Retina external monitors — and DDC brightness control — in a tiny macOS menu bar app.**

On Apple Silicon Macs, macOS only offers HiDPI ("Retina") resolutions on high-density displays. Plug in a 1440p monitor and you get two choices: native 2560×1440 with tiny UI, or a scaled mode like "looks like 1920×1080" that is noticeably blurry. HiDPI Mirror gives you the third option: the size you want, rendered at 2× and downsampled to the panel, the same way macOS treats a Retina display.

It is a small, focused alternative to the HiDPI feature of [BetterDisplay](https://github.com/waydabber/BetterDisplay) — about 1,200 lines of Swift, no dependencies.

## Features

- **HiDPI on any external display.** Pick a "looks like" size (2560×1440, 2304×1296, 1920×1080, …); the desktop is rendered at twice that and scaled to the panel's native resolution.
- **Keeps your refresh rate.** The virtual display is created at the panel's current refresh rate (tested at 180 Hz).
- **Brightness control over DDC/CI.** A native slider in the menu and the keyboard's brightness keys (F1/F2) adjust the monitor's own backlight, with an on-screen indicator like the built-in display's. Hold ⌥⇧ for quarter steps.
- **Safe by design.** Display changes are applied for the session only, nothing is written to disk, and quitting the app always restores the monitor. A global shortcut (**⌃⌥⌘H**) toggles HiDPI from anywhere in case something looks wrong.
- **Remembers your setup.** On/off state, display and size survive restarts, are re-applied after sleep, and the app can launch at login.
- **Stays the same size when turned off.** Switching HiDPI off moves the panel to the matching regular mode, so windows don't suddenly shrink.

## Requirements

- Apple Silicon Mac
- macOS 14 Sonoma or later (developed on macOS 27 with an M4 Pro and a 2560×1440 @ 180 Hz monitor)
- Xcode or the Swift toolchain to build

## Install

```sh
git clone https://github.com/ahmetozrahat/hidpi-mirror.git
cd hidpi-mirror
./build.sh --install
```

This builds a release binary, wraps it in `HiDPI Mirror.app`, installs it to `~/Applications` and launches it. A display icon appears in the menu bar.

`build.sh` signs the app with your first *Developer ID Application* certificate if you have one (override with `SIGN_IDENTITY=…`), otherwise ad-hoc. A stable signature matters for the brightness keys: macOS ties the Accessibility permission to it, and an ad-hoc signature changes on every build.

## Usage

Click the menu bar icon:

- **Turn HiDPI on/off** — or press **⌃⌥⌘H** anywhere.
- **Brightness** — drag the slider; it snaps to the same 16 steps as the keys.
- **View** — choose the "looks like" size. *(native)* marks the panel's own resolution.
- **Launch at login** and **Use brightness keys** toggles.

The menu UI is currently in Turkish.

### Brightness keys

The first time it runs, the app asks for **Accessibility** access (System Settings → Privacy & Security → Accessibility), which it needs to listen for the brightness keys. If another utility (MonitorControl, Vorssaint, Lunar, …) also handles brightness keys, turn that off there so the two don't fight over the monitor.

While HiDPI is on, the physical monitor is hidden behind the virtual display, so other brightness utilities usually can't see it anyway — that is why brightness lives in this app.

## How it works

```
             ┌───────────────────────────────┐
  macOS ───▶ │ Virtual display (HiDPI)       │  "looks like" 1920×1080
  renders    │ 3840×2160 pixel backing store │  rendered at 2×
             └───────────────┬───────────────┘
                             │ mirrored & downsampled
             ┌───────────────▼───────────────┐
             │ Physical monitor              │  native 2560×1440 @ 180 Hz
             └───────────────────────────────┘
```

1. **Virtual display.** The app creates a display with CoreGraphics' private `CGVirtualDisplay` API, with HiDPI enabled and a set of modes matching the monitor's aspect ratio and refresh rate. macOS then offers a 2× variant of each mode.
2. **Mirroring.** The physical monitor is pinned to its native mode and set to mirror the virtual display. macOS renders the desktop at 2× on the virtual display and scales the result down to the panel.
3. **Teardown.** Turning HiDPI off removes the mirror, switches the panel to the matching 1× mode and releases the virtual display. All configuration uses `CGConfigureOption.forSession`, and the app tears down cleanly on quit, `SIGTERM` and `SIGINT`.

The older trick of dropping a display override plist into `/Library/Displays/…/Overrides` doesn't unlock HiDPI modes for 1440p panels on Apple Silicon, which is why this approach is needed.

**Brightness** uses DDC/CI, the protocol monitors expose over the video cable for their on-screen menu settings. On Apple Silicon the I2C bus is reached through the private `IOAVService` API; the app matches the right bus to the monitor by its EDID vendor, product and serial numbers in the IORegistry. Writes are coalesced so dragging the slider or holding a key never builds up a backlog, and the final value is resent once input settles in case the monitor dropped it.

## Project layout

| Path | What's there |
| --- | --- |
| `Sources/HiDPIMirror/MirrorController.swift` | Virtual display creation, mirroring, mode selection and teardown |
| `Sources/HiDPIMirror/Displays.swift` | Physical display discovery and the list of offered sizes |
| `Sources/HiDPIMirror/DDC.swift` | DDC/CI reads and writes over `IOAVService` |
| `Sources/HiDPIMirror/BrightnessController.swift` | Coalesced brightness writes and key stepping |
| `Sources/HiDPIMirror/MediaKeyTap.swift` | Event tap for the brightness keys |
| `Sources/HiDPIMirror/BrightnessSlider.swift`, `BrightnessHUD.swift` | Menu slider and on-screen indicator |
| `Sources/HiDPIMirror/AppDelegate.swift` | Menu bar UI, settings, sleep/wake and hot-plug handling |
| `Sources/PrivateAPIs/include/` | Headers for the private CoreGraphics and IOKit APIs |

## Diagnostics

Two command-line flags help check things without touching your setup, e.g. after a macOS update:

```sh
.build/release/HiDPIMirror --probe     # create the virtual display, list its modes, remove it
.build/release/HiDPIMirror --ddc       # read the monitor's brightness over DDC
.build/release/HiDPIMirror --ddc 60    # set it to 60, then read it back
```

`--probe` does not mirror anything, so the monitor stays as it is.

## Limitations

- **Private APIs.** `CGVirtualDisplay` and `IOAVService` are undocumented. The app can't ship on the Mac App Store, and a macOS update could break it — `--probe` and `--ddc` are the quickest way to find out.
- **Mirroring trade-offs.** Variable refresh rate (adaptive sync) and HDR are likely unavailable while HiDPI is on.
- **Leftover virtual display.** If the process is killed abruptly while the virtual display is being set up, macOS can keep it around until you log out. The app detects this and says so in the menu.
- **DDC support varies.** Most monitors support brightness over DDC/CI, but some disable it in their own settings or over certain inputs/docks.

## Credits

Built on what others figured out about these private APIs:

- [BetterDummy / BetterDisplay](https://github.com/waydabber/BetterDisplay) — virtual displays with `CGVirtualDisplay`
- [MonitorControl](https://github.com/MonitorControl/MonitorControl) and [m1ddc](https://github.com/waydabber/m1ddc) — DDC/CI on Apple Silicon
- Chromium's `virtual_display_mac_util` — `CGVirtualDisplay` declarations

## License

[MIT](LICENSE)
