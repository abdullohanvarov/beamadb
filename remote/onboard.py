"""Provision an authorized ADB phone without exposing invitation credentials."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import ssl
import subprocess
import time
from remove_device import remove


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--serial', required=True)
    p.add_argument('--adb', default=shutil.which('adb'))
    a = p.parse_args()
    base = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'beamadb-link'
    source = Path(__file__).resolve().parent
    if not (base / 'invite.json').is_file():
        raise RuntimeError('Configure the relay in Connect device → Remote first.')
    base.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (base / 'onboard.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        def adb(*args, data=None):
            r = subprocess.run([a.adb, '-s', a.serial, *args], input=data,
                               capture_output=True, timeout=120)
            out = r.stdout.decode(errors='replace')
            if r.returncode or 'Error:' in out or 'Exception' in out or 'Failure [' in out:
                # No command arguments or credentials in exceptions.
                raise RuntimeError('Phone setup failed. Unlock the phone and allow USB installation/debugging if requested.')
            return out.strip()
        if adb('get-state') != 'device':
            raise RuntimeError('Authorize this computer on the phone first.')
        identity = adb('shell', 'getprop', 'ro.serialno')
        if not identity or identity == 'unknown':
            raise RuntimeError('Cannot identify this phone safely.')
        key = hashlib.sha256(identity.encode()).hexdigest()
        if (base / 'removed' / (key + '.json')).exists():
            state = remove(base, identity, a.serial, a.adb)
            print('Removed; BeamADB Link uninstalled.' if state == 'complete' else 'Uninstall pending. Keep the phone connected through authorized USB/local ADB.')
            return
        folder = base / 'phones' / key
        folder.mkdir(mode=0o700, parents=True, exist_ok=True)
        cfg_path = folder / 'desktop.json'
        if not cfg_path.exists():
            cfg = json.loads((base / 'desktop.json').read_text())
            used = {json.loads(path.read_text()).get('localPort') for path in (base / 'phones').glob('*/desktop.json')}
            port = next(port for port in range(45900, 46156) if port not in used)
            cfg.update(channel=secrets.token_hex(32), proof=secrets.token_hex(32), localPort=port)
            write_private(cfg_path, json.dumps(cfg))
            for name in ('peer.pem', 'peer.key'):
                write_private(folder / name, (base / name).read_text())
        cfg = json.loads(cfg_path.read_text())
        if not (folder / 'name').exists():
            write_private(folder / 'name', adb('shell', 'getprop', 'ro.product.model') or 'Phone')
        invitation = json.loads((base / 'invite.json').read_text())
        invitation.update(channel=cfg['channel'], proof=cfg['proof'], peer=hashlib.sha256(ssl.PEM_cert_to_DER_cert((folder / 'peer.pem').read_text())).hexdigest())
        apk = source / 'BeamADB-Link.apk'
        digest = hashlib.sha256(apk.read_bytes()).hexdigest()
        installed = adb('shell', 'pm', 'path', 'dev.beamadb.link')
        stamp = folder / 'installed-apk'
        changed = not installed or not stamp.exists() or stamp.read_text() != digest
        if changed:
            adb('install', '--no-incremental', '-r', str(apk))
            write_private(stamp, digest)
        adb('shell', 'pm', 'grant', 'dev.beamadb.link', 'android.permission.WRITE_SECURE_SETTINGS')
        status = adb('shell', 'content', 'query', '--uri', 'content://dev.beamadb.link.provision/config')
        configured = cfg['channel'] in status and 'enabled=1' in status
        if not configured:
            adb('shell', 'content', 'write', '--uri', 'content://dev.beamadb.link.provision/config', data=json.dumps(invitation).encode())
            for _ in range(20):
                status = adb('shell', 'content', 'query', '--uri', 'content://dev.beamadb.link.provision/config')
                if cfg['channel'] in status and 'enabled=1' in status:
                    break
                time.sleep(.1)
            else:
                raise RuntimeError('Phone did not confirm configuration. Retry setup.')
        # Match the user's choice in the existing relay configuration.
        if changed or not configured or 'ServiceRecord{' not in adb('shell', 'dumpsys', 'activity', 'services', 'dev.beamadb.link/.Link'):
            adb('shell', 'am', 'start', '-n', 'dev.beamadb.link/.Setup', '--ez', 'background', 'true')
        agents = Path.home() / '.local/share/beamadb-link'
        agents.mkdir(parents=True, exist_ok=True)
        for name in ('agent.py', 'relay.py'):
            shutil.copyfile(source / name, agents / name)
        unit = f'beamadb-link-phone-{key}.service'
        units = Path.home() / '.config/systemd/user'
        units.mkdir(parents=True, exist_ok=True)
        # Systemd paths are quoted; identity is hashed and never interpolated.
        env = str(folder).replace('%', '%%').replace('"', '\\"')
        script = str(agents / 'agent.py').replace('%', '%%').replace('"', '\\"')
        (units / unit).write_text(f'[Unit]\nDescription=BeamADB paired phone\n[Service]\nEnvironment="BEAMADB_LINK_CONFIG={env}"\nExecStart=/usr/bin/python3 "{script}"\nRestart=always\nRestartSec=5\n[Install]\nWantedBy=default.target\n')
        subprocess.run(['systemctl', '--user', 'daemon-reload'], check=True, capture_output=True)
        subprocess.run(['systemctl', '--user', 'enable', '--now', unit], check=True, capture_output=True)
        if cfg.get('cellularMode') and adb('shell', 'getprop', 'service.adb.tcp.port') != '45885':
            adb('tcpip', '45885')
        print(f'Paired automatically. Internet ADB: 127.0.0.1:{cfg["localPort"]}. After reboot, unlock and use trusted Wi-Fi. Some phones require Background autostart in Android settings.')


def write_private(path, text):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as stream:
        stream.write(text)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Explicit errors contain no secrets; subprocess errors are deliberately generic.
        print(str(error) if isinstance(error, RuntimeError) else 'Automatic setup failed. Check phone authorization and the local agent installation.')
        raise SystemExit(1)
