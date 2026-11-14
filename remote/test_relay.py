import asyncio
import unittest
class StreamSink:
    """In-memory byte transport for testing the rendezvous protocol."""
    def __init__(self, peer):
        self.peer = peer

    def write(self, data):
        self.peer.feed_data(data)

    async def drain(self):
        await asyncio.sleep(0)

    def close(self):
        self.peer.feed_eof()

from relay import Broker, credential


class RelayTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.secret = '43' * 32
        self.broker = Broker(self.secret)
        self.handlers = []
        self.clients = []

    async def client(self, token):
        reader, server_reader = asyncio.StreamReader(), asyncio.StreamReader()
        writer = StreamSink(server_reader)
        self.clients.append(writer)
        peer = server_reader, StreamSink(reader)
        self.handlers.append(asyncio.create_task(self.broker.accept(*peer)))
        writer.write((token + '\n').encode())
        await writer.drain()
        return reader, writer

    async def asyncTearDown(self):
        for writer in self.clients:
            writer.close()
        await asyncio.wait_for(asyncio.gather(*self.handlers), 2)

    async def test_presence_without_adb(self):
        async def status(role):
            r, _ = await self.client('STATUS ' + credential(self.secret, role))
            return await r.readline()
        self.assertEqual(await status('desktop'), b'OFFLINE\n')
        self.assertEqual(await status('phone'), b'ONLINE\n')
        self.assertEqual(await status('desktop'), b'ONLINE\n')
        self.broker.phone_seen -= 40
        self.assertEqual(await status('desktop'), b'OFFLINE\n')

    async def test_authenticate_transfer_and_rejoin(self):
        invalid, _ = await self.client('wrong')
        self.assertEqual(await invalid.read(), b'')
        for first, second in [('phone','desktop'), ('desktop','phone')]:
            a, aw = await self.client(credential(self.secret,first))
            b, bw = await self.client(credential(self.secret,second))
            self.assertEqual(await a.readline(), b'OK\n')
            self.assertEqual(await b.readline(), b'OK\n')
            duplicate, _ = await self.client(credential(self.secret,second))
            self.assertEqual(await duplicate.read(), b'')
            for src,dst in [(aw,b),(bw,a)]:
                src.write(bytes(range(256)))
                self.assertEqual(await dst.readexactly(256),bytes(range(256)))
            aw.close()
            self.assertEqual(await b.read(), b'')
            await asyncio.gather(*self.handlers)

    async def test_channels_are_isolated_and_legacy_still_works(self):
        async def join(role, channel):
            return await self.client(credential(self.secret, role) + ' CHANNEL ' + channel)
        one, two = 'a' * 64, 'b' * 64
        a, aw = await join('phone', one)
        b, bw = await join('desktop', one)
        c, cw = await join('phone', two)
        d, dw = await join('desktop', two)
        for reader in (a, b, c, d):
            self.assertEqual(await reader.readline(), b'OK\n')
        aw.write(b'first phone\n')
        cw.write(b'second phone\n')
        self.assertEqual(await b.readline(), b'first phone\n')
        self.assertEqual(await d.readline(), b'second phone\n')
        r, _ = await self.client('STATUS ' + credential(self.secret, 'phone') + ' CHANNEL ' + one)
        self.assertEqual(await r.readline(), b'ONLINE\n')
        r, _ = await self.client('STATUS ' + credential(self.secret, 'desktop') + ' CHANNEL ' + two)
        self.assertEqual(await r.readline(), b'OFFLINE\n')
        r, _ = await self.client('STATUS ' + credential(self.secret, 'desktop'))
        self.assertEqual(await r.readline(), b'OFFLINE\n')
        invalid, _ = await self.client('wrong CHANNEL ' + 'c' * 64)
        self.assertEqual(await invalid.read(), b'')
        self.assertEqual(len(self.broker.channels), 2)

    async def test_watch_pushes_transitions_and_rejects_phone_subscribers(self):
        channel = 'd' * 64
        watcher, _ = await self.client('WATCH ' + credential(self.secret, 'desktop') + ' CHANNEL ' + channel)
        self.assertEqual(await asyncio.wait_for(watcher.readline(), 2), b'OFFLINE\n')
        heartbeat, _ = await self.client('STATUS ' + credential(self.secret, 'phone') + ' CHANNEL ' + channel)
        self.assertEqual(await heartbeat.readline(), b'ONLINE\n')
        self.assertEqual(await asyncio.wait_for(watcher.readline(), 2), b'ONLINE\n')
        self.broker.channels[channel].phone_seen -= 40
        self.assertEqual(await asyncio.wait_for(watcher.readline(), 2), b'OFFLINE\n')
        denied, _ = await self.client('WATCH ' + credential(self.secret, 'phone') + ' CHANNEL ' + channel)
        self.assertEqual(await denied.read(), b'')
