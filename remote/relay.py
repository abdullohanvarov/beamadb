"""Single-owner, two-peer TLS rendezvous. No arbitrary destination forwarding."""
import argparse
import asyncio
import hashlib
import hmac
from pathlib import Path
import ssl
import socket
import time
import re


def keepalive(sock):
    """Expire a vanished peer instead of holding its rendezvous slot forever."""
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
    for name, value in (('TCP_KEEPIDLE', 15), ('TCP_KEEPINTVL', 5),
                        ('TCP_KEEPCNT', 3), ('TCP_USER_TIMEOUT', 30000)):
        option = getattr(socket, name, None)
        if option is not None:
            sock.setsockopt(socket.IPPROTO_TCP, option, value)


async def pipe(reader, writer):
    while data := await reader.read(65536):
        writer.write(data)
        await writer.drain()


async def bridge(left, right):
    tasks = [asyncio.create_task(pipe(left[0], right[1])),
             asyncio.create_task(pipe(right[0], left[1]))]
    try:
        await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    finally:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)


def credential(secret, role):
    return hmac.new(bytes.fromhex(secret), role.encode(), hashlib.sha256).hexdigest()


class Broker:
    def __init__(self, secret):
        self.tokens = {credential(secret, r): r for r in ('desktop', 'phone')}
        self.channels = {}
        self.waiting = {}
        self.active = False
        self.phone_seen = float("-inf")

    async def accept(self, reader, writer):
        try:
            line = (await asyncio.wait_for(reader.readline(), 5)).decode('ascii').strip()
            parts = line.split(' CHANNEL ')
            if len(parts) == 2:
                token, channel = parts
                raw = token.removeprefix('STATUS ').removeprefix('WATCH ')
                if raw not in self.tokens or not re.fullmatch(r'[0-9a-f]{64}', channel):
                    return
                if channel not in self.channels:
                    if len(self.channels) >= 256:
                        return
                    child = object.__new__(Broker)
                    child.tokens = self.tokens
                    child.channels = {}
                    child.waiting = {}
                    child.active = False
                    child.phone_seen = float('-inf')
                    self.channels[channel] = child
                await self.channels[channel].accept_token(reader, writer, token)
            elif len(parts) == 1:
                await self.accept_token(reader, writer, line)
        except (TimeoutError, ValueError, OSError, UnicodeError):
            pass
        finally:
            writer.close()

    async def accept_token(self, reader, writer, token):
        slot = None
        try:
            if token.startswith('WATCH '):
                if self.tokens.get(token[6:]) != 'desktop':
                    return
                closed = asyncio.create_task(reader.read(1))
                previous = None
                heartbeat = 0
                try:
                    while not closed.done():
                        state = b'ONLINE\n' if time.monotonic() - self.phone_seen < 35 else b'OFFLINE\n'
                        if state != previous or heartbeat >= 15:
                            writer.write(state)
                            await writer.drain()
                            previous, heartbeat = state, 0
                        await asyncio.wait({closed}, timeout=1)
                        heartbeat += 1
                finally:
                    closed.cancel()
                    await asyncio.gather(closed, return_exceptions=True)
                return
            if token.startswith('STATUS '):
                role = self.tokens.get(token[7:])
                if role == 'phone':
                    self.phone_seen = time.monotonic()
                if role:
                    writer.write(b'ONLINE\n' if time.monotonic() - self.phone_seen < 35 else b'OFFLINE\n')
                    await writer.drain()
                return
            role = self.tokens.get(token)
            if not role or self.active or role in self.waiting:
                return
            other = 'phone' if role == 'desktop' else 'desktop'
            peer = self.waiting.pop(other, None)
            if peer is None:
                slot = asyncio.get_running_loop().create_future()
                self.waiting[role] = (reader, writer, slot)
                await asyncio.wait_for(asyncio.shield(slot), 20)
                return
            self.active = True
            try:
                for stream in (peer[1], writer):
                    stream.write(b'OK\n')
                    await stream.drain()
                await bridge((reader, writer), peer)
            finally:
                self.active = False
                peer[2].set_result(None)
        except (TimeoutError, ValueError, OSError, UnicodeError):
            pass
        finally:
            # Once matched, the other handler owns this stream until the bridge ends.
            if slot and not slot.done() and role not in self.waiting:
                await slot
            elif slot and self.waiting.get(role, (None, None, None))[2] is slot:
                self.waiting.pop(role)
            writer.close()


async def main():
    p = argparse.ArgumentParser()
    for name in ('cert', 'key', 'secret'):
        p.add_argument('--' + name, required=True)
    p.add_argument('--host', default='0.0.0.0')
    p.add_argument('--port', type=int, default=45883)
    args = p.parse_args()
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(args.cert, args.key)
    broker = Broker(Path(args.secret).read_text().strip())
    async def accept(reader, writer):
        keepalive(writer.get_extra_info('socket'))
        await broker.accept(reader, writer)

    async with await asyncio.start_server(accept, args.host, args.port,
                                          ssl=context, limit=1024, ssl_handshake_timeout=5) as server:
        await server.serve_forever()


if __name__ == '__main__':
    asyncio.run(main())
