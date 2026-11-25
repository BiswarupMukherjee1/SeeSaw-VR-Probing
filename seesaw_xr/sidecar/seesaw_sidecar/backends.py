"""Vision backends. Each one turns a 224x224 image into (patch features 16x16xC, CLS attention 16x16).

To add the second model for the comparison lens: write another class with the same
`features(img)` method, and register it in BACKENDS.
"""
import numpy as np

from .constants import GRID, IMG

IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
IMAGENET_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)


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
        """img: float32 HxWx3 in [0,1], 224x224."""
        torch = self.torch
        x = (img - IMAGENET_MEAN) / IMAGENET_STD
        x = torch.from_numpy(x.transpose(2, 0, 1)[None]).to(self.device)
        if self.half:
            x = x.half()
        with torch.no_grad():
            out = self.model(pixel_values=x, output_attentions=True)
        tokens = out.last_hidden_state[0].float()                 # (1 + 256, 384)
        patches = tokens[1:1 + GRID * GRID].reshape(GRID, GRID, -1)
        attn = out.attentions[-1][0].float()                       # (heads, N, N)
        cls = attn[:, 0, 1:1 + GRID * GRID].mean(0).reshape(GRID, GRID)   # CLS -> patch, mean over heads
        if self.device == "cuda":
            torch.cuda.synchronize()
        return patches.cpu().numpy(), cls.cpu().numpy()


class RgbBackend:
    """Debug baseline: patch features = mean colour. NOT a vision transformer."""
    name = "RGB baseline (no DINOv2)"
    has_attention = False

    def features(self, img):
        patches = img.reshape(GRID, 14, GRID, 14, 3).mean(axis=(1, 3))
        return patches.astype(np.float32), np.ones((GRID, GRID), np.float32)


BACKENDS = {"dinov2": Dinov2Backend, "rgb": RgbBackend}


def create_backend(name, random_weights=False):
    if name == "dinov2":
        return Dinov2Backend(random_weights=random_weights)
    return BACKENDS[name]()
