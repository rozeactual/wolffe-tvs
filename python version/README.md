# Wolffe TV v3

Wolffe TV is a local-only dashboard for switching a Roku TV between HDMI and AV inputs over Roku's External Control Protocol (ECP). It uses Python's standard library and does not require cloud hosting, accounts, analytics, npm, or third-party Python packages.

## Successfully tested television

Wolffe TV v3 is based on successful testing with:

- Manufacturer: Hisense
- Model: 55R6+
- Hardware/model number: 7215X
- Roku OS/software version: 16.0.4
- Software build: 853 / 39H.04E00853A
- ECP port: 8060

Other Roku TVs may work, but their input availability and menu wording can differ.

## Dashboard controls

- Apple TV: HDMI 1 / ARC
- Unused: HDMI 2
- Unused: HDMI 3
- Wii: AV / Composite
- TV Settings: Home, Back, directional controls, and OK
- Advanced > Reset Setup: deletes the local `config.json`, restarts first-run setup in Terminal, and asks for a new IP address and TV name

The button labels are currently fixed in `index.html`. The setup name appears as the dashboard heading and browser title.

## Roku TV preparation

### 1. Enable local network controls

On the Roku TV, open:

`Settings > System > Advanced system settings > Control by mobile apps > Network access`

Choose `Enabled` or `Default`, depending on the options shown by the TV. Roku documents that recent Roku OS versions require Control by mobile apps to be enabled for ECP keypress commands. Developer Mode is not required for the standard input and remote commands used by this dashboard.

Source: https://developer.roku.com/dev/docs/external-control-api

### 2. Find the TV's IP address

Open:

`Settings > Network > About`

Write down the local IPv4 address. The TV and the Mac running Wolffe TV must remain reachable over the local network.

A reserved/fixed DHCP assignment in the router is recommended so the address does not change.

### 3. Reduce Roku tracking and Home-screen clutter

Available settings vary by Roku TV and software build. Use only options actually shown on your television.

- Open `Settings > Privacy > Smart TV Experience` and turn off `Use info from TV inputs` or the equivalent Smart TV Experience option. Roku states this disables ACR collection for content viewed through connected inputs and the TV antenna.
- If `Settings > Privacy > Advertising` is present, enable `Limit ad tracking` and reset the advertising identifier. This option is not available on every television.
- Under `Settings > Privacy > Microphone`, restrict channel microphone access if voice features are not wanted.
- Under `Settings > Home screen`, hide promotional or recommendation categories that your software build allows you to hide.
- Remove unused streaming channels from Roku Home.
- Under `Settings > System > Power > Power on`, choose HDMI 1 if the Apple TV should be the normal startup input.

Roku notes that turning off Smart TV Experience affects ACR collection from TV inputs and antenna viewing, but does not stop all data associated with Internet streaming services.

Source: https://docs.roku.com/published/smarttvexperience/en/US

## Block the TV's Internet/WAN access while keeping local LAN access

For the strongest privacy setup, keep the television connected to your home network but prevent it from reaching the public Internet. Wolffe TV only needs local connectivity between the computer running the dashboard and the Roku TV.

Router and firewall terminology varies by manufacturer. Look for features named something similar to `Block Internet`, `Pause Internet`, `Access Control`, `Firewall Rules`, `Device Rules`, `Parental Controls`, or `WAN Access`.

The desired result is simple:

```text
Roku TV -> Internet/WAN: BLOCKED
Roku TV <-> trusted local network/LAN: ALLOWED
```

General setup:

1. Find the Roku TV in your router or firewall's connected-device/client list.
2. If supported, reserve its current IP address with DHCP so the TV keeps the same local address.
3. Create a device-specific rule that blocks Internet/WAN access for the Roku TV.
4. Keep access to the local LAN enabled so the computer running Wolffe TV can still reach the television.
5. Avoid options such as `Client Isolation`, `AP Isolation`, `Device Isolation`, `Guest Isolation`, `Block Local Network`, or similar features if they prevent trusted local devices from communicating with the TV.
6. Do not expose Wolffe TV or Roku ECP to the public Internet with port forwarding.

### Verify that local control still works

From the computer running Wolffe TV, replace `TV_IP` with the television's address:

```bash
curl --max-time 5 "http://TV_IP:8060/query/device-info"
curl --max-time 5 "http://TV_IP:8060/query/apps"
```

Both commands should continue returning XML after Internet/WAN access is blocked. If they stop working, review the router/firewall rule and confirm it blocks Internet access only, rather than local LAN communication.

## OTA software updates and local ECP controls

Wolffe TV does not disable the TV's OTA/software-update components. A WAN-blocked TV cannot normally download an online Roku update while the block is active.

For a controlled update window:

1. Temporarily disable or pause the Roku TV Internet/WAN-block rule in your router or firewall.
2. On the TV, open `Settings > System > Software update > Check Now`.
3. Allow the update and any required restart to finish.
4. Confirm that the dashboard still switches inputs.
5. Re-enable the Internet/WAN-block rule.

Roku documents `Settings > System > Software update > Check Now` as the manual software-update path and notes that disconnected Roku TV systems may also support USB updates.

Source: https://support.roku.com/article/article/update-the-software-on-your-streaming-device

For dashboard control, keep `Control by mobile apps > Network access` enabled. ECP operates over the local network on port 8060.

## Python requirement on macOS

Wolffe TV requires Python 3. Do not assume every Mac already has a suitable user-installed copy. Before the first launch, open Terminal and run:

```bash
python3 --version
```

If Terminal prints `Python 3.x.x`, continue to the first-run instructions below. Wolffe TV uses only Python's standard library, so no extra Python packages are required.

If Terminal reports `command not found`, asks you to install developer tools, or the launcher immediately closes with a Python error:

1. Visit the official [Python releases for macOS](https://www.python.org/downloads/macos/) page.
2. Download a current stable macOS installer. Python.org provides universal installers that support Apple Silicon and Intel Macs.
3. Open the downloaded `.pkg` file and complete the standard macOS installation.
4. Close and reopen Terminal.
5. Confirm the installation:

```bash
python3 --version
```

6. When a Python 3 version is displayed, continue with Wolffe TV setup.

Do not delete or alter any Python components managed by Apple. Installing Python from python.org can coexist with Apple's own system or developer-tool Python.

## First run on macOS

1. Download and unzip `wolffe-tv-v3.zip`.
2. Open the `wolffe-tv-v3` folder.
3. Double-click `run.command`.
4. Enter the Roku TV's local IPv4 address.
5. Enter a friendly TV name, such as `Living Room TV`.
6. Setup creates a private `config.json` and starts the server.
7. Open `http://localhost:8787` on the Mac.

If macOS blocks the launcher, open Terminal in the project folder and run:

```bash
chmod +x run.command
./run.command
```

Later launches reuse `config.json` and skip setup.

## Reset setup from the dashboard

1. Open `TV Settings`.
2. Expand `Advanced` at the bottom.
3. Select `Reset Setup`.
4. Confirm the warning.
5. Return to the Terminal window and enter the new IP address and TV name.

Reset Setup deletes only `config.json`. It does not reset, unlink, modify, or factory-reset the Roku TV.

## Open the dashboard from an iPhone or iPad

The device must be able to reach the Mac on the local network. On the Mac, run:

```bash
ipconfig getifaddr en0
```

If that returns `10.1.0.50`, for example, open `http://10.1.0.50:8787` on the other device.

## GitHub and distribution safety

- `config.json` is excluded by `.gitignore` and is not included in the release ZIP.
- `config.example.json` contains placeholders only and is safe to publish.
- The repository must not contain Roku serial numbers, device IDs, advertising IDs, MAC addresses, passwords, or private network details.
- Run `git status` before every push and verify that `config.json` is not staged.

## Stop the server

Return to Terminal and press Control+C.

## Security notes

- The server accepts only a fixed allowlist of Roku key commands.
- The setup-reset endpoint is available only through the local dashboard server, but the server does not provide authentication.
- Do not expose port 8787 or Roku ECP port 8060 to the public Internet.
- Use this only on a trusted home LAN.
