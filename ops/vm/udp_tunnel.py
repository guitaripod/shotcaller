"""Carries a UDP game port over one TCP connection, so it can cross a network that drops UDP replies.

QEMU's user-mode network with restrict=on is what keeps the guest away from the host and the LAN, but it also
drops UDP replies to host-forwarded ports. TCP forwards still work, so the host side listens on the UDP port and
the guest side talks to the game server, and the two exchange datagrams as frames over a forwarded TCP port.

A frame is a 2-byte payload length, a 4-byte peer id and the payload. The host side gives every sender address an
id and only ever sends to addresses it has seen, so a compromised guest cannot make it send to anywhere else. The
guest side gives every id its own UDP socket to the server, so the server tells players apart by port.
"""

from __future__ import annotations

import argparse
import asyncio
import struct
import time

HEADER = struct.Struct("!HI")
IDLE_S = 300.0
RETRY_S = 2.0


def frame(peer: int, payload: bytes) -> bytes:
    """One datagram as a frame."""
    return HEADER.pack(len(payload), peer) + payload


async def read_frame(reader: asyncio.StreamReader) -> tuple[int, bytes]:
    """The next frame as (peer id, payload); raises IncompleteReadError when the connection ends."""
    length, peer = HEADER.unpack(await reader.readexactly(HEADER.size))
    return peer, await reader.readexactly(length)


class HostSide(asyncio.DatagramProtocol):
    """Listens on the public UDP port and relays every datagram through the tunnel."""

    def __init__(self, tunnel: tuple[str, int]) -> None:
        self.tunnel = tunnel
        self.transport: asyncio.DatagramTransport | None = None
        self.writer: asyncio.StreamWriter | None = None
        self.ids: dict[tuple, int] = {}
        self.peers: dict[int, tuple[tuple, float]] = {}
        self.next_id = 1

    def connection_made(self, transport: asyncio.BaseTransport) -> None:
        self.transport = transport  # type: ignore[assignment]

    def datagram_received(self, data: bytes, addr: tuple) -> None:
        """A player's datagram: tag it with the sender's id and pass it on, or drop it while the tunnel is down."""
        peer = self.ids.get(addr)
        if peer is None:
            peer = self.next_id
            self.next_id += 1
            self.ids[addr] = peer
        self.peers[peer] = (addr, time.monotonic())
        if self.writer is not None and not self.writer.is_closing():
            self.writer.write(frame(peer, data))

    def reply(self, peer: int, payload: bytes) -> None:
        """A server datagram coming back through the tunnel, sent to the address that id belongs to."""
        known = self.peers.get(peer)
        if known is not None and self.transport is not None:
            self.transport.sendto(payload, known[0])

    def expire(self) -> None:
        """Forgets senders that have been silent for a while."""
        cutoff = time.monotonic() - IDLE_S
        for peer, (addr, seen) in list(self.peers.items()):
            if seen < cutoff:
                del self.peers[peer]
                self.ids.pop(addr, None)

    async def run_tunnel(self) -> None:
        """Keeps one connection to the guest side open for as long as the process runs."""
        while True:
            try:
                reader, writer = await asyncio.open_connection(*self.tunnel)
            except OSError:
                await asyncio.sleep(RETRY_S)
                continue
            self.writer = writer
            try:
                while True:
                    peer, payload = await read_frame(reader)
                    self.reply(peer, payload)
            except (asyncio.IncompleteReadError, OSError):
                pass
            finally:
                self.writer = None
                writer.close()
            await asyncio.sleep(RETRY_S)


class GuestEndpoint(asyncio.DatagramProtocol):
    """One UDP socket to the game server on behalf of one remote sender."""

    def __init__(self, peer: int, writer: asyncio.StreamWriter) -> None:
        self.peer = peer
        self.writer = writer
        self.seen = time.monotonic()

    def datagram_received(self, data: bytes, _addr: tuple) -> None:
        if not self.writer.is_closing():
            self.writer.write(frame(self.peer, data))


class GuestSide:
    """Accepts the tunnel connection and fans its frames out to the game server."""

    def __init__(self, game: tuple[str, int]) -> None:
        self.game = game

    async def handle(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        """Serves one tunnel connection until it ends, then closes every socket it opened."""
        endpoints: dict[int, tuple[asyncio.DatagramTransport, GuestEndpoint]] = {}
        loop = asyncio.get_running_loop()
        reaper = asyncio.create_task(self.reap(endpoints))
        try:
            while True:
                peer, payload = await read_frame(reader)
                if peer not in endpoints:
                    transport, protocol = await loop.create_datagram_endpoint(lambda p=peer: GuestEndpoint(p, writer), remote_addr=self.game)
                    endpoints[peer] = (transport, protocol)
                transport, protocol = endpoints[peer]
                protocol.seen = time.monotonic()
                transport.sendto(payload)
        except (asyncio.IncompleteReadError, OSError):
            pass
        finally:
            reaper.cancel()
            for transport, _ in endpoints.values():
                transport.close()
            writer.close()

    async def reap(self, endpoints: dict) -> None:
        """Closes the sockets of senders that have been silent for a while."""
        while True:
            await asyncio.sleep(30)
            cutoff = time.monotonic() - IDLE_S
            for peer, (transport, protocol) in list(endpoints.items()):
                if protocol.seen < cutoff:
                    transport.close()
                    del endpoints[peer]


def split(address: str) -> tuple[str, int]:
    """Splits host:port."""
    host, _, port = address.rpartition(":")
    return host, int(port)


async def run_host(listen: tuple[str, int], tunnel: tuple[str, int]) -> None:
    loop = asyncio.get_running_loop()
    side = HostSide(tunnel)
    await loop.create_datagram_endpoint(lambda: side, local_addr=listen)
    asyncio.create_task(side.run_tunnel())
    while True:
        await asyncio.sleep(60)
        side.expire()


async def run_guest(listen: tuple[str, int], game: tuple[str, int]) -> None:
    server = await asyncio.start_server(GuestSide(game).handle, *listen)
    async with server:
        await server.serve_forever()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="side", required=True)
    host = sub.add_parser("host", help="the side that listens on the public UDP port")
    host.add_argument("--listen", default="0.0.0.0:28961", help="UDP address players send to")
    host.add_argument("--tunnel", default="127.0.0.1:28962", help="TCP address of the guest side, as forwarded on the host")
    guest = sub.add_parser("guest", help="the side next to the game server")
    guest.add_argument("--listen", default="0.0.0.0:28962", help="TCP address the host side connects to")
    guest.add_argument("--game", default="127.0.0.1:28961", help="UDP address of the game server")
    args = parser.parse_args()
    if args.side == "host":
        asyncio.run(run_host(split(args.listen), split(args.tunnel)))
    else:
        asyncio.run(run_guest(split(args.listen), split(args.game)))


if __name__ == "__main__":
    main()
