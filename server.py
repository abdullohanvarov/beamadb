#!/usr/bin/env python3
"""
Wireless ADB Manager - High Performance, Zero-Dependency Server
Supports:
  - QR Code Wireless Pairing (Android 11+ / AOSP adb-tls-pairing protocol)
  - 6-digit Code Manual Pairing
  - Direct IP:Port Wireless Connection
  - 1-Click USB-to-Wireless Migration (adb tcpip 5555)
  - Real-time mDNS device discovery & state tracking
  - Live Server-Sent Events (SSE) updates
  - Live Screenshot & Shell command execution
"""

import sys
import os
import json
import time
import uuid
import random
import re
import socket
import struct
import select
import threading
import subprocess
from pathlib import Path
from http.server import HTTPServer, SimpleHTTPRequestHandler
from socketserver import ThreadingMixIn
from urllib.parse import urlparse, parse_qs

# Configuration
PORT = int(os.environ.get("PORT", 5588))
HOST = "0.0.0.0"
STATIC_DIR = Path(__file__).parent / "static"

# Find ADB binary
def find_adb():
    candidates = [
        os.environ.get("ADB_PATH"),
        "/home/abdulloh/.local/bin/adb",
        "/home/abdulloh/Android/Sdk/platform-tools/adb",
        "adb"
    ]
    for c in candidates:
        if not c:
            continue
        try:
            res = subprocess.run([c, "version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=2)
            if res.returncode == 0:
                return c
        except Exception:
            continue
    return "adb"

ADB_BIN = find_adb()

class State:
    def __init__(self):
        self.lock = threading.Lock()
        self.qr_session = None  # { "session_id", "service_name", "pairing_code", "created_at", "status", "message", "device" }
        self.sse_clients = []
        self.discovered_services = []
        self.connected_devices = []
        self.logs = []

    def broadcast(self, event_type, data):
        msg = f"event: {event_type}\ndata: {json.dumps(data)}\n\n"
        with self.lock:
            dead_clients = []
            for client_q in self.sse_clients:
                try:
                    client_q.put_nowait(msg)
                except Exception:
                    dead_clients.append(client_q)
            for c in dead_clients:
                if c in self.sse_clients:
                    self.sse_clients.remove(c)

    def log(self, text):
        entry = {"time": time.strftime("%H:%M:%S"), "text": text}
        print(f"[{entry['time']}] {text}")
        with self.lock:
            self.logs.append(entry)
            if len(self.logs) > 100:
                self.logs.pop(0)
        self.broadcast("log", entry)

state = State()

def run_adb(args, timeout=10, check=False):
    """Executes an adb command safely with timeout"""
    cmd = [ADB_BIN] + [str(a) for a in args]
    try:
        res = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout
        )
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except subprocess.TimeoutExpired:
        return -1, "", "Command timed out"
    except Exception as e:
        return -1, "", str(e)

def get_devices():
    """Parses adb devices -l and enriches with model, IP, battery, version"""
    code, out, _ = run_adb(["devices", "-l"], timeout=4)
    devices = []
    if code != 0:
        return devices

    lines = out.splitlines()[1:]
    for line in lines:
        line = line.strip()
        if not line:
            continue
        parts = re.split(r'\s+', line)
        serial = parts[0]
        status = parts[1] if len(parts) > 1 else "unknown"

        meta = {}
        for p in parts[2:]:
            if ":" in p:
                k, v = p.split(":", 1)
                meta[k] = v

        is_wireless = bool(re.match(r'^\d+\.\d+\.\d+\.\d+:\d+$', serial))

        # Query extra properties in background or short timeout
        model = meta.get("model", "")
        brand = ""
        battery = ""
        version = ""
        ip_addr = ""

        if status == "device":
            if not model:
                _, m, _ = run_adb(["-s", serial, "shell", "getprop", "ro.product.model"], timeout=2)
                model = m or serial
            _, b, _ = run_adb(["-s", serial, "shell", "getprop", "ro.product.brand"], timeout=2)
            brand = b
            _, v, _ = run_adb(["-s", serial, "shell", "getprop", "ro.build.version.release"], timeout=2)
            version = v

            # Battery level
            _, bat, _ = run_adb(["-s", serial, "shell", "dumpsys battery"], timeout=2)
            m = re.search(r'level:\s*(\d+)', bat)
            if m:
                battery = m.group(1)

            # Wi-Fi IP address
            if is_wireless:
                ip_addr = serial.split(":")[0]
            else:
                _, ip_out, _ = run_adb(["-s", serial, "shell", "ip -4 route show"], timeout=2)
                m = re.search(r'dev\s+wlan0\s+proto\s+\w+\s+scope\s+\w+\s+src\s+([\d\.]+)', ip_out)
                if m:
                    ip_addr = m.group(1)
                else:
                    _, ip_out2, _ = run_adb(["-s", serial, "shell", "ip -4 addr show wlan0"], timeout=2)
                    m2 = re.search(r'inet\s+([\d\.]+)/', ip_out2)
                    if m2:
                        ip_addr = m2.group(1)

        devices.append({
            "serial": serial,
            "status": status,
            "is_wireless": is_wireless,
            "model": model or serial,
            "brand": brand,
            "battery": battery,
            "version": version,
            "ip": ip_addr,
            "product": meta.get("product", ""),
            "device": meta.get("device", ""),
        })
    return devices

def get_mdns_services():
    """Parses adb mdns services output"""
    code, out, _ = run_adb(["mdns", "services"], timeout=3)
    services = []
    if code != 0:
        return services

    for line in out.splitlines():
        line = line.strip()
        parts = re.split(r'\s+', line)
        if len(parts) >= 3 and ("_tcp" in parts[1] or "_adb" in parts[1]):
            svc_name = parts[0]
            svc_type = parts[1]
            svc_addr = parts[2]
            host, port = svc_addr.split(":", 1) if ":" in svc_addr else (svc_addr, "")
            services.append({
                "name": svc_name,
                "type": svc_type,
                "address": svc_addr,
                "host": host,
                "port": port
            })
    return services

# Background discovery loop & automated QR pairing handler
def discovery_worker():
    state.log("mDNS discovery worker started")
    last_discovered = []
    last_devices = []

    while True:
        try:
            # 1. Check discovered services
            services = get_mdns_services()
            if services != last_discovered:
                last_discovered = services
                with state.lock:
                    state.discovered_services = services
                state.broadcast("discovered", services)

            # 2. Check connected devices
            devices = get_devices()
            if devices != last_devices:
                last_devices = devices
                with state.lock:
                    state.connected_devices = devices
                state.broadcast("devices", devices)

            # 3. Check active QR session
            with state.lock:
                session = state.qr_session

            if session and session.get("status") in ("waiting", "detected"):
                target_service_name = session["service_name"]
                pairing_code = session["pairing_code"]

                # Find any matching pairing service or newly appeared pairing service
                matching_pairing_svc = None
                for svc in services:
                    if svc["type"] == "_adb-tls-pairing._tcp":
                        # Check name match or session freshness
                        if target_service_name in svc["name"] or session.get("status") == "waiting":
                            matching_pairing_svc = svc
                            break

                if matching_pairing_svc and session.get("status") == "waiting":
                    target_host = matching_pairing_svc["host"]
                    target_port = matching_pairing_svc["port"]
                    session["status"] = "detected"
                    session["message"] = f"Phone scanned QR! Pairing with {target_host}:{target_port}..."
                    state.log(f"Phone detected for QR session at {target_host}:{target_port}")
                    state.broadcast("qr_status", session)

                    # Trigger pairing in separate thread to prevent blocking worker
                    threading.Thread(
                        target=do_pair_and_connect,
                        args=(session, target_host, target_port, pairing_code),
                        daemon=True
                    ).start()

        except Exception as e:
            # Prevent crashes
            pass

        time.sleep(1.2)

def do_pair_and_connect(session, host, port, code):
    """Executes adb pair and subsequent adb connect"""
    pair_target = f"{host}:{port}"
    state.log(f"Executing adb pair {pair_target} {code}...")
    p_code, p_out, p_err = run_adb(["pair", pair_target, code], timeout=15)
    full_output = f"{p_out}\n{p_err}".strip()

    if "Successfully paired" in full_output or p_code == 0:
        state.log(f"Pairing succeeded: {full_output}")
        session["status"] = "paired"
        session["message"] = f"Successfully paired! Connecting to device..."
        state.broadcast("qr_status", session)

        # Allow time for phone to spin up _adb-tls-connect port
        connected = False
        time.sleep(1.0)

        # Look for connect service for this host
        for _ in range(8):
            svcs = get_mdns_services()
            for s in svcs:
                if s["type"] == "_adb-tls-connect._tcp" and s["host"] == host:
                    connect_target = f"{host}:{s['port']}"
                    state.log(f"Found TLS connect service at {connect_target}. Connecting...")
                    c_code, c_out, c_err = run_adb(["connect", connect_target], timeout=10)
                    if "connected to" in c_out.lower() or c_code == 0:
                        connected = True
                        session["status"] = "connected"
                        session["device"] = connect_target
                        session["message"] = f"Successfully connected to {connect_target}! 🎉"
                        state.log(f"Connected to {connect_target}")
                        state.broadcast("qr_status", session)
                        break
            if connected:
                break
            time.sleep(1.0)

        if not connected:
            # Check if adb auto-connected
            devs = get_devices()
            for d in devs:
                if d["is_wireless"] and host in d["serial"]:
                    session["status"] = "connected"
                    session["device"] = d["serial"]
                    session["message"] = f"Auto-connected to {d['serial']}! 🎉"
                    state.log(f"Device already connected: {d['serial']}")
                    state.broadcast("qr_status", session)
                    connected = True
                    break

        if not connected:
            session["status"] = "paired"
            session["message"] = f"Paired! Waiting for device connection port (check device IP & port in Wireless Debugging settings)."
            state.broadcast("qr_status", session)

    else:
        state.log(f"Pairing failed for {pair_target}: {full_output}")
        session["status"] = "error"
        session["message"] = f"Pairing failed: {full_output or 'Unknown error'}"
        state.broadcast("qr_status", session)


# Threaded HTTP Request Handler
class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True

class RequestHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(STATIC_DIR), **kwargs)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/":
            self.path = "/index.html"
            return super().do_GET()

        elif path.startswith("/static/"):
            self.path = path[len("/static"):]
            return super().do_GET()

        elif path == "/api/status":
            self.send_json_response(200, {
                "ok": True,
                "adb": ADB_BIN,
                "time": time.time()
            })

        elif path == "/api/devices":
            self.send_json_response(200, {
                "devices": state.connected_devices or get_devices()
            })

        elif path == "/api/discovered":
            self.send_json_response(200, {
                "services": state.discovered_services or get_mdns_services()
            })

        elif path == "/api/qr_session":
            with state.lock:
                session = state.qr_session
            self.send_json_response(200, session or {})

        elif path == "/api/logs":
            with state.lock:
                logs = list(state.logs)
            self.send_json_response(200, {"logs": logs})

        elif path == "/api/screenshot":
            qs = parse_qs(parsed.query)
            device = qs.get("device", [""])[0]
            if not device:
                self.send_json_response(400, {"error": "Missing device parameter"})
                return

            cmd = [ADB_BIN, "-s", device, "exec-out", "screencap", "-p"]
            try:
                proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8)
                if proc.returncode == 0 and len(proc.stdout) > 0:
                    self.send_response(200)
                    self.send_header("Content-Type", "image/png")
                    self.send_header("Content-Length", str(len(proc.stdout)))
                    self.send_header("Cache-Control", "no-cache")
                    self.end_headers()
                    self.wfile.write(proc.stdout)
                else:
                    self.send_json_response(500, {"error": "Screencap failed", "details": proc.stderr.decode(errors="ignore")})
            except Exception as e:
                self.send_json_response(500, {"error": str(e)})

        elif path == "/api/events":
            # Server-Sent Events (SSE) Stream
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()

            import queue
            client_q = queue.Queue(maxsize=50)
            with state.lock:
                state.sse_clients.append(client_q)

            # Send initial state
            try:
                init_msg = f"event: init\ndata: {json.dumps({'devices': state.connected_devices, 'discovered': state.discovered_services, 'qr': state.qr_session})}\n\n"
                self.wfile.write(init_msg.encode("utf-8"))
                self.wfile.flush()

                while True:
                    try:
                        msg = client_q.get(timeout=20)
                        self.wfile.write(msg.encode("utf-8"))
                        self.wfile.flush()
                    except queue.Empty:
                        # Keep-alive heartbeat
                        self.wfile.write(b": heartbeat\n\n")
                        self.wfile.flush()
            except (ConnectionResetError, BrokenPipeError):
                pass
            finally:
                with state.lock:
                    if client_q in state.sse_clients:
                        state.sse_clients.remove(client_q)

        else:
            return super().do_GET()

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        body = self.read_json_body()

        if path == "/api/qr_session":
            # Generate new QR code session
            session_id = uuid.uuid4().hex[:6]
            service_name = f"ADB-WIFI-{session_id.upper()}"
            pairing_code = f"{random.randint(100000, 999999)}"
            qr_payload = f"WIFI:T:ADB;S:{service_name};P:{pairing_code};;"

            session = {
                "session_id": session_id,
                "service_name": service_name,
                "pairing_code": pairing_code,
                "qr_payload": qr_payload,
                "created_at": time.time(),
                "status": "waiting",
                "message": "Ready. Scan this QR code with your phone.",
                "device": None
            }
            with state.lock:
                state.qr_session = session
            state.log(f"Generated new QR pairing session: {service_name} (Code: {pairing_code})")
            state.broadcast("qr_status", session)
            self.send_json_response(200, session)

        elif path == "/api/pair_manual":
            host = (body.get("host") or "").strip()
            port = (body.get("port") or "").strip()
            code = (body.get("code") or "").strip()
            connect_port = (body.get("connect_port") or "").strip()

            if not host or not port or not code:
                self.send_json_response(400, {"error": "Host, port, and pairing code are required."})
                return

            target = f"{host}:{port}"
            state.log(f"Manual pairing request for {target} with code {code}...")
            c_code, c_out, c_err = run_adb(["pair", target, code], timeout=15)
            full_out = f"{c_out}\n{c_err}".strip()

            if "Successfully paired" in full_out or c_code == 0:
                state.log(f"Manual pairing successful for {target}")
                connect_result = ""
                connected_dev = ""

                # Connect if connect_port provided
                if connect_port:
                    conn_target = f"{host}:{connect_port}"
                    time.sleep(0.5)
                    state.log(f"Connecting to {conn_target}...")
                    _, conn_out, conn_err = run_adb(["connect", conn_target], timeout=8)
                    connect_result = f"{conn_out}\n{conn_err}".strip()
                    connected_dev = conn_target

                self.send_json_response(200, {
                    "ok": True,
                    "message": "Successfully paired!",
                    "output": full_out,
                    "connect_result": connect_result,
                    "device": connected_dev
                })
            else:
                state.log(f"Manual pairing failed: {full_out}")
                self.send_json_response(400, {
                    "ok": False,
                    "error": full_out or "Pairing failed. Ensure IP, port, and code match your phone screen."
                })

        elif path == "/api/connect":
            host = (body.get("host") or "").strip()
            port = (body.get("port") or "").strip()
            if not host:
                self.send_json_response(400, {"error": "Host is required."})
                return
            if not port:
                port = "5555"

            target = f"{host}:{port}"
            state.log(f"Connecting to {target}...")
            c_code, c_out, c_err = run_adb(["connect", target], timeout=10)
            full_out = f"{c_out}\n{c_err}".strip()

            if "connected to" in full_out.lower() or c_code == 0:
                state.log(f"Connected to {target}")
                self.send_json_response(200, {"ok": True, "target": target, "message": full_out})
            else:
                self.send_json_response(400, {"ok": False, "error": full_out or "Connection failed."})

        elif path == "/api/disconnect":
            device = (body.get("device") or "").strip()
            if not device:
                self.send_json_response(400, {"error": "Device is required."})
                return

            state.log(f"Disconnecting {device}...")
            _, out, err = run_adb(["disconnect", device], timeout=6)
            self.send_json_response(200, {"ok": True, "message": f"{out}\n{err}".strip()})

        elif path == "/api/disconnect_all":
            state.log("Disconnecting all devices...")
            _, out, err = run_adb(["disconnect"], timeout=6)
            self.send_json_response(200, {"ok": True, "message": f"{out}\n{err}".strip()})

        elif path == "/api/usb_to_wireless":
            serial = (body.get("serial") or "").strip()
            if not serial:
                self.send_json_response(400, {"error": "Serial is required."})
                return

            state.log(f"Enabling TCP/IP on USB device {serial}...")
            # 1. Enable tcpip 5555
            _, t_out, t_err = run_adb(["-s", serial, "tcpip", "5555"], timeout=8)
            time.sleep(1.0)

            # 2. Get device IP
            _, ip_out, _ = run_adb(["-s", serial, "shell", "ip -4 route show"], timeout=3)
            m = re.search(r'dev\s+wlan0\s+proto\s+\w+\s+scope\s+\w+\s+src\s+([\d\.]+)', ip_out)
            ip_addr = m.group(1) if m else None

            if not ip_addr:
                _, ip_out2, _ = run_adb(["-s", serial, "shell", "ip -4 addr show wlan0"], timeout=3)
                m2 = re.search(r'inet\s+([\d\.]+)/', ip_out2)
                ip_addr = m2.group(1) if m2 else None

            if not ip_addr:
                self.send_json_response(400, {
                    "error": "TCP/IP 5555 activated, but could not detect Wi-Fi IP address. Ensure phone is connected to Wi-Fi."
                })
                return

            # 3. Connect to ip:5555
            target = f"{ip_addr}:5555"
            state.log(f"Connecting wirelessly to {target}...")
            _, c_out, c_err = run_adb(["connect", target], timeout=8)
            self.send_json_response(200, {
                "ok": True,
                "ip": ip_addr,
                "target": target,
                "message": f"Switched to wireless! You can now unplug the USB cable. Output: {c_out}"
            })

        elif path == "/api/shell":
            device = (body.get("device") or "").strip()
            cmd_text = (body.get("command") or "").strip()
            if not device or not cmd_text:
                self.send_json_response(400, {"error": "Device and command are required."})
                return

            c_code, c_out, c_err = run_adb(["-s", device, "shell", cmd_text], timeout=15)
            self.send_json_response(200, {
                "code": c_code,
                "output": c_out,
                "error": c_err
            })

        elif path == "/api/restart_adb":
            state.log("Restarting ADB Server...")
            run_adb(["kill-server"], timeout=5)
            time.sleep(0.5)
            c, out, err = run_adb(["start-server"], timeout=8)
            state.log("ADB Server restarted.")
            self.send_json_response(200, {"ok": True, "message": "ADB Server restarted."})

        else:
            self.send_json_response(404, {"error": "Not Found"})

    def read_json_body(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
            if length > 0:
                return json.loads(self.rfile.read(length).decode("utf-8"))
        except Exception:
            pass
        return {}

    def send_json_response(self, status_code, data):
        payload = json.dumps(data).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format, *args):
        # Quiet standard HTTP request logging
        return

def main():
    print(f"=== Wireless ADB Manager ===")
    print(f"ADB Binary: {ADB_BIN}")
    
    # Start ADB server initially
    run_adb(["start-server"])

    # Launch background mDNS and discovery worker
    threading.Thread(target=discovery_worker, daemon=True).start()

    server = ThreadedHTTPServer((HOST, PORT), RequestHandler)
    url = f"http://localhost:{PORT}"
    print(f"Server running at: {url}")
    print(f"Opening browser...")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        server.server_close()

if __name__ == "__main__":
    main()
