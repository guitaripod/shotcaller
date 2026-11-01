"""A minimal IW4x RCON client over UDP."""

from __future__ import annotations

import re
import socket

_PLAYER_LINE = re.compile(r"^\s*(\d+)\s+(-?\d+)\s+(-?\d+)\s+(\S+)\s+(.+?)\s+-?\d+\s+\S+\s+-?\d+\s+-?\d+\s*$")
_OOB = b"\xff\xff\xff\xff"


class Rcon:
    """Sends rcon commands and collects the reply packets."""

    def __init__(self, host: str, port: int, password: str, timeout_s: float = 1.5) -> None:
        self.host = host
        self.port = port
        self._password = password
        self.timeout_s = timeout_s

    def send(self, command: str) -> str:
        """Runs one command and returns whatever the server printed back."""
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(self.timeout_s)
        try:
            sock.sendto(_OOB + f"rcon {self._password} {command}".encode(), (self.host, self.port))
            return self._collect(sock)
        finally:
            sock.close()

    def _collect(self, sock: socket.socket) -> str:
        parts: list[str] = []
        try:
            while True:
                parts.append(sock.recvfrom(65535)[0][len(_OOB) :].decode("latin-1"))
        except TimeoutError:
            pass
        return "".join(parts)

    def alive(self) -> bool:
        """Whether the server answers a status request."""
        return "map:" in self.send("status")

    def human_count(self) -> int:
        """How many human players are connected: every player line whose guid is not a bot's."""
        return count_humans(self.send("status"))


def count_humans(status: str) -> int:
    """Counts the human lines of an rcon `status` reply; bots carry a `botN` guid."""
    total = 0
    for line in status.splitlines():
        match = _PLAYER_LINE.match(line)
        if match and not match.group(4).startswith("bot"):
            total += 1
    return total
