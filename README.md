# Wolffe TV v4 Alpha 3.3.1

**Alpha 3.3.1 hotfix:** fixes the Swift comparison syntax in SSDP result sorting.

Adds automatic Roku SSDP discovery, duplicate detection, discovered device names/models, one-click adding, automatic input detection after addition, and manual-IP fallback.

## Build from Downloads
```bash
cd ~/Downloads/wolffe-tv-v4-alpha3.3.1-source
xattr -dr com.apple.quarantine .
chmod +x build-universal-dmg.sh
./build-universal-dmg.sh
```
Expected DMG: `build/Wolffe-TV-v4-alpha3.3.1-universal.dmg`.

Test Discover TVs, confirm both existing TVs are marked Added, retry without duplicates, and verify manual IP entry remains available. SSDP may be blocked by VLANs, guest Wi-Fi, client isolation, multicast filtering, or firewall policy.

Apache License 2.0. Experimental software provided **AS IS**. Ad-hoc signed, not Developer ID signed or Apple-notarized.

---
**Built with Microsoft Copilot ❤️**

Visual in this project was generated with Microsoft Copilot.
