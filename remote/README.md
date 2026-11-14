# BeamADB internet connection

The desktop app automatically sets up phones connected through **authorized local ADB** while the app is open. It installs the bundled companion, grants Wi-Fi recovery permission, transfers the invitation directly through a shell-protected Android content provider, and starts a separate systemd user agent for each phone. No invitation file needs to be selected or left in Downloads. Android's USB-debugging and vendor installation approvals still require the phone owner. HyperOS may also require Background autostart to be enabled manually.

## Initial relay setup

Run `bash remote/deploy.sh ~/oracle/sshkey.key ubuntu@130.61.119.34` from Ubuntu. Verify the SSH host fingerprint if unknown. The deployment uses only the SSH user's BeamADB directory and service and stops if another project owns TCP 45883. Allow stateful inbound TCP destination 45883 in the Oracle network rules and host firewall. Preserve other rules and services. Enable lingering for the VPS account to keep the service running after logout and reboot.

In **Connect device → Remote**, configure the Ubuntu agent once using the downloaded desktop.json and phone.json. After that, new authorized phones are set up automatically. **Settings → Set up connected phones automatically** controls automatic onboarding. **Set up selected phone** retries a blocked setup; **Open companion settings on phone** opens the Android management screen. The companion has no launcher icon. It retains Android's required foreground-service indicator with a quiet fixed message rather than repeated connection-status messages.

## Multiple phones and security

Each newly configured phone receives a separate random relay channel, inner-TLS proof, local loopback ADB port starting at 45900, and systemd user unit. The relay supports up to 256 channels and preserves the original unchannelled protocol for existing installations. Channel-isolation tests verify simultaneous streams do not cross. A real single phone has been tested; simultaneous physical multi-phone validation still requires another phone.

Private configurations live under `~/.config/beamadb-link/phones/` with mode-600 credential files and mode-700 device directories. Credentials travel on stdin to Android's shell-protected provisioning provider, never in command-line arguments or logs. The provider requires Android's platform DUMP permission, which ordinary apps cannot obtain. The relay verifies role tokens over pinned TLS. Inside it, the phone verifies the desktop certificate and proves its invitation secret before forwarding ADB. Android ADB key authorization remains required.

## Cellular handover

**Enable cellular mode** permits authenticated ADB TCP on phone port 45885. Android binds this listener to phone network interfaces: devices on the same network can reach it, but require an authorized ADB key. The companion uses loopback and carries traffic inside the encrypted relay; no additional VPS ports are opened. A newly onboarded phone inherits the existing cellular-mode preference.

After phone reboot, unlock once and connect to trusted Wi-Fi to bootstrap Wireless debugging. New Wi-Fi networks may require Android's debugging approval. Cellular-only boot recovery remains unsupported. Handover reconnects ADB and can interrupt running commands or transfers; this is not a general-purpose VPN.

**Disable cellular mode** clears automatic TCP startup for all paired phones and requests that their listeners stop. If a phone is offline, reboot it after disabling, or connect it over USB and run `python3 remote/cellular.py disable --serial PHONE_SERIAL`. Unlinking the companion alone does not stop Android's TCP listener. Disable automatic onboarding before intentionally unlinking a phone that remains connected locally.

## Validation and maintenance

On 2026-11-14, an authenticated ADB shell command passed through the VPS on LTE with Wi-Fi and Wireless debugging disabled; handover took about 49 seconds. Wi-Fi recovery and the TCP off switch passed. Automatic provisioning of the updated companion was then verified without a file picker, using its own relay channel and local port 45900. The phone had no launcher activity, and real relay shell commands returned its identity and battery.

Desktop recordings save automatically to the system Videos/BeamADB folder (screen/camera) or Music/BeamADB folder (audio), respecting XDG media-directory settings. Names contain phone name, mode and local timestamp, with collision suffixes. Saving reports the resulting path.

Use `journalctl --user -u 'beamadb-link-phone-*'` for paired phone agents and `journalctl --user -u beamadb-link-relay` on the VPS. The legacy agent is `beamadb-link-agent`. Do not print credential files. Updating the VPS needs only a relay service restart; do not reboot it or restart web services. Build the debug-signed APK with `bash remote/android/build.sh`, then build/install the desktop with `bash tools/install-desktop-linux.sh`. Android SDK 35, build tools 35.0.0, a JDK, Flutter and the local signing key are required.

### Internet screen mirroring

Screen mirroring prefers the same phone's available relay transport so switching networks does not leave it tied to a Wi-Fi IP. Internet captures are limited to 1280 pixels, 30 fps and 2 Mbps to reduce cellular congestion. After a previously live mirror disconnects, the mirror window retries while the phone is reachable; stopping it cancels recovery. Recordings interrupted by a connection loss are not resumed automatically.

A live cellular mirror was tested with an injected ADB transport disconnection on 2026-11-14. The same window went through Disconnected/Starting and returned to Live automatically in approximately 18 seconds. This is a controlled recovery test, not a guarantee against poor cellular coverage or all carrier-network conditions.

### Desktop connection notifications and removal

The per-phone agent subscribes to an authenticated `WATCH` stream over pinned TLS. The VPS pushes ONLINE/OFFLINE transitions plus keepalives. Offline means no authenticated companion heartbeat for 35 seconds, not an instantaneous Wi-Fi loss. An unreachable VPS produces an unavailable state instead of a false phone-disconnected notification. Agents remember the last authoritative state to suppress duplicate alerts after restart. Ubuntu's `notify-send` delivers notifications while the desktop window is closed (the user session must be running). Settings → Device connection notifications controls these alerts. VPS presence confirms the companion is reachable; it does not by itself prove ADB is ready.

Each device card has **Remove phone**. The confirmation action attempts an identity-checked ADB uninstall of `dev.beamadb.link`, disables that phone's systemd agent, deletes its local relay credentials, and records a removal tombstone so automatic setup cannot reinstall it. Offline phones are removed from the roster immediately with uninstall pending. If remote uninstall severs the relay before confirmation, the result is explicitly unconfirmed. Connect the phone through authorized USB/local ADB with the desktop open to complete/verify uninstall. Settings shows removal results. Removal does not revoke the computer's Android ADB authorization or change unrelated phone apps.

Validation: seven Python tests cover relay authentication/channel isolation/push transitions and guarded/pending removal; desktop tests cover hidden removed devices and transport recovery. A dedicated temporary channel on the actual VPS produced exactly one connected and one disconnected notification accepted by Ubuntu's notification service; repeated heartbeats produced no duplicate. The user's actual phone was not uninstalled as a test.

### Local-first routing

Desktop operations and mirroring prefer USB, then a verified local-network ADB route, then the VPS relay. Relay presence stays connected as a backup. When mDNS is unavailable, the desktop can obtain a paired phone's WLAN address and existing ADB port over the relay, probe local reachability, and verify the Android serial before selecting it. Local wireless routes receive short identity/reachability checks so stale connections fall back to the relay. The desktop periodically checks for a returning local route; active mirrors restart their stream when switching transports, so handover can briefly interrupt video or recordings.

Validated on the Infinix with actual authenticated ADB commands: discovered local 10.30.15.15:45885, selected local over the relay, fell back to 127.0.0.1:45901 after disconnecting the local route, and preferred local again after reconnection. Being on Wi-Fi alone does not establish local reachability (guest/client-isolated networks can block it).
