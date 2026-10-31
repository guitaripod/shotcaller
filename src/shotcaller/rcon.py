"""A minimal IW4x RCON client over UDP."""

from __future__ import annotations

import socket

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
