# Wolffe TV v4

Wolffe TV v4 is the native macOS branch of Wolffe TV, a local-network controller for Roku TVs using Roku's External Control Protocol (ECP).

> **Status:** v4 is currently an alpha/development build. The native application and Universal DMG build pipeline have been successfully built locally, but public release signing/notarization is a separate release step.

## Developer quick start

### Requirements

- macOS development machine
- Full Xcode installation
- Swift toolchain supplied through Xcode
- Git, if cloning from source control
- A Roku TV reachable from the Mac over the local network for functional testing

Full Xcode matters. Apple's standalone Command Line Tools live at `/Library/Developer/CommandLineTools`, while a normally installed full Xcode uses `/Applications/Xcode.app/Contents/Developer`. Apple documents `xcode-select --print-path` as the way to inspect the active developer directory. Full Xcode also includes command-line development tools. See Apple's Xcode documentation for current details.

### 1. Install and initialize Xcode

Install the current compatible release of Xcode from Apple. Launch Xcode at least once and complete any first-launch setup prompts.

Confirm which developer directory is active:

```bash
xcode-select --print-path
```

For a standard Xcode installation, the expected path is:

```text
/Applications/Xcode.app/Contents/Developer
```

If the standalone Command Line Tools are selected instead, switch to full Xcode:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

If Xcode is installed somewhere else, substitute its actual path. Apple explicitly supports selecting a nonstandard Xcode location with `xcode-select`.

Verify the toolchain:

```bash
xcodebuild -version
swift --version
xcrun --find swift
```

### 2. Obtain the source

Clone the repository and enter the project directory:

```bash
git clone <repository-url>
cd wolffe-tv-v4-source
```

For a downloaded source archive, extract it and change into the extracted directory instead.

The root should contain at least:

```text
Package.swift
Info.plist
build-universal-dmg.sh
Sources/
```

### 3. Build the Swift package directly

For a normal development build:

```bash
swift build
```

For an optimized release build:

```bash
swift build -c release --product WolffeTV
```

Swift Package Manager is the project's build system. SwiftPM 6.4 uses Swift Build by default and may place artifacts differently than older SwiftPM versions. Do not write tooling that assumes a fixed `.build/<architecture>/release` path.

To obtain the actual output directory, use:

```bash
swift build -c release --product WolffeTV --show-bin-path
```

### 4. Build the Universal macOS application and DMG

Make the build script executable once:

```bash
chmod +x build-universal-dmg.sh
```

Then run:

```bash
./build-universal-dmg.sh
```

The build script is intended to:

1. Preflight the selected Xcode/Swift environment.
2. Clean generated `.build` and `build` directories.
3. Build the `WolffeTV` release product for both `arm64` and `x86_64`.
4. Ask SwiftPM for the actual binary location with `--show-bin-path`.
5. Verify that the resulting executable contains both architectures.
6. Assemble `Wolffe TV.app` with its `Info.plist`.
7. Apply an ad-hoc signature for local development/testing.
8. Verify the app bundle before packaging.
9. Create a DMG containing the app and an Applications shortcut.

SwiftPM 6.4 officially supports multiple architecture arguments when building Universal binaries for Apple platforms, including `--arch arm64 --arch x86_64`.

Expected development artifacts:

```text
build/Wolffe TV.app
build/Wolffe-TV-v4-universal.dmg
```

### 5. Verify the Universal binary

Inspect the executable architectures:

```bash
lipo -archs "build/Wolffe TV.app/Contents/MacOS/WolffeTV"
```

The Universal build should report both:

```text
arm64 x86_64
```

Inspect the app signature:

```bash
codesign --verify --deep --strict --verbose=2 "build/Wolffe TV.app"
```

For an ad-hoc development build, this verifies structural signing but does **not** turn the app into a Developer ID/notarized public release.

### 6. Test the DMG

Open:

```text
build/Wolffe-TV-v4-universal.dmg
```

Copy Wolffe TV to Applications and launch the newly built copy. Test at minimum:

- first-run setup;
- TV name persistence;
- IPv4 configuration;
- connection testing;
- HDMI 1 switching;
- HDMI 2 switching;
- HDMI 3 switching;
- AV/composite switching;
- online/offline status;
- setup reset;
- relaunch with persisted settings.

A release intended for both architectures should be tested on Apple silicon and Intel hardware before publication.

## Clean builds

Remove all generated SwiftPM and packaging output:

```bash
rm -rf .build build
```

Then rebuild:

```bash
./build-universal-dmg.sh
```

This is particularly useful after changing Xcode/toolchains or when investigating stale build artifacts.

## Troubleshooting

### `SwiftUIMacros.StateMacro` / `plugin for module 'SwiftUIMacros' not found`

Check the active developer directory:

```bash
xcode-select --print-path
```

If it reports:

```text
/Library/Developer/CommandLineTools
```

select the full Xcode installation, then clean and rebuild:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
rm -rf .build build
./build-universal-dmg.sh
```

### Build succeeds but the script cannot find `WolffeTV`

Do not hard-code an old SwiftPM output directory. Query SwiftPM:

```bash
swift build -c release --product WolffeTV --arch arm64 --arch x86_64 --show-bin-path
```

SwiftPM 6.4 changed build artifact placement and explicitly recommends `--show-bin-path` for determining the output location.

### macOS says the app is damaged or incomplete

First verify that the executable actually exists:

```bash
ls -l "build/Wolffe TV.app/Contents/MacOS/WolffeTV"
```

Then verify the bundle's signature:

```bash
codesign --verify --deep --strict --verbose=2 "build/Wolffe TV.app"
```

A packaging failure should not be treated as a successful app build. Delete `build` and rebuild after resolving the underlying error.

## Project architecture

```text
wolffe-tv-v4-source/
├── Package.swift
├── Info.plist
├── AppIcon-source.png
├── build-universal-dmg.sh
├── README.md
└── Sources/
    └── WolffeTV/
        └── main.swift
```

`Package.swift` defines the Swift package and executable product. `main.swift` contains the current SwiftUI application and Roku ECP client logic. `Info.plist` supplies application-bundle metadata. `build-universal-dmg.sh` handles Universal release building and local DMG packaging.

## Local-network development

The application communicates with the configured Roku TV over the local network. Keep the computer and television mutually reachable on the LAN while testing. Internet/WAN access for the television is not required for the local ECP input-control workflow itself.

Do not expose the Roku ECP service to the public Internet.

## Version control guidance

Do not commit:

- `.build/`;
- `build/`;
- locally generated DMGs;
- signing credentials;
- notarization credentials;
- Roku serial numbers, MAC addresses, advertising identifiers, or private device information.

A typical project `.gitignore` should therefore include at least:

```gitignore
.build/
build/
.DS_Store
*.dmg
```

## Signing and public distribution

The development build script uses ad-hoc signing for local testing. That is intentionally different from a public macOS release.

For direct public distribution outside the Mac App Store, Apple documents Developer ID signing and notarization. Apple's notary service checks Developer ID-signed software and supports macOS applications and disk images. Current command-line notarization workflows use `notarytool`; Apple no longer accepts `altool` for this workflow.

A future release workflow should therefore keep these stages separate:

```text
source
  ↓
Universal release build
  ↓
.app bundle
  ↓
Developer ID signing
  ↓
DMG packaging/signing
  ↓
Apple notarization
  ↓
staple/validate ticket
  ↓
release artifact
```

Never commit Apple Developer certificates, private keys, app-specific passwords, or notary-service credentials to the repository.

## Notes for contributors

- Keep the Roku interaction layer local-network only.
- Prefer APIs available in the project's declared macOS deployment target.
- Preserve support for both Apple silicon and Intel until the project explicitly changes that policy.
- Keep packaging failures fatal. A partially assembled `.app` should never be presented as a successful release artifact.
- When changing SwiftPM build arguments, use the same arguments with `--show-bin-path` when locating the resulting product.
- Test networking changes against a real Roku TV before treating them as release-ready.

## Current status

The Universal macOS build pipeline has successfully produced a working development DMG after correcting two environment/tooling issues encountered during early v4 development: selecting full Xcode rather than standalone Command Line Tools, and querying SwiftPM for its actual output path rather than assuming an older `.build` layout.
