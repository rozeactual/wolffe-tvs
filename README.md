# Wolffe TV v4 Alpha 3.4.2 — REMOTE-01B

Moves the redesigned Remote into the main Wolffe TV window instead of presenting it as a modal sheet.

## Changes

- TV Remote now replaces the dashboard inside the existing app window.
- The main window remains resizable while the Remote is visible.
- Remote geometry follows the current main-window dimensions.
- Adds **Back to Inputs** navigation instead of a modal Done button.
- Removes the Remote's independent minimum/ideal sheet dimensions.
- Preserves the custom RemoteTile controls and every existing command mapping.
- Does not change networking, persistence, devices, inputs, or discovery behavior.

## Build from Downloads

```bash
cd ~/Downloads/wolffe-tv-v4-alpha3.4.2-source
xattr -dr com.apple.quarantine .
chmod +x build-universal-dmg.sh
./build-universal-dmg.sh
```

Expected DMG: `build/Wolffe-TV-v4-alpha3.4.2-universal.dmg`.

## Test focus

1. Open the Remote and confirm it appears in the same application window.
2. Resize the main window while the Remote is visible.
3. Confirm tiles reflow between two and three columns.
4. Select **Back to Inputs** and confirm the dashboard returns.
5. Test Home, navigation, volume, and power commands.

Apache License 2.0. Experimental software provided **AS IS**. Ad-hoc signed, not Developer ID signed or Apple-notarized.

---

**Built with Microsoft Copilot ❤️**

Visual in this project was generated with Microsoft Copilot.
