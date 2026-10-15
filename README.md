# BeamADB ⚡📱

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.kernel.org)
[![Python: 3.8+](https://img.shields.io/badge/Python-3.8+-brightgreen.svg)](https://www.python.org)
[![Android: 11+](https://img.shields.io/badge/Android-11+%20(Wireless%20Debugging)-orange.svg)](https://developer.android.com/tools/adb#wireless)
[![Zero Dependency](https://img.shields.io/badge/Dependencies-Zero%20pip%2Fnpm-success.svg)](https://github.com/abdullohanvarov/beamadb)

> **Fast, accessible Android Wireless Debugging & QR Pairing Bridge for Linux.**

BeamADB lets developers pair, connect, and debug Android devices over Wi-Fi without needing Android Studio or struggling with dynamic IP addresses, randomized pairing ports, and cumbersome typing.

Works seamlessly both as an **accessible modern Web GUI** and as an **instant, zero-dependency Terminal CLI**.

<p align="center">
  <img src="static/icon.svg" alt="BeamADB Logo" width="128" height="128">
</p>

---

## ✨ Highlights & Features

- **📷 QR Code Pairing (Android 11+ AOSP)**:
  - Generates a real-time scannable QR code matching Android's Wireless Debugging schema (`WIFI:T:ADB;S:...;P:...;;`).
  - **In Web GUI**: Animated QR display with radar scan-line and auto-detecting connection loop.
  - **Directly in Terminal**: Crisp UTF-8 half-block QR rendered right inside your shell (`beamadb pair`).
  - Automatically listens for phone broadcast over Wi-Fi, completes TLS security exchange (`adb pair`), discovers the connection port, and connects (`adb connect`).
- **🔢 6-Digit Code Pairing**:
  - Full manual pairing with IP, pairing port, and 6-digit code.
  - 1-click auto-fill from discovered local network endpoints.
- **🌐 Local Network mDNS Auto-Discovery**:
  - Automatically queries local network for `_adb-tls-pairing._tcp` and `_adb-tls-connect._tcp` services.
  - Shows phone model name and advertised pairing/connect ports in real time.
- **📱 Real-time Screen & Camera Mirroring (Scrcpy)**:
  - 1-Click native screen mirroring with full mouse and keyboard control.
  - **Live Camera Mirroring**: Stream your phone's camera (front, back, or external) directly as a high-speed video monitor (Android 12+).
  - Configurable options: Stay awake, turn device display off while mirroring, mute audio, and selectable frame rate (FPS).
- **📁 Full Device File Explorer**:
  - Browse, navigate, and manage device storage (`/sdcard`, `Downloads`, `DCIM`, `Documents`, etc.) with interactive breadcrumbs.
  - **Upload Files & Folders**: Single/multi-file upload, whole directory upload, and seamless drag-and-drop right onto the explorer table.
  - **Download Files & Folders**: 1-click file download or automatic zipped directory download.
  - **File Operations**: Create new directories, delete files/folders permanently, and rename files.
  - **Real-time Search**: Instant client-side filtering by name.
  - **Storage Gauge**: Live indicator showing total, used, and free storage space.
- **🔌 1-Click USB to Wireless Migration**:
  - Phone plugged in via USB? Run `beamadb usb` or click **"Switch to Wireless"** to enable `tcpip 5555`, fetch the phone's Wi-Fi IP address, connect wirelessly, and safely unplug the cable.
- **📱 Active Device Management**:
  - Live inspection: Device model, Android OS version, battery percentage, Wi-Fi IP, and connection state.
  - **Live Screenshot Preview**: Capture and download instant device screenshots directly from the UI.
  - **Interactive Shell Drawer**: Run shell commands directly from the UI or terminal.
  - **1-Click ADB Server Restart**: Recover quickly from stale ADB states.
- **♿ Accessible by Design**:
  - Keyboard navigation shortcuts (`Alt+1` QR tab, `Alt+2` Manual tab, `Alt+3` Discovered tab, `Alt+R` Refresh, `Alt+S` Restart ADB).
  - High contrast colors, dark glassmorphism styling, screen reader announcements (`aria-live`), and auditory feedback tones.
- **🪶 Zero Heavy Dependencies**:
  - Standalone Python 3 daemon using standard libraries (`http.server`, `subprocess`, `ssl`, `socket`).
  - Embedded lightweight pure-Python QR generator with zero pip or npm requirements.

---

## 📋 Prerequisites

Before using BeamADB, ensure you have the Android Platform Tools (`adb`) installed on your Linux machine:

### Ubuntu / Debian / Linux Mint
```bash
sudo apt update
sudo apt install -y android-tools-adb avahi-utils
```

### Fedora / RHEL
```bash
sudo dnf install -y android-tools avahi-tools
```

### Arch Linux / Manjaro
```bash
sudo pacman -S android-tools avahi
```

---

## 🚀 Installation

### Option 1: Install Debian (.deb) Package (Recommended for Ubuntu/Debian/Mint)

Download or build the `.deb` package and install it with:
```bash
sudo apt install ./dist/beamadb_1.0.0_all.deb
# or
sudo dpkg -i dist/beamadb_1.0.0_all.deb
```

This installs:
- The `beamadb` CLI command in `/usr/bin/beamadb`
- The desktop shortcut in your application launcher menu
- High-resolution SVG application icon

To uninstall:
```bash
sudo apt remove beamadb
```

### Option 2: Run Directly from Source

```bash
# Clone the repository
git clone https://github.com/abdullohanvarov/beamadb.git
cd beamadb

# Make executable and launch
chmod +x beamadb
./beamadb
```

---

## 💻 Terminal CLI Usage

BeamADB includes a comprehensive CLI that works in headless environments or developer terminals:

| Command | Description |
| :--- | :--- |
| `beamadb` | Launch the Graphical Web UI in your default browser |
| `beamadb pair` *(or `beamadb qr`)* | Render QR code in terminal and wait for phone scan |
| `beamadb code <ip:port> <code> [connect_port]` | Pair device manually using 6-digit code |
| `beamadb connect <ip:port>` | Connect to an already paired device (e.g. `192.168.1.50:5555`) |
| `beamadb devices` | List currently connected USB and Wi-Fi devices with details |
| `beamadb discovered` | Scan and display local Wi-Fi mDNS ADB pairing and connect services |
| `beamadb usb` | Switch a connected USB device to wireless mode (port 5555) |
| `beamadb scrcpy [device]` | Launch native Scrcpy screen mirroring |
| `beamadb camera [device]` | Launch native Scrcpy camera mirroring (Android 12+) |
| `beamadb files [device] [path]` | Browse device filesystem from CLI |
| `beamadb pull <device> <remote> [local]` | Download file or folder from device |
| `beamadb push <device> <local> <remote>` | Upload file or folder to device |
| `beamadb rm <device> <remote>` | Delete file or folder on device |
| `beamadb disconnect <ip:port>` | Disconnect a specific wireless device |
| `beamadb disconnect all` | Disconnect all connected wireless devices |
| `beamadb restart` | Kill and restart the local ADB server daemon |
| `beamadb status` | Check status of ADB daemon and BeamADB server |
| `beamadb help` | Show usage options and flags |

---

## 📱 How to Pair Your Android Phone with QR Code

1. Connect your Android phone to the **same Wi-Fi network** as your computer (or connect your computer to your phone's Wi-Fi hotspot).
2. On your phone, open **Settings** &rarr; **Developer options** &rarr; toggle on **Wireless debugging**.  
   *(If Developer options is not enabled: Go to **Settings** &rarr; **About phone** &rarr; tap **Build number** 7 times).*
3. Tap on **Wireless debugging** &rarr; tap **"Pair device with QR code"**.
4. Point your phone camera at the QR code on your screen:
   - In the **Web GUI**: Open `beamadb` and look at the "Scan QR Code" tab.
   - In the **Terminal**: Run `beamadb pair` or `beamadb qr`.
5. BeamADB detects your device, completes the TLS handshake, discovers the active port, and connects wirelessly!

---

## ⌨️ Web UI Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Alt + 1` | Switch to **QR Code Pairing** tab |
| `Alt + 2` | Switch to **Manual 6-Digit Code** tab |
| `Alt + 3` | Switch to **Discovered Network Devices** tab |
| `Alt + R` | Refresh connected devices and trigger network rescan |
| `Alt + S` | Restart local ADB server daemon |

---

## 📦 Building the Debian Package

To compile the `.deb` installer locally:

```bash
chmod +x build-deb.sh
./build-deb.sh
```

The resulting package is output to `dist/beamadb_1.0.0_all.deb`.

---

## 🔍 Troubleshooting

- **QR Code scan doesn't trigger connection**:
  - Ensure your computer and Android device are on the **exact same Wi-Fi subnet**.
  - Some public/corporate Wi-Fi networks enable **Client Isolation** (AP Isolation), which blocks devices from communicating with each other. If this is the case, connect your laptop to your phone's **Wi-Fi Hotspot** or use a private home router.
- **Port changes after phone reconnects**:
  - Android rotates wireless debugging ports whenever Wi-Fi reconnects. Use `beamadb discovered` to see the new port or run `beamadb connect <ip:new_port>`.
- **ADB server in bad state**:
  - Run `beamadb restart` or click the "Restart ADB Server" button in the Web GUI to reset ADB.

---

## 📄 License

Distributed under the [MIT License](LICENSE). See [LICENSE](LICENSE) for more details.

---

## 👤 Author

Developed by **[Abdulloh Anvarov](https://github.com/abdullohanvarov)**.
Contributions, bug reports, and pull requests are welcome!
