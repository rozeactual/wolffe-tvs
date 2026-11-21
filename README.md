# Wolffe TV v4 Alpha 3.6.1 — DISC-01 compile hotfix

Fixes Alpha 3.6 compilation by replacing Swift-inaccessible `FD_ZERO` / `FD_SET` C macros with macOS `poll(2)` for waiting on the already-bound UDP discovery socket. DISC-01's socket architecture and diagnostics otherwise remain unchanged.

## Build from Downloads

```bash
cd ~/Downloads/wolffe-tv-v4-alpha3.6.1-source
xattr -dr com.apple.quarantine .
chmod +x build-universal-dmg.sh
./build-universal-dmg.sh
```

Expected DMG: `build/Wolffe-TV-v4-alpha3.6.1-universal.dmg`.

After launch, open **Add TV** and report the diagnostics line exactly as displayed if discovery does not find the Roku TVs.

Apache License 2.0. Experimental software provided **AS IS**. Ad-hoc signed, not Developer ID signed or Apple-notarized.

---
**Built with Microsoft Copilot ❤️**

Visual in this project was generated with Microsoft Copilot.
