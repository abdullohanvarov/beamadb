# BeamADB ⚡📱

> **Fast, accessible Android Wireless Debugging and QR Pairing Bridge for Linux.**

BeamADB lets developers pair, connect, and debug Android devices over Wi-Fi without needing Android Studio or struggling with dynamic IP addresses, ports, and typing long pairing codes.

Works both as a **modern accessible Web GUI** and a **lightning-fast Terminal CLI**.

![BeamADB Icon](static/icon.svg)

---

## ✨ Features

- **📷 QR Code Pairing (Android 11+ AOSP)**:
  - Generates a scannable QR code matching Android's Wireless Debugging schema (`WIFI:T:ADB;S:...;P:...;;`).
  - **Works in Web GUI** with glowing radar animations.
  - **Works directly in Terminal** with crisp Unicode half-block characters!
  - Automatically listens for phone broadcast over Wi-Fi, completes TLS security exchange (`adb pair`), discovers connection port, and connects (`adb connect`).
- **🔢 6-Digit Code Pairing**:
  - Full manual pairing with IP, pairing port, and 6-digit code.
  - 1-click auto-fill from discovered local network endpoints.
- **🌐 Local Network mDNS Auto-Discovery**:
  - Automatically scans and displays all local Android devices advertising ADB on your Wi-Fi network.
- **🔌 1-Click USB to Wireless Migration**:
  - Phone plugged in via USB? Run `beamadb usb` or click "Switch to Wireless" to enable `tcpip 5555`, fetch the phone's Wi-Fi IP address, connect, and unplug the cable.
- **📱 Active Device Management**:
  - Live inspection: Device model, Android OS version, battery percentage, Wi-Fi IP, and status.
  - **Live Screenshot Preview**: Capture and download instant screenshots directly from the UI.
  - **Interactive Shell Drawer**: Run shell commands directly from the UI or terminal.
  - **1-Click ADB Server Restart**: Recover quickly from stale ADB states.
- **♿ Accessible by Design**:
  - Full keyboard shortcuts (`Alt+1` QR tab, `Alt+2` Manual tab, `Alt+3` Discovered tab, `Alt+R` Refresh, `Alt+S` Restart ADB).
  - High contrast colors, dark glassmorphism styling, screen reader announcements (`aria-live`), and auditory feedback tones.

---

## 🚀 Installation

### Option 1: Install Debian (.deb) Package (Ubuntu / Debian / Mint)
Download or build the `.deb` package and install with:
```bash
sudo dpkg -i dist/beamadb_1.0.0_all.deb
# or
sudo apt install ./dist/beamadb_1.0.0_all.deb
```
This automatically installs:
- The `beamadb` CLI command in `/usr/bin/beamadb`
- The desktop shortcut in your application launcher menu
- High-resolution SVG app icon

### Option 2: Run Directly from Repository
```bash
git clone https://github.com/abdullohanvarov/beamadb.git
cd beamadb
chmod +x beamadb
./beamadb
```

---

## 💻 Terminal CLI Usage

BeamADB is designed to work seamlessly from your command line:

```bash
# Launch Graphical Web UI in your default browser
beamadb

# Terminal QR Pairing Mode (renders QR code directly in your terminal!)
beamadb pair
# or
beamadb qr

# Manual 6-digit code pairing
beamadb code 192.168.1.50:37125 849201 [connect_port]

# Connect to an already-paired device (or default port 5555)
beamadb connect 192.168.1.50:41235

# List currently connected USB and Wi-Fi devices
beamadb devices

# Scan and list local Wi-Fi mDNS ADB pairing and connect services
beamadb discovered

# Switch connected USB device to wireless in 1 click
beamadb usb

# Disconnect a specific wireless device or all devices
beamadb disconnect 192.168.1.50:41235
beamadb disconnect all

# Check status of ADB daemon and BeamADB server
beamadb status

# Restart ADB server daemon
beamadb restart

# Show help
beamadb help
```

---

## 📱 How to Pair Your Android Phone with QR Code

1. Connect your Android phone to the **same Wi-Fi network** as your computer (or connect your computer to your phone's Wi-Fi hotspot).
2. On your phone, open **Settings** &rarr; **Developer options** &rarr; toggle on **Wireless debugging**.
   *(If Developer options is not enabled: Go to **Settings** &rarr; **About phone** &rarr; tap **Build number** 7 times).*
3. Tap on **Wireless debugging** &rarr; tap **"Pair device with QR code"**.
4. Point your phone camera at the QR code on your screen (either in the **Web GUI** or directly in your **Terminal** with `beamadb pair`).
5. BeamADB detects your device, completes the TLS handshake, and connects wirelessly!

---

## 📦 Building the Debian Package

To compile the `.deb` installer:
```bash
./build-deb.sh
```
The output `.deb` installer will be generated in `dist/beamadb_1.0.0_all.deb`.

---

## 📄 License

MIT License. Free and open source for all developers.
