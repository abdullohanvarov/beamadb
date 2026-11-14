"""Remove a phone and retain a tombstone to prevent automatic reinstallation."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def phone_key(identity):
    return hashlib.sha256(identity.encode()).hexdigest()


def uninstall(adb, serial, identity):
    def run(*args):
        return subprocess.run([adb, '-s', serial, *args], capture_output=True, text=True, timeout=25)
    try:
        check = run('shell', 'getprop', 'ro.serialno')
        if check.returncode or check.stdout.strip() != identity:
            return False
        result = run('shell', 'pm', 'uninstall', 'dev.beamadb.link')
        # On a relay-only transport uninstall can sever the connection before
        # acknowledgement. Never claim success without the phone's confirmation.
        if result.returncode == 0 and result.stdout.strip() == 'Success':
            return True
        check = run('shell', 'pm', 'list', 'packages', 'dev.beamadb.link')
        return check.returncode == 0 and not check.stderr.strip() and not check.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return False


def remove(base, identity, serial, adb):
    key = phone_key(identity)
    removed = base / 'removed'
    removed.mkdir(parents=True, mode=0o700, exist_ok=True)
    marker = removed / (key + '.json')
    entry = {'identity': identity, 'state': 'pending'}
    if marker.exists():
        entry = json.loads(marker.read_text())
    # Write the tombstone before any uninstall/service action, under the shared
    # onboarding lock. An in-flight setup cannot reinstall the companion.
    def save():
        with os.fdopen(os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as f:
            json.dump(entry, f)
    save()
    if serial and adb and entry['state'] != 'complete' and uninstall(adb, serial, identity):
        entry['state'] = 'complete'
        save()
    unit = f'beamadb-link-phone-{key}.service'
    unit_path = Path.home() / '.config/systemd/user' / unit
    if unit_path.exists():
        subprocess.run(['systemctl', '--user', 'disable', '--now', unit], check=True, capture_output=True)
        unit_path.unlink()
        subprocess.run(['systemctl', '--user', 'daemon-reload'], check=True, capture_output=True)
    folder = base / 'phones' / key
    if folder.exists():
        shutil.rmtree(folder)
    return entry['state']


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--identity', required=True)
    p.add_argument('--serial')
    p.add_argument('--adb', default=shutil.which('adb'))
    args = p.parse_args()
    base = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'beamadb-link'
    base.mkdir(parents=True, exist_ok=True)
    with (base / 'onboard.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = remove(base, args.identity, args.serial, args.adb)
    print('Removed; BeamADB Link uninstalled.' if state == 'complete' else 'Removed from desktop. Uninstall is unconfirmed; reconnect this phone through USB/local ADB to finish automatically.')


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('Removal could not finish. Reconnect the phone and retry.')
        raise SystemExit(1)
