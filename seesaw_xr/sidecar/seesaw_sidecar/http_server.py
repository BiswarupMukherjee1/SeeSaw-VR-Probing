"""Tiny HTTP front: GET / = health check, POST /probe = PNG in, JSON out."""
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def make_handler(prober):
    class Handler(BaseHTTPRequestHandler):
        def _send(self, code, obj):
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            self._send(200, {"ok": True, "backend": prober.backend.name})

        def do_POST(self):
            if self.path != "/probe":
                return self._send(404, {"error": "use POST /probe"})
            data = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            t0 = time.perf_counter()
            with prober.lock:
                res = prober.probe(data)
            res["timing_ms"]["server_total"] = round((time.perf_counter() - t0) * 1000, 1)
            self._send(200, res)

        def log_message(self, fmt, *args):
            pass
    return Handler


def serve(prober, host, port):
    ThreadingHTTPServer((host, port), make_handler(prober)).serve_forever()
