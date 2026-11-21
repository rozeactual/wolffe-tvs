# Wolffe TV v4 Alpha 2.1

A native macOS local-network controller for Roku TVs using Roku ECP.

> ## ⚠️ EXPERIMENTAL SOFTWARE — NO WARRANTY
> Wolffe TV is independent experimental software distributed under the repository's Apache License 2.0. The software is provided on an **AS IS** basis, without warranties or conditions except as stated in that license. Wolffe TV is not affiliated with or endorsed by Roku, Hisense, Apple, or another device manufacturer. Users are responsible for reviewing the source, verifying release provenance, configuring their networks, and deciding whether to override macOS security protections. See `LICENSE` for the governing terms.

## Alpha 2.1 changes

- Fixes Swift macro/property-wrapper declarations so each `@Published` and `@State` wrapper applies to exactly one stored property.

## Alpha 2 changes

- Restores a native TV remote with Home, directional navigation, OK, Back, Play/Pause, Options, volume, mute, replay, and power controls.
- Converts `AppIcon-source.png` into `WolffeTV.icns` during each build.
- Copies and verifies the icon inside the application bundle.
- Builds one Universal app for Apple silicon and Intel Macs.
- Uses ad-hoc signing for local testing; the release is not Developer ID signed or Apple-notarized.

## Roku setup

On the TV, enable `Settings > System > Advanced system settings > Control by mobile apps > Network access`, using `Enabled` or `Default` as available. Find the address under `Settings > Network > About`.

Test ECP manually, replacing `TV_IP`:

```bash
curl --max-time 5 "http://TV_IP:8060/query/device-info"
curl --max-time 5 "http://TV_IP:8060/query/apps"
```

Both should return XML. Keep the TV and Mac mutually reachable over the local LAN. Never expose ports 8060 or the app to the public Internet.

## Privacy-oriented TV setup

Available Roku menus vary by model and software build:

- Turn off `Settings > Privacy > Smart TV Experience > Use info from TV inputs`, if present.
- Enable Limit Ad Tracking and reset the advertising identifier if those controls exist.
- Restrict channel microphone access if voice features are unwanted.
- Hide promotional Home-screen categories where Roku permits it.
- Remove unused channels.
- Set `Settings > System > Power > Power on` to the preferred HDMI input where supported.

For stronger isolation, configure the router/firewall so the Roku TV may communicate with trusted devices on the LAN but cannot reach the Internet/WAN. Do not enable client/AP/device isolation if it blocks the Mac from reaching the TV.

```text
Roku TV -> Internet/WAN: BLOCKED
Roku TV <-> trusted LAN: ALLOWED
```

Temporarily restore WAN access when intentionally checking for Roku updates, then reapply the block afterward.

## Building from source

Requirements:

- macOS 13 or newer
- Full Xcode, opened once to complete first-launch setup
- Xcode-selected Swift toolchain

Verify:

```bash
xcode-select --print-path
xcodebuild -version
swift --version
```

The selected path should normally be `/Applications/Xcode.app/Contents/Developer`. If standalone Command Line Tools are selected:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

Build:

```bash
chmod +x build-universal-dmg.sh
./build-universal-dmg.sh
```

Output:

```text
build/Wolffe TV.app
build/Wolffe-TV-v4-alpha2-universal.dmg
```

The script cleans prior output, builds `arm64` and `x86_64`, resolves SwiftPM's output using `--show-bin-path`, verifies both architectures, generates the `.icns`, assembles and ad-hoc signs the app, verifies the bundle, and creates the DMG. A packaging failure is fatal.

Verify manually:

```bash
lipo -archs "build/Wolffe TV.app/Contents/MacOS/WolffeTV"
codesign --verify --deep --strict --verbose=2 "build/Wolffe TV.app"
ls -lh "build/Wolffe TV.app/Contents/Resources/WolffeTV.icns"
```

## Opening this non-notarized build

This project does not currently use paid Developer ID signing or Apple notarization. macOS may block the first launch. First try opening Wolffe TV. If blocked, review the source and provenance before proceeding, then use `System Settings > Privacy & Security > Open Anyway` for Wolffe TV and authenticate when prompted. Do not globally disable Gatekeeper.

## Tested configuration

A Universal development DMG build succeeded on a MacBook Air with Apple M5, 24 GB unified memory, and 1 TB storage. Results may vary with macOS, Xcode, SwiftPM, SDK, security, network, and Roku versions.

TV control was tested on a Hisense 55R6+, hardware/model 7215X, Roku OS 16.0.4, build 853 / 39H.04E00853A.

## Alpha 2 test checklist

- The DMG builds without errors.
- Finder shows the Wolffe TV icon on the app.
- Setup and connection testing work.
- Four input buttons still switch correctly.
- TV Remote opens and each applicable key works.
- Power Off is visually distinct.
- Settings persist after quitting and reopening.
- Reset Setup still works.

## License

Apache License 2.0. Keep the repository's `LICENSE` and any applicable `NOTICE` with source and binary distributions.

---

**Built with Microsoft Copilot ❤️**

Visual in this project was generated with Microsoft Copilot.
