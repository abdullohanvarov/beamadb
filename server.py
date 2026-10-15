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
import shutil
import tempfile
import shlex
import mimetypes
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

# Find Scrcpy binary
def find_scrcpy():
    return shutil.which("scrcpy")

SCRCPY_BIN = find_scrcpy()

def get_scrcpy_cameras(device):
    scrcpy = find_scrcpy()
    if not scrcpy:
        return []
    try:
        proc = subprocess.run([scrcpy, "--list-cameras", "-s", device], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=8)
        output = f"{proc.stdout}\n{proc.stderr}"
        cameras = []
        for line in output.splitlines():
            m = re.search(r'--camera-id=(\d+)\s*\((.+?)\)', line)
            if m:
                cameras.append({"id": m.group(1), "description": m.group(2).strip()})
        return cameras
    except Exception:
        return []

def get_storage_info(device, path="/sdcard"):
    try:
        _, out, _ = run_adb(["-s", device, "shell", f"df -h {shlex.quote(path)}"], timeout=5)
        lines = [l.strip() for l in out.splitlines() if l.strip()]
        if len(lines) >= 2:
            parts = lines[1].split()
            if len(parts) >= 5:
                return {
                    "size": parts[1],
                    "used": parts[2],
                    "avail": parts[3],
                    "percent": parts[4]
                }
    except Exception:
        pass
    return None

def parse_ls_listing(output, base_path):
    pattern = re.compile(
        r'^([d\-lcbsp][rwx\-sStT]{9})\s+'
        r'(?:\d+\s+)?'
        r'(?:\S+\s+){1,2}'
        r'(\d+)\s+'
        r'(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}|[A-Za-z]{3}\s+\d+\s+(?:\d{2}:\d{2}|\d{4}))\s+'
        r'(.+)$'
    )
    norm_base = base_path.rstrip('/') or '/'
    items = []
    for line in output.splitlines():
        line = line.strip()
        if not line or line.startswith('total '):
            continue
        m = pattern.match(line)
        if m:
            perms, size_str, date_str, name_part = m.groups()
            link_target = None
            if ' -> ' in name_part:
                name, link_target = name_part.split(' -> ', 1)
            else:
                name = name_part
            if name in ('.', '..'):
                continue
            is_dir = perms.startswith('d')
            is_symlink = perms.startswith('l')
            ext = name.rsplit('.', 1)[1].lower() if ('.' in name and not is_dir) else ''
            full_path = f"{norm_base}/{name}" if norm_base != '/' else f"/{name}"
            items.append({
                "name": name,
                "path": full_path,
                "is_dir": is_dir,
                "is_symlink": is_symlink,
                "link_target": link_target,
                "size": int(size_str),
                "date": date_str,
                "perms": perms,
                "ext": ext
            })
    items.sort(key=lambda x: (not x["is_dir"] and not x["is_symlink"], x["name"].lower()))
    return items

class State:
    def __init__(self):
        self.lock = threading.Lock()
        self.qr_session = None  # { "session_id", "service_name", "pairing_code", "created_at", "status", "message", "device" }
        self.sse_clients = []
        self.discovered_services = []
        self.connected_devices = []
        self.logs = []
        self.scrcpy_procs = {}

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

        elif path == "/api/scrcpy/status":
            qs = parse_qs(parsed.query)
            device = qs.get("device", [""])[0]
            with state.lock:
                proc = state.scrcpy_procs.get(device)
                is_running = proc is not None and proc.poll() is None
            self.send_json_response(200, {
                "installed": shutil.which("scrcpy") is not None,
                "running": is_running,
                "device": device
            })

        elif path == "/api/scrcpy/cameras":
            qs = parse_qs(parsed.query)
            device = qs.get("device", [""])[0]
            if not device:
                self.send_json_response(400, {"error": "Device is required"})
                return
            cams = get_scrcpy_cameras(device)
            self.send_json_response(200, {
                "device": device,
                "cameras": cams
            })

        elif path == "/api/files/list":
            qs = parse_qs(parsed.query)
            device = qs.get("device", [""])[0]
            dir_path = qs.get("path", ["/sdcard"])[0].strip() or "/sdcard"
            if not device:
                self.send_json_response(400, {"error": "Device is required"})
                return

            norm_path = dir_path.rstrip('/') or '/'
            # Compute parent path
            parent_path = str(Path(norm_path).parent) if norm_path != '/' else None
            if parent_path == norm_path:
                parent_path = None

            c_code, c_out, c_err = run_adb(["-s", device, "shell", f"ls -la {shlex.quote(norm_path)}/"], timeout=10)
            if c_code != 0 and not c_out.strip():
                c_code, c_out, c_err = run_adb(["-s", device, "shell", f"ls -la {shlex.quote(norm_path)}"], timeout=8)

            files = parse_ls_listing(c_out, norm_path)
            storage = get_storage_info(device, norm_path)

            self.send_json_response(200, {
                "ok": True,
                "device": device,
                "path": norm_path,
                "parent": parent_path,
                "files": files,
                "storage": storage
            })

        elif path == "/api/files/download":
            qs = parse_qs(parsed.query)
            device = qs.get("device", [""])[0]
            remote_path = qs.get("path", [""])[0].strip()
            is_dir = qs.get("is_dir", ["0"])[0] in ("1", "true")
            if not device or not remote_path:
                self.send_json_response(400, {"error": "Device and path are required"})
                return

            filename = os.path.basename(remote_path.rstrip('/')) or "download"

            if is_dir:
                # Directory download: pull and zip
                temp_dir = tempfile.mkdtemp(prefix="beamadb_dl_")
                try:
                    pulled_dir = os.path.join(temp_dir, filename)
                    p_code, _, p_err = run_adb(["-s", device, "pull", remote_path, pulled_dir], timeout=180)
                    zip_base = os.path.join(temp_dir, f"{filename}_archive")
                    zip_path = shutil.make_archive(zip_base, "zip", pulled_dir)
                    zip_size = os.path.getsize(zip_path)

                    self.send_response(200)
                    self.send_header("Content-Type", "application/zip")
                    self.send_header("Content-Disposition", f'attachment; filename="{filename}.zip"')
                    self.send_header("Content-Length", str(zip_size))
                    self.end_headers()

                    with open(zip_path, "rb") as f:
                        shutil.copyfileobj(f, self.wfile)
                except Exception as e:
                    self.send_json_response(500, {"error": f"Failed to download folder: {e}"})
                finally:
                    shutil.rmtree(temp_dir, ignore_errors=True)
                return
            else:
                # File download
                temp_file = tempfile.NamedTemporaryFile(delete=False, prefix="beamadb_dl_")
                temp_path = temp_file.name
                temp_file.close()
                try:
                    p_code, _, p_err = run_adb(["-s", device, "pull", remote_path, temp_path], timeout=90)
                    if p_code != 0 or not os.path.exists(temp_path):
                        self.send_json_response(500, {"error": f"ADB pull failed: {p_err}"})
                        return

                    file_size = os.path.getsize(temp_path)
                    mime_type, _ = mimetypes.guess_type(filename)
                    if not mime_type:
                        mime_type = "application/octet-stream"

                    self.send_response(200)
                    self.send_header("Content-Type", mime_type)
                    self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
                    self.send_header("Content-Length", str(file_size))
                    self.end_headers()

                    with open(temp_path, "rb") as f:
                        shutil.copyfileobj(f, self.wfile)
                except Exception as e:
                    self.send_json_response(500, {"error": f"Download failed: {e}"})
                finally:
                    if os.path.exists(temp_path):
                        os.unlink(temp_path)
                return

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

        if path == "/api/files/upload":
            qs = parse_qs(parsed.query)
            device = qs.get("device", [""])[0]
            dest_dir = qs.get("path", ["/sdcard"])[0].strip() or "/sdcard"
            filename = qs.get("filename", [""])[0].strip()

            if not device or not filename:
                self.send_json_response(400, {"error": "Missing device or filename parameter"})
                return

            content_length = int(self.headers.get("Content-Length", 0))
            if content_length <= 0:
                self.send_json_response(400, {"error": "Uploaded file is empty"})
                return

            temp_file = tempfile.NamedTemporaryFile(delete=False, prefix="beamadb_up_")
            temp_path = temp_file.name
            try:
                remaining = content_length
                chunk_size = 64 * 1024
                while remaining > 0:
                    read_bytes = self.rfile.read(min(remaining, chunk_size))
                    if not read_bytes:
                        break
                    temp_file.write(read_bytes)
                    remaining -= len(read_bytes)
                temp_file.flush()
                temp_file.close()

                # Ensure destination directory exists on phone
                run_adb(["-s", device, "shell", f"mkdir -p {shlex.quote(dest_dir)}"], timeout=5)

                remote_dest = f"{dest_dir.rstrip('/')}/{filename}"
                p_code, p_out, p_err = run_adb(["-s", device, "push", temp_path, remote_dest], timeout=180)
                if p_code == 0:
                    state.log(f"Uploaded {filename} to {device}:{remote_dest}")
                    self.send_json_response(200, {
                        "ok": True,
                        "message": f"Successfully uploaded {filename}",
                        "filename": filename,
                        "path": remote_dest
                    })
                else:
                    self.send_json_response(500, {
                        "ok": False,
                        "error": f"Failed to push file to device: {p_err or p_out}"
                    })
            except Exception as e:
                self.send_json_response(500, {"error": f"Upload failed: {e}"})
            finally:
                if os.path.exists(temp_path):
                    os.unlink(temp_path)
            return

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
            lower_out = full_out.lower()

            # adb connect often exits with returncode 0 even on failure (e.g., 'failed to connect to ...: Connection refused')
            has_error = any(k in lower_out for k in ["failed", "cannot", "unable", "refused", "no route", "timed out", "timeout", "fault"])
            is_connected = ("connected to" in lower_out or "already connected to" in lower_out) and not has_error

            if is_connected:
                state.log(f"Connected to {target}")
                self.send_json_response(200, {"ok": True, "target": target, "message": full_out})
            else:
                state.log(f"Connection failed for {target}: {full_out}")
                self.send_json_response(400, {"ok": False, "error": full_out or "Connection failed. Ensure device is on the same Wi-Fi."})

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

        elif path == "/api/scrcpy/start":
            device = (body.get("device") or "").strip()
            mode = body.get("mode", "screen")
            camera_id = body.get("camera_id")
            camera_facing = body.get("camera_facing")
            stay_awake = body.get("stay_awake", True)
            turn_off_screen = body.get("turn_off_screen", False)
            no_audio = body.get("no_audio", False)

            if not shutil.which("scrcpy"):
                self.send_json_response(400, {
                    "ok": False,
                    "error": "scrcpy is not installed on this machine. Run: sudo apt install scrcpy"
                })
                return

            if not device:
                self.send_json_response(400, {"error": "Device is required"})
                return

            # Terminate any existing scrcpy for this device
            with state.lock:
                old_proc = state.scrcpy_procs.get(device)
                if old_proc and old_proc.poll() is None:
                    try:
                        old_proc.terminate()
                        old_proc.wait(timeout=2)
                    except Exception:
                        pass

            env = os.environ.copy()
            if "DISPLAY" not in env:
                env["DISPLAY"] = ":0"

            cmd = ["scrcpy", "-s", device]
            if mode == "camera":
                cmd.extend(["--video-source=camera"])
                if camera_id is not None and str(camera_id).strip():
                    cmd.append(f"--camera-id={camera_id}")
                elif camera_facing in ("front", "back", "external"):
                    cmd.append(f"--camera-facing={camera_facing}")
                cmd.append(f"--window-title=BeamADB Camera: {device}")
            else:
                cmd.append(f"--window-title=BeamADB Mirror: {device}")

            if stay_awake:
                cmd.append("--stay-awake")
            if turn_off_screen:
                cmd.append("--turn-screen-off")
            if no_audio:
                cmd.append("--no-audio")

            try:
                proc = subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                with state.lock:
                    state.scrcpy_procs[device] = proc
                state.log(f"Started scrcpy ({mode}) for {device}")
                self.send_json_response(200, {
                    "ok": True,
                    "message": f"Launched scrcpy ({mode}) for {device}",
                    "mode": mode
                })
            except Exception as e:
                self.send_json_response(500, {"error": f"Failed to launch scrcpy: {e}"})

        elif path == "/api/scrcpy/stop":
            device = (body.get("device") or "").strip()
            with state.lock:
                proc = state.scrcpy_procs.get(device)
                if proc and proc.poll() is None:
                    try:
                        proc.terminate()
                        proc.wait(timeout=2)
                    except Exception:
                        pass
                    state.scrcpy_procs.pop(device, None)
                    state.log(f"Stopped scrcpy for {device}")
                    self.send_json_response(200, {"ok": True, "message": f"Stopped mirroring for {device}"})
                else:
                    self.send_json_response(200, {"ok": True, "message": "Mirroring was not active"})

        elif path == "/api/files/delete":
            device = (body.get("device") or "").strip()
            remote_path = (body.get("path") or "").strip()
            if not device or not remote_path or remote_path in ("/", "/system", "/vendor", "/sdcard"):
                self.send_json_response(400, {"error": "Invalid deletion request or protected path."})
                return

            d_code, d_out, d_err = run_adb(["-s", device, "shell", f"rm -rf {shlex.quote(remote_path)}"], timeout=15)
            if d_code == 0:
                name = os.path.basename(remote_path.rstrip('/'))
                state.log(f"Deleted {remote_path} on {device}")
                self.send_json_response(200, {"ok": True, "message": f"Deleted '{name}'"})
            else:
                self.send_json_response(500, {"error": d_err or d_out or "Delete failed"})

        elif path == "/api/files/mkdir":
            device = (body.get("device") or "").strip()
            parent_dir = (body.get("path") or "/sdcard").strip()
            folder_name = (body.get("name") or "").strip()
            if not device or not folder_name:
                self.send_json_response(400, {"error": "Device and folder name are required."})
                return

            new_folder_path = f"{parent_dir.rstrip('/')}/{folder_name}"
            m_code, m_out, m_err = run_adb(["-s", device, "shell", f"mkdir -p {shlex.quote(new_folder_path)}"], timeout=10)
            if m_code == 0:
                state.log(f"Created folder {new_folder_path} on {device}")
                self.send_json_response(200, {"ok": True, "message": f"Created folder '{folder_name}'", "path": new_folder_path})
            else:
                self.send_json_response(500, {"error": m_err or m_out or "Failed to create folder"})

        elif path == "/api/files/rename":
            device = (body.get("device") or "").strip()
            old_path = (body.get("old_path") or "").strip()
            new_path = (body.get("new_path") or "").strip()
            if not device or not old_path or not new_path:
                self.send_json_response(400, {"error": "Missing parameters for rename."})
                return

            r_code, r_out, r_err = run_adb(["-s", device, "shell", f"mv {shlex.quote(old_path)} {shlex.quote(new_path)}"], timeout=10)
            if r_code == 0:
                self.send_json_response(200, {"ok": True, "message": "Renamed successfully"})
            else:
                self.send_json_response(500, {"error": r_err or r_out or "Rename failed"})

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
