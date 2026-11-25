"""See/Saw PoC sidecar.

Receives a PNG of the aimed view from Godot, runs a frozen DINOv2 ViT-S/14,
groups the patch features with k-means (K=8), and sends back:
  * a label map (which group each pixel belongs to)
  * the mean CLS-to-patch attention of each group (last layer)
  * per-stage timings in milliseconds

Run:
    python server.py                      # DINOv2 (downloads facebook/dinov2-small once)
    python server.py --backend rgb        # no deep learning, plain colour k-means (debug only)
    python server.py --no-match           # paper behaviour: colours relabelled every probe
"""
import argparse
import base64
import io
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
from PIL import Image

IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
IMAGENET_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)
IMG = 224          # input size, 224 / 14 = 16 patches per side
OUT = 112          # resolution of the label map sent back to Godot


# ---------------------------------------------------------------- backends
class Dinov2Backend:
    name = "DINOv2 ViT-S/14"
    has_attention = True

    def __init__(self, model_id="facebook/dinov2-small", random_weights=False):
        import torch
        from transformers import AutoModel, Dinov2Config, Dinov2Model

        self.torch = torch
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        if random_weights:  # only for testing shapes without internet
            self.model = Dinov2Model(Dinov2Config(hidden_size=384, num_hidden_layers=12, num_attention_heads=6,
                                                  patch_size=14, image_size=518, intermediate_size=1536))
            self.model.config._attn_implementation = "eager"
            self.name += " (RANDOM WEIGHTS, test only)"
        else:
            self.model = AutoModel.from_pretrained(model_id, attn_implementation="eager")
        self.model.eval().to(self.device)
        self.half = self.device == "cuda"
        if self.half:
            self.model.half()

    def features(self, img):
        """img: float32 HxWx3 in [0,1], 224x224. Returns (patch_feats 16x16xC, cls_attn 16x16)."""
        torch = self.torch
        x = (img - IMAGENET_MEAN) / IMAGENET_STD
        x = torch.from_numpy(x.transpose(2, 0, 1)[None]).to(self.device)
        if self.half:
            x = x.half()
        with torch.no_grad():
            out = self.model(pixel_values=x, output_attentions=True)
        tokens = out.last_hidden_state[0].float()           # (1 + 256, 384)
        g = IMG // 14
        patches = tokens[1:1 + g * g].reshape(g, g, -1)
        attn = out.attentions[-1][0].float()                 # (heads, N, N)
        cls = attn[:, 0, 1:1 + g * g].mean(0).reshape(g, g)  # CLS -> patch, mean over heads
        if self.device == "cuda":
            torch.cuda.synchronize()
        return patches.cpu().numpy(), cls.cpu().numpy()


class RgbBackend:
    """Debug baseline: patch features = mean colour. NOT a vision transformer."""
    name = "RGB baseline (no DINOv2)"
    has_attention = False

    def features(self, img):
        g = IMG // 14
        patches = img.reshape(g, 14, g, 14, 3).mean(axis=(1, 3))
        return patches.astype(np.float32), np.ones((g, g), np.float32)


# ---------------------------------------------------------------- k-means
def l2n(a, axis=-1):
    return a / (np.linalg.norm(a, axis=axis, keepdims=True) + 1e-8)


def kmeans(x, k, iters=25, seed=0):
    """Cosine k-means with k-means++ init. x: (N, C) L2-normalised."""
    rng = np.random.default_rng(seed)
    c = [x[rng.integers(len(x))]]
    for _ in range(1, k):
        d = 1.0 - np.max(x @ np.stack(c).T, axis=1)
        d = np.clip(d, 0, None) + 1e-9
        c.append(x[rng.choice(len(x), p=d / d.sum())])
    c = np.stack(c)
    for _ in range(iters):
        lab = np.argmax(x @ c.T, axis=1)
        for j in range(k):
            m = x[lab == j]
            if len(m):
                c[j] = m.mean(0)
        c = l2n(c)
    return np.argmax(x @ c.T, axis=1), c


def match_to_previous(cent, prev):
    """Our 'stable colours' addition: reorder clusters so they best match the previous probe."""
    cost = -(cent @ prev.T)
    try:
        from scipy.optimize import linear_sum_assignment
        rows, cols = linear_sum_assignment(cost)
        perm = np.empty(len(cent), int)
        perm[cols] = rows          # new slot `col` takes old cluster `row`
        return perm
    except ImportError:            # greedy fallback
        perm, used = np.full(len(cent), -1), set()
        for col in range(len(prev)):
            order = np.argsort(cost[:, col])
            row = next(r for r in order if r not in used)
            perm[col] = row
            used.add(row)
        return perm


# ---------------------------------------------------------------- probe
class Prober:
    def __init__(self, backend, k=8, match=True):
        self.backend, self.k, self.match = backend, k, match
        self.prev = None
        self.lock = threading.Lock()

    def probe(self, png_bytes):
        t = {}
        t0 = time.perf_counter()
        img = Image.open(io.BytesIO(png_bytes)).convert("RGB").resize((IMG, IMG), Image.BILINEAR)
        img = np.asarray(img, dtype=np.float32) / 255.0
        t["decode"] = time.perf_counter() - t0

        t0 = time.perf_counter()
        feats, cls = self.backend.features(img)       # (16,16,C), (16,16)
        t["encoder"] = time.perf_counter() - t0

        t0 = time.perf_counter()
        g = feats.shape[0]
        x = l2n(feats.reshape(g * g, -1))
        lab, cent = kmeans(x, self.k)
        # paper behaviour: order clusters by their mean image row (top to bottom)
        rows = np.arange(g * g) // g
        order = np.argsort([rows[lab == j].mean() if np.any(lab == j) else 1e9 for j in range(self.k)])
        if self.match and self.prev is not None and self.prev.shape == cent.shape:
            order = match_to_previous(cent, self.prev)
        cent = cent[order]
        self.prev = cent.copy()
        t["kmeans"] = time.perf_counter() - t0

        t0 = time.perf_counter()
        # simple stand-in for FeatUp: bilinear upsample of the features, then nearest centroid
        up =np.stack([np.asarray(Image.fromarray(feats[:, :, c]).resize((OUT, OUT), Image.BILINEAR))
                       for c in range(feats.shape[2])], axis=-1)
        labels = np.argmax(l2n(up) @ cent.T, axis=-1).astype(np.uint8)   # (OUT, OUT)
        t["upsample"] = time.perf_counter() - t0

        patch_lab = np.argmax(x @ cent.T, axis=1)
        flat = cls.reshape(-1)
        attn = np.array([flat[patch_lab == j].mean() if np.any(patch_lab == j) else 0.0 for j in range(self.k)])
        attn = attn / (attn.max() + 1e-8)
        share = np.array([np.mean(patch_lab == j) for j in range(self.k)])
        return {
            "backend": self.backend.name,
            "has_attention": self.backend.has_attention,
            "matched_colors": self.match,
            "k": self.k, "w": OUT, "h": OUT,
            "labels_b64": base64.b64encode(labels.tobytes()).decode(),
            "attn": [round(float(a), 4) for a in attn],
            "share": [round(float(s), 4) for s in share],
            "timing_ms": {k: round(v * 1000, 1) for k, v in t.items()},
        }


def make_handler(prober):
    class H(BaseHTTPRequestHandler):
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
    return H


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--backend", choices=["dinov2", "rgb"], default="dinov2")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--k", type=int, default=8)
    ap.add_argument("--no-match", action="store_true", help="paper behaviour, no colour matching between probes")
    ap.add_argument("--random-weights", action="store_true", help="test only: DINOv2 architecture with random weights")
    a = ap.parse_args()
    backend = Dinov2Backend(random_weights=a.random_weights) if a.backend == "dinov2" else RgbBackend()
    prober = Prober(backend, k=a.k, match=not a.no_match)
    print(f"See/Saw sidecar ready: {backend.name} on http://127.0.0.1:{a.port}  (K={a.k}, matching={'on' if prober.match else 'off'})")
    ThreadingHTTPServer(("127.0.0.1", a.port), make_handler(prober)).serve_forever()


if __name__ == "__main__":
    main()
