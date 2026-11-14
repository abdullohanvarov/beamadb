"""Ubuntu user service. Exposes one loopback transport to the user's ADB server."""
import asyncio
import hashlib
import json
import os
from pathlib import Path
import shutil
import hmac
import fcntl
import ssl
from relay import bridge, keepalive

BASE = Path(os.environ.get('BEAMADB_LINK_CONFIG', str(Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'beamadb-link')))


async def main():
    cfg = json.loads((BASE / 'desktop.json').read_text())
    suffix = ' CHANNEL ' + cfg['channel'] if cfg.get('channel') else ''
    target = '127.0.0.1:' + str(cfg.get('localPort', 45884))
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE  # Authenticate the exact provisioned certificate below.
    inner = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    inner.load_cert_chain(BASE / "peer.pem", BASE / "peer.key")
    busy = False

    pending = None

    async def relay():
        reader, writer = await asyncio.wait_for(asyncio.open_connection(
            cfg['host'], cfg['port'], ssl=ctx, server_hostname=cfg['host']), 10)
        keepalive(writer.get_extra_info('socket'))
        cert = writer.get_extra_info('ssl_object').getpeercert(binary_form=True)
        if hashlib.sha256(cert).hexdigest() != cfg['pin']:
            writer.close()
            raise ValueError('Relay certificate changed')
        return reader, writer

    async def presence():
        # Persist the last authoritative state so agent/relay restarts do not
        # produce duplicate alerts or mistake a network failure for phone logout.
        last_path = BASE / 'last-presence'
        previous = last_path.read_text().strip() if last_path.exists() else None
        async def publish(state):
            nonlocal previous
            (BASE / 'status.tmp').write_text(state)
            (BASE / 'status.tmp').replace(BASE / 'status')
            if state not in ('Phone online', 'Phone offline') or state == previous:
                return
            initial = previous is None
            previous = state
            last_path.write_text(state)
            root = BASE.parent.parent if BASE.parent.name == 'phones' else BASE
            preferences = root / 'notifications.json'
            try:
                enabled = json.loads(preferences.read_text()).get('enabled', True) if preferences.exists() else True
                name_path = BASE / 'name'
                name = name_path.read_text().strip() if name_path.exists() else 'Your phone'
                command = shutil.which('notify-send')
                if enabled and command and not (initial and state == 'Phone offline'):
                    label = 'connected' if state == 'Phone online' else 'disconnected'
                    proc = await asyncio.create_subprocess_exec(command, '--app-name=BeamADB', '--icon=smartphone', '--',
                        f'{name} {label}', 'VPS reports the companion online. ADB may still be reconnecting.' if label == 'connected' else 'The VPS has not heard from this phone for 35 seconds.',
                        stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
                    try:
                        await asyncio.wait_for(proc.wait(), 5)
                    except TimeoutError:
                        proc.kill()
                        await proc.wait()
            except (OSError, ValueError):
                pass
        while True:
            writer = None
            try:
                reader, writer = await relay()
                writer.write(('WATCH ' + cfg['token'] + suffix + '\n').encode())
                await writer.drain()
                while True:
                    response = await asyncio.wait_for(reader.readline(), 25)
                    if response not in (b'ONLINE\n', b'OFFLINE\n'):
                        raise OSError('Presence subscription ended')
                    await publish('Phone online' if response == b'ONLINE\n' else 'Phone offline')
            except (OSError, TimeoutError, ValueError):
                await publish('Relay unavailable')
            finally:
                if writer:
                    writer.close()
            await asyncio.sleep(5)

    async def authenticated(reader, writer):
        nonlocal pending
        try:
            proof = await asyncio.wait_for(reader.readline(), 5)
            if pending is None or not hmac.compare_digest(proof, (cfg['proof'] + '\n').encode()):
                return
            pair = pending
            pending = None
            await bridge(pair, (reader, writer))
        except (TimeoutError, OSError, ValueError) as error:
            print(f'Peer connection retry: {type(error).__name__}: {error}', flush=True)
        finally:
            writer.close()

    tls_server = await asyncio.start_server(authenticated, '127.0.0.1', 0, ssl=inner)
    inner_port = tls_server.sockets[0].getsockname()[1]

    async def attach(reader, writer):
        nonlocal busy, pending
        if busy:
            writer.close()
            return
        busy = True
        remote = local = None
        try:
            upstream, remote = await relay()
            remote.write((cfg['token'] + suffix + '\n').encode())
            await remote.drain()
            if await asyncio.wait_for(upstream.readline(), 25) == b'OK\n':
                local_reader, local = await asyncio.open_connection('127.0.0.1', inner_port)
                pending = (reader, writer)
                await bridge((local_reader, local), (upstream, remote))
        except (OSError, TimeoutError, ValueError) as error:
            print(f'Relay tunnel retry: {type(error).__name__}: {error}', flush=True)
        finally:
            pending = None
            if local:
                local.close()
            if remote:
                remote.close()
            writer.close()
            busy = False

    tool = shutil.which('adb') or '/usr/lib/beamadb/bin/scrcpy/linux/adb'
    bundled = Path.home() / '.local/share/beamadb/bin/scrcpy/linux/adb'
    if bundled.is_file():
        tool = str(bundled)

    async def adb(*args):
        proc = await asyncio.create_subprocess_exec(tool, *args,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        try:
            output, _ = await asyncio.wait_for(proc.communicate(), 30)
            return output.strip()
        except TimeoutError:
            proc.kill()
            await proc.wait()
            return b''

    async def cellular_bootstrap():
        while True:
            with (BASE / 'cellular.lock').open('a') as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    await asyncio.sleep(1)
                    continue
                # Read on each pass so turning the mode off takes effect immediately.
                settings = json.loads((BASE / 'desktop.json').read_text())
                if settings.get('cellularMode', False):
                    if await adb('-s', target, 'get-state') == b'device':
                        port = await adb('-s', target, 'shell', 'getprop', 'service.adb.tcp.port')
                        if port != b'45885':
                            response = await adb('-s', target, 'tcpip', '45885')
                            if b'restarting in TCP mode' in response:
                                print('Cellular ADB mode enabled for this phone boot', flush=True)
            await asyncio.sleep(15)

    async with await asyncio.start_server(attach, '127.0.0.1', cfg.get('localPort', 45884)):
        status_task = asyncio.create_task(presence())
        cellular_task = asyncio.create_task(cellular_bootstrap())
        while True:
            if cellular_task.done():
                cellular_task.result()
            if status_task.done():
                status_task.result()
            if not busy:
                if await adb('-s', target, 'get-state') != b'device':
                    await adb('disconnect', target)
                    await adb('connect', target)
            await asyncio.sleep(3)


if __name__ == '__main__':
    asyncio.run(main())
