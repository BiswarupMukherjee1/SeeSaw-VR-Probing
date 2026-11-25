"""One probe = decode PNG -> backend features -> k-means -> upsampled label map + timings."""
import base64
import io
import threading
import time

import numpy as np
from PIL import Image

from .clustering import kmeans, l2n, match_to_previous
from .constants import GRID, IMG, OUT


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
        # stand-in for FeatUp: bilinear upsample of the features, then nearest centroid
        up = np.stack([np.asarray(Image.fromarray(feats[:, :, c]).resize((OUT, OUT), Image.BILINEAR))
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
