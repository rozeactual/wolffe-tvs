# Wolffe TV v4 Alpha 3.2.1

Adds per-TV physical-input detection, dynamic input buttons, renaming, visibility controls, restore, and refresh while preserving per-TV customizations. This hotfix uses Apple-platform `Foundation` for `XMLParser`; it does not import `FoundationXML`.

## Build from Downloads

```bash
cd ~/Downloads/wolffe-tv-v4-alpha3.2.1-source
xattr -dr com.apple.quarantine .
chmod +x build-universal-dmg.sh
./build-universal-dmg.sh
```

Expected DMG: `build/Wolffe-TV-v4-alpha3.2.1-universal.dmg`.

Test both saved TVs, detect inputs, rename/hide one input on TV2, refresh, and verify the customization stays isolated to TV2.

Apache License 2.0. Experimental software provided **AS IS**. Ad-hoc signed, not Developer ID signed or Apple-notarized.

---

**Built with Microsoft Copilot ❤️**

Visual in this project was generated with Microsoft Copilot.
