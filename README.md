# Wolffe TV v4 Alpha 3.5 — Input Customization Polish

Adds per-TV input ordering, icon selection, accent colors, and a clearer input editor while preserving the Alpha 3.4.2 Remote and working control architecture.

## Changes

- Move inputs up or down in **Customize Inputs**.
- Persist custom ordering separately for each TV.
- Select an SF Symbol icon for each input.
- Select an accent color for each input.
- Preview the chosen input name, icon, and color in the editor.
- Preserve name, visibility, order, icon, and color when refreshing inputs from the TV.
- Existing Alpha 3.4.2 records remain compatible because the new appearance fields are optional.

## Build from Downloads

```bash
cd ~/Downloads/wolffe-tv-v4-alpha3.5-source
xattr -dr com.apple.quarantine .
chmod +x build-universal-dmg.sh
./build-universal-dmg.sh
```

Expected DMG: `build/Wolffe-TV-v4-alpha3.5-universal.dmg`.

## Test focus

1. Confirm existing TVs, inputs, and Remote remain intact.
2. Reorder two inputs and select Done.
3. Assign a different icon and color to one input.
4. Close and reopen the app; confirm order and appearance persist.
5. Refresh inputs from the TV; confirm custom order, icon, color, name, and visibility remain.
6. Switch TVs and confirm customization remains isolated per TV.

Automatic SSDP discovery remains a known deferred issue. Manual IP entry remains available.

Apache License 2.0. Experimental software provided **AS IS**. Ad-hoc signed, not Developer ID signed or Apple-notarized.

---

**Built with Microsoft Copilot ❤️**

Visual in this project was generated with Microsoft Copilot.
