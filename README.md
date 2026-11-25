# See/Saw PoC (first prototype)

A small working re-implementation of the core loop of **See/Saw** (Xie & Lin, SIGGRAPH Posters 2026),
built with **Godot 4** plus a **Python sidecar** that runs a frozen **DINOv2 ViT-S/14**.

Aim at something, press **SPACE**. Godot captures the view inside the white square, sends it to the
sidecar, and paints the returned groups back onto the 3D surfaces:

* **color** = k-means group of the DINOv2 patch features (K = 8)
* **brightness** = that group's mean CLS-to-patch attention (last layer)
* the group under the reticle is highlighted, the others are dimmed

Then walk around (WASD): the paint stays on the geometry where the probe saw it. Probe again from
another place to re-tokenize the scene and compare.

## What is in this version

| Part | Status |
|---|---|
| Godot scene, reticle aim, square frustum capture | done (desktop, mouse and keyboard) |
| Sidecar round trip: DINOv2 + k-means + attention | done |
| Overlay reprojection shader (paint on meshes) | done |
| Stable colors (match clusters between probes) | first version, on by default |
| Latency HUD (capture, round trip, encoder, k-means, upsample) | first version |
| FeatUp upsampling | not yet: bilinear feature upsampling as a stand-in |
| Comparison lens (second model) | planned |
| Meta Quest 3 / OpenXR, mixed reality | planned |

## 1. Start the sidecar (Python 3.10+)

```bash
cd sidecar
python -m venv .venv
# Windows: .venv\Scripts\activate      macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
python server.py
```

The first start downloads `facebook/dinov2-small` (about 90 MB) from Hugging Face. It uses an NVIDIA GPU
automatically if PyTorch sees one, otherwise the CPU (slower, still fine for a demo).

Options:

* `python server.py --no-match` : paper behaviour, colors are reassigned every probe
* `python server.py --backend rgb` : debug only, k-means on plain colors, no DINOv2 (do not use for screenshots of results)
* `python server.py --k 6` : another number of groups

## 2. Run the Godot project (Godot 4.3 or newer)

Open Godot, **Import**, select `godot/project.godot`, then press **F5**.

| Key | Action |
|---|---|
| SPACE, E or left click | probe the view inside the white square |
| W A S D (+ Shift) | move |
| right click | toggle mouse look (arrow keys also turn) |
| O | overlay on/off |
| H | hide the HUD (clean screenshot) |
| F12 | save a screenshot (path is shown in the HUD) |

## Getting a screenshot for the slides

1. Start the sidecar, run the project, press SPACE.
2. Take one screenshot with the HUD (shows backend and latency) and one with **H** (clean).
3. Walk sideways, probe again, take a second shot: two viewpoints side by side show the idea.

## Using a real scene

Put a `.glb` file at `godot/assets/scene.glb` (for example a CC-BY Sketchfab scene, credit it on the slide).
The project loads it instead of the built-in primitive room and adds the overlay to all its meshes.

## How it works

```
Godot (main.gd)                                   Python (sidecar/server.py)
 aim + SPACE
 SubViewport camera renders the aimed view  --PNG-->  resize 224x224, DINOv2 ViT-S/14
 (overlay switched off during capture)               16x16 patch features + CLS attention
                                                     cosine k-means, K = 8
                                                     match colors to previous probe
                                                     bilinear upsample -> 112x112 label map
 overlay shader (next_pass on every material) <--JSON--  labels, attention per group, timings
 world position -> capture camera projection
 -> label -> color, attention -> brightness
```

## Known limitations

* The overlay is projected like a slide projector: a surface hidden behind another object, as seen
  from the capture camera, still receives paint. A depth test against the capture view would fix it.
* Software rendering or a CPU-only sidecar makes probes slow (seconds). That is part of what the
  latency HUD is for.
* Desktop only for now; the OpenXR (Quest 3) version is the next step.
