"""Run:  python -m seesaw_sidecar [--host 0.0.0.0] [--backend dinov2|rgb] [--k 8] [--no-match]

--host 127.0.0.1 (default) only accepts the desktop Godot on this PC.
--host 0.0.0.0   lets the Quest reach it over Wi-Fi. There is no password: use a network you trust.
"""
import argparse
import socket

from .backends import create_backend
from .http_server import serve
from .prober import Prober


def lan_addresses():
    try:
        return sorted({ip for ip in socket.gethostbyname_ex(socket.gethostname())[2] if not ip.startswith("127.")})
    except OSError:
        return []


def main():
    ap = argparse.ArgumentParser(prog="seesaw_sidecar")
    ap.add_argument("--backend", choices=["dinov2", "rgb"], default="dinov2")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--k", type=int, default=8)
    ap.add_argument("--no-match", action="store_true", help="paper behaviour, no colour matching between probes")
    ap.add_argument("--random-weights", action="store_true", help="test only: DINOv2 architecture with random weights")
    a = ap.parse_args()

    backend = create_backend(a.backend, random_weights=a.random_weights)
    prober = Prober(backend, k=a.k, match=not a.no_match)
    print(f"See/Saw sidecar ready: {backend.name}  (K={a.k}, matching={'on' if prober.match else 'off'})")
    print(f"  listening on {a.host}:{a.port}")
    if a.host == "0.0.0.0":
        for ip in lan_addresses():
            print(f"  headset server address: {ip}")
    serve(prober, a.host, a.port)


if __name__ == "__main__":
    main()
