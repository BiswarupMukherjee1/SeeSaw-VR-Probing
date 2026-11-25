# See/Saw VR Probing

[![CI](https://github.com/BiswarupMukherjee1/SeeSaw-VR-Probing/actions/workflows/ci.yml/badge.svg)](https://github.com/BiswarupMukherjee1/SeeSaw-VR-Probing/actions/workflows/ci.yml)

**Look inside a Vision Transformer from within a 3D scene.** Aim a controller (or the mouse), press a button, and a
frozen **DINOv2 ViT-S/14** tells you how it *groups* what you are looking at. The groups are painted back onto the
3D surfaces, coloured by cluster and shaded by the model's attention. Walk to a different spot and probe again to see
which groupings survive a change of viewpoint.

The project is a from-scratch re-implementation of the core loop of *See/Saw: Embodied Probing of Vision Transformer
Attention in Virtual Reality* (Xie and Lin, SIGGRAPH Posters 2026), built with **Godot 4.7**, **OpenXR (Meta Quest 3)**
and a **Python inference sidecar**. It was developed for the Augmented and Virtual Reality course at the University
of Bordeaux. This repository is an independent re-implementation and is not affiliated with the paper's authors.

## What it does

1. **Capture.** A dedicated square off-screen camera renders the aimed view (224 x 224 model input); the overlay is
   switched off during capture so the model sees the clean scene.
2. **Infer.** The PNG goes over HTTP to a Python sidecar, which runs DINOv2 ViT-S/14 and extracts a 16 x 16 grid of
   patch features and the last-layer CLS-to-patch attention.
3. **Group.** Patch features are L2-normalised and clustered with cosine k-means (K = 8, k-means++ initialisation,
   implemented in NumPy). Clusters are matched to the previous probe with the Hungarian algorithm so a group keeps
   its colour between probes.
4. **Paint.** The sidecar returns a label map plus per-group attention. A Godot spatial shader, chained onto every
   mesh material, projects each fragment's world position into the *capture camera* and looks up its label:
   **colour = group, brightness = mean attention, highlighted = the group under the reticle**. Because the paint is
   anchored to the capture camera's saved matrices, it stays on the geometry while you walk around.
5. **Measure.** Every probe reports its stage timings (capture, network round trip, encoder, k-means, upsample) in an
   in-world HUD (a 3D label, so it also works inside a headset).

## Status

| Part | State |
|---|---|
| Godot scene, aiming, square frustum capture | Done and tested on the desktop; the OpenXR rig is written but untested on a device |
| Python sidecar: DINOv2 + attention + cosine k-means over HTTP | Done, runs on CPU or CUDA |
| Overlay reprojection shader (colour, attention brightness, aimed-group highlight, frustum feather) | Done |
| Stable colours between probes (Hungarian matching) | Done, on by default (`--no-match` gives the paper's behaviour) |
| Latency HUD with per-stage timings | Done |
| Modular XR version, Quest export preset, deploy scripts, CI | Done |
| Running on a physical Quest 3 | **Not verified yet**: the headset build is scripted but untested on a device |
| FeatUp upsampling | Not yet: bilinear feature upsampling is used as a stand-in |
| Depth test against the capture view (don't paint hidden surfaces) | Not yet |
| Comparison lens with a second model | Designed, not built (see [docs/design.md](docs/design.md)) |
| Mixed reality / headset camera feed | Not started |

## Architecture

```
 Godot 4.7 client (desktop or Quest 3)                 Python sidecar
 ┌────────────────────────────────────┐   PNG / HTTP   ┌───────────────────────────────────┐
 │ XRRig        aim + input           │ ─────────────▶ │ http_server   POST /probe         │
 │ ProbeClient  capture, send, timing │                │ Prober        decode, k-means,    │
 │ OverlayPainter  label texture +    │ ◀───────────── │               colour matching     │
 │              saved capture matrix  │      JSON      │ backends      DINOv2 | RGB baseline│
 │ probe_overlay.gdshader             │                │ clustering    cosine k-means,     │
 │ HudPanel     in-world latency HUD  │                │               Hungarian matching  │
 └────────────────────────────────────┘                └───────────────────────────────────┘
```

Design points worth knowing:

* **The client keeps the capture camera's view and projection matrices** and projects scene positions through them,
  never through the headset's current pose, so a result that arrives after the user has moved still lands on the
  right surfaces.
* **The model is behind a one-method interface** (`features(img)` returns patch features and CLS attention), so a
  second model for the comparison lens is one more backend class.
* **A RGB-colour baseline backend** lets the whole client/server/shader path be tested without torch or a GPU.
* **Desktop fallback.** The same Godot project runs with mouse and keyboard when no headset is found, which keeps
  development and CI independent of hardware.

More detail, including the target design (comparison lens, capture-depth rejection, the versioned `/probe` API) and
the acceptance criteria, is in [docs/design.md](docs/design.md).

## Repository layout

```
godot/                  Desktop prototype: Godot project (scene, reticle aim, overlay shader)
sidecar/                Desktop prototype: single-file DINOv2 + k-means server (server.py)
seesaw_xr/              Modular Quest 3 (OpenXR) version with desktop fallback
  godot/                  XR rig, probe client, overlay painter, HUD, export preset
  sidecar/                Packaged sidecar (backends, clustering, prober, HTTP server)
  deploy/                 Build the APK and install it on the headset (PowerShell and bash)
docs/
  desktop-prototype.md    Controls and usage of the desktop prototype
  design.md               Target system, decisions, API and acceptance criteria
.github/                CI (repo checks, sidecar checks, headless Godot import and GDScript parse), release workflow
```

### Branches

| Branch | Contents |
|---|---|
| `main` | Everything above: both versions, docs and CI |
| `desktop-demo` | The first working desktop prototype, as originally committed |
| `openxr-quest` | The modular Quest 3 / OpenXR version, as originally committed |

## Quick start (desktop, no headset)

Requirements: Python 3.10+, [Godot 4.7.2](https://godotengine.org/) (standard build). An NVIDIA GPU is optional.

```bash
# 1. sidecar
cd seesaw_xr/sidecar
python -m venv .venv && source .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python -m seesaw_sidecar                               # downloads facebook/dinov2-small (~90 MB) on first run
#   python -m seesaw_sidecar --backend rgb              # plumbing test, no torch needed
#   python -m seesaw_sidecar --host 0.0.0.0             # let a Quest on the same network reach it

# 2. client: open seesaw_xr/godot/project.godot in Godot 4.7.2 and press F5
```

Desktop controls: **SPACE / click** probe, **WASD** move, **right click** mouse look, **O** overlay on/off, **H** HUD.
To run on a Quest 3 (developer mode, APK export, `adb` install) see [seesaw_xr/README.md](seesaw_xr/README.md).

## Roadmap

1. Verify the Quest 3 build on a device and measure real end-to-end latency.
2. FeatUp (learned feature upsampling) instead of bilinear upsampling.
3. Capture-depth rejection so surfaces hidden from the capture camera stay unpainted.
4. The comparison lens: a hand-held, world-space lens that shows a second model's grouping of the same capture.
5. Optional: apply the same analysis to the headset camera feed.

## Limitations

* The overlay is projected like a slide projector: a surface hidden behind another object, as seen from the capture
  camera, still receives paint until the depth test (roadmap item 3) exists.
* Colours are unsupervised groups, not object classes. Colour matching stabilises their identity between nearby
  probes but cannot promise semantic consistency across large viewpoint changes or different scenes.
* Attention brightness is a read-out of the model, not evidence that the model is right.
* A CPU-only sidecar makes a probe take seconds; that is part of what the latency HUD is for.

## References

* Z. Xie and S. Lin, *See/Saw: Embodied Probing of Vision Transformer Attention in Virtual Reality*, ACM SIGGRAPH
  2026 Posters. DOI [10.1145/3799825.3818748](https://doi.org/10.1145/3799825.3818748).
* M. Oquab et al., *DINOv2: Learning Robust Visual Features without Supervision* (model loaded from Hugging Face,
  `facebook/dinov2-small`).
* S. Fu et al., *FeatUp: A Model-Agnostic Framework for Features at Any Resolution* (planned upsampler).
