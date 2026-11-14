"""Manage authenticated ADB TCP startup for all paired phones."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('mode', choices=('enable', 'disable'))
p.add_argument('--serial', help='Explicit USB transport for stopping an unreachable phone listener')
a = p.parse_args()
base = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'beamadb-link'
bundled = Path.home() / '.local/share/beamadb/bin/scrcpy/linux/adb'
tool = str(bundled) if bundled.is_file() else shutil.which('adb')
phones = list((base / 'phones').glob('*/desktop.json'))
failed = False
for path in [base / 'desktop.json', *phones]:
    with (path.parent / 'cellular.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        cfg = json.loads(path.read_text())
        cfg['cellularMode'] = a.mode == 'enable'
        fd, temporary = tempfile.mkstemp(dir=path.parent)
        try:
            with os.fdopen(fd, 'w') as stream:
                json.dump(cfg, stream)
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary): os.unlink(temporary)
        if a.mode == 'disable' and (not phones or path.parent != base):
            target = a.serial or f'127.0.0.1:{cfg.get("localPort", 45884)}'
            try:
                result = subprocess.run([tool, '-s', target, 'usb'], capture_output=True, timeout=30) if tool else None
                failed |= result is None or result.returncode != 0
            except subprocess.TimeoutExpired:
                failed = True
if a.mode == 'enable':
    print('Cellular mode enabled for paired phones. TCP 45885 requires an authorized ADB key and is reachable on phone network interfaces. Trusted Wi-Fi is needed after phone reboot.')
elif failed:
    raise SystemExit('Automatic TCP startup disabled. Some phones are unreachable: restart those phones to close their TCP listener, or connect USB and repeat with --serial PHONE_SERIAL.')
else:
    print('Automatic TCP startup disabled; paired phone TCP listeners stopped.')
