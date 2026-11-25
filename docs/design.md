# Design notes: target system and decisions

This document describes the full system the project is aiming at (a Quest VR application with two-model
comparison) and the technical decisions behind it. The code in this repository implements a subset: see the
[status table in the README](../README.md#status). Where the implemented behaviour differs from the target design,
both are described.

## 1. Scope

| Requirement | Target outcome |
|---|---|
| XR query and capture | Headset tracking; controller aim and trigger; 224 x 224 RGB capture from a dedicated capture camera with a frozen pose and projection |
| Frozen DINOv2 ViT-S/14 | L2-normalised patch features, k-means with K = 8, last-layer CLS-to-patch attention |
| FeatUp | Learned (JBU) upsampled features assigned to the nearest patch centroid, giving a 224 x 224 label map |
| Surface visualisation | Discrete group colours, attention as brightness, highlight of the aimed group; frustum-scoped, depth-aware overlay on the scene meshes that also rejects surfaces hidden from the capture camera |
| Stable colours | Match clusters to the last *applied* probe, independently per model |
| Comparison lens | Two models process the same capture: model B inside a hand-held lens, model A outside it, on the same surfaces |
| Latency HUD | Measured per-stage timings and a visible processing state |
| Optional: mixed reality | Needs a real camera image, its pose and room geometry (passthrough alone is not enough); requires a native Quest build |

### Interpreting the result

Colours identify *unsupervised groups*, not fixed object classes. Matching stabilises the visual identity of a
group between probes but cannot guarantee semantic consistency across scenes or large viewpoint changes. Attention
brightness is a read-out of the model, not evidence that the model is right. The reference paper reports
qualitative findings and no completed controlled user study.

## 2. Architecture

```
 Quest 3 / desktop (Godot 4.7)                        Sidecar (Python)
 ┌───────────────────────────────┐                    ┌──────────────────────────────────┐
 │ 1 Aim and capture             │   PNG over HTTP    │ 3 Encode and group               │
 │   square Camera3D → SubViewport├───────────────────▶│   frozen ViT, patch features,    │
 │   save view/projection matrices│                    │   CLS attention, k-means (K=8)   │
 │ 2 Submit asynchronously       │                    │ 4 Upsample and match             │
 │   (UI keeps rendering)        │◀───────────────────┤   labels + attention + timings   │
 │ 5 Paint                       │       JSON         └──────────────────────────────────┘
 │   label texture + saved matrices → overlay shader  │
 └───────────────────────────────┘
```

The central rule: **preserve the view that produced each result.** The label map only makes sense in the camera
that captured it, so the client keeps the capture camera's view/projection matrices and projects scene positions
through *those* matrices, never through the headset's current pose.

### Technical decisions

* **Transport.** HTTP `POST /probe`: simple on both sides. The reference system used ZMQ on a background thread;
  HTTP is an adaptation.
* **Capture camera.** A dedicated square `Camera3D` in a `SubViewport`, not the XR camera, whose projection differs
  per eye. It follows the head pose (the "aimed view"); the controller ray selects the query point inside it.
* **Overlay pass.** A Godot spatial shader chained as `next_pass` after each surface material. It shares the main
  depth buffer, so occlusion in the current view works.
* **Capture-depth rejection.** Projecting the label image like a slide projector paints surfaces that were hidden
  from the capture camera as soon as the user steps sideways. The fix is to render a depth map with the capture
  camera and discard fragments whose capture-space depth is behind it (with a small bias). *Not implemented yet.*
* **Aimed-group highlight.** Client side: project the aim hit point through the saved capture matrices, read its
  label from the cluster map, pass the id to the shader. Updates every frame without a new probe.
* **Lens.** World-space disc held by the controller. For each fragment, intersect the eye-to-fragment ray with the
  lens plane; inside the radius use model B, otherwise model A. A screen-space circle would not line up between the
  two eyes. *Not implemented yet.*
* **Label textures.** 8-bit, nearest sampling (the value is read as 0..1, so multiply by 255 and round in the
  shader); labels 0..7 index a shared palette; brightness is modulated by group attention; positions outside the
  recorded frustum are rejected with a soft edge feather.
* **Request policy.** One probe in flight; show "busy" and keep the previous valid overlay; discard mismatched,
  expired or late results; every response binds to its saved capture. Matching history is per session and per
  model, and is advanced only by results the client actually applied.

## 3. The `/probe` API

### Implemented (current)

`GET /` returns `{"ok": true, "backend": ...}`. `POST /probe` takes the raw PNG as the request body and returns:

```json
{
  "backend": "DINOv2 ViT-S/14", "has_attention": true, "matched_colors": true,
  "k": 8, "w": 112, "h": 112,
  "labels_b64": "<w*h bytes, one cluster id per pixel, base64>",
  "attn": [0.0, "... 8 values, 0..1, per-cluster mean CLS attention"],
  "share": ["... 8 values: fraction of patches per cluster"],
  "timing_ms": {"decode": 0, "encoder": 0, "kmeans": 0, "upsample": 0, "server_total": 0}
}
```

### Target (version 1 of the full system)

* Request: `multipart/form-data` with `image` (PNG, RGB, 224 x 224) and `metadata` (JSON: `schema_version`,
  unique `probe_id`, `session_id`, requested `models`, `match_against`, `reset_history`; K fixed to 8).
* Response: `probe_id` echoed unchanged, one entry per model (`model_id`, 224 x 224 grayscale PNG whose pixel values
  are cluster ids 0..7, `attention[8]`, per-stage `timings_ms`), `server_total_ms`, or on failure an error code and
  message with no partial paired overlay.
* **`match_against`**: a map of model id to the `probe_id` of the last result the *client applied*. The server
  matches new centroids against that probe's centroids (it keeps the last ~10 per session and model), never against
  its own latest output. Why: if the server stored every result as "previous" and the client then discarded a late
  result, the next probe would be matched to colours the user never saw, and stable colours would break exactly when
  the system is slow.
* Conventions: top-left image origin, x right, y down; HTTP 400 for invalid input, 503 for unavailable models,
  500 for processing errors; explicit client timeout; on timeout keep the previous overlay and allow retry.
* Timing: report client end-to-end time separately from backend stage times, and synchronise GPU work before
  reporting a stage time.

## 4. Choice of the second model (lens)

FeatUp's pretrained JBU upsamplers exist only for `dinov2` (ViT-S/14), `dino16`, `clip`, `maskclip`, `vit` and
`resnet50`. There is no pretrained upsampler for DINOv2 ViT-B/14, which rules out the obvious "same family, bigger
model" choice if FeatUp is to be used for both models.

| Option | Pretrained FeatUp | For | Against |
|---|---|---|---|
| CLIP | yes | Language-supervised vs self-supervised should show visible disagreement | Last-layer CLS attention is noisier and less object-centred |
| MaskCLIP | yes (unnormed only) | Better-localised dense features than plain CLIP | Not a standard ViT forward pass, so attention is not directly comparable |
| DINO v1 (`dino16`) | yes | Same size and idea, different generation; clean attention maps | Differences from DINOv2 may be subtle |
| Supervised ViT | yes | Self-supervised vs ImageNet-supervised is an easy contrast to explain | Not the comparison the reference paper names |
| DINOv2 ViT-B/14 | none | Same family, easy to load | Bilinear upsampling only; likely close to ViT-S, so a weak lens demo |

ResNet-50 is excluded: it has no CLS token, so there is no attention channel. The sidecar already isolates a model
behind a small interface (`backends.py`: `features(img)` returns patch features and CLS attention), so adding model
B means writing one more backend class.

## 5. Acceptance criteria for the full system

| ID | Test | Pass condition |
|---|---|---|
| A1 | VR startup | Stereo renders correctly; headset and both controllers tracked |
| A2 | Probe and pose | Aim and trigger capture the intended view; a result arriving after the user moved still uses the saved capture matrices |
| A3 | Real model and grouping | Frozen DINOv2 gives features, eight-group labels and per-group attention; no mock output in release mode |
| A4 | FeatUp | Pixel labels derive from FeatUp features and nearest centroids; execution path (CUDA kernel or fallback) recorded |
| A5 | Overlay channels | Discrete colours; brightness reflects attention; aimed group highlighted; colours stay on the right surfaces |
| A6 | Frustum and occlusion | No paint outside the capture bounds or on surfaces hidden from the capture camera, including after a sideways step |
| A7 | Stable colours | Nearby probes keep group ids; a discarded late result does not change the next probe's colours; reset works |
| A8 | Comparison lens | Two distinct real models use the same capture; B inside and A outside the lens, aligned in both eyes |
| A9 | HUD and measurement | Every completed probe shows per-stage and total times with units, model identity and status |
| A10 | Responsiveness | Rendering and input continue during slow inference; frame rate recorded |
| A11 | Reliability | Repeated triggers, invalid or late results and a backend disconnect neither crash nor apply stale results; retry works |
| A12 | Reproduction | The README is enough to run backend and headset demo from a clean checkout |

Repeatability protocol: a static reference view, nearby viewpoint changes and an occluder reveal; ten consecutive
probes and one disconnect/reconnect cycle; log the cold start separately and report the warm median and range per
model and for the FeatUp stage.

## 6. Optional extension: probing the headset camera feed

Read a frame from the Quest passthrough camera, resize to 224 x 224, send it to the unchanged `/probe` API and show
the returned groups next to the frame (stage 1, no room geometry needed). Painting the result onto the physical room
(stage 2) additionally needs camera calibration, a timestamp-matched pose and a room mesh, which is a much larger
piece of work. Both need a native Quest build, because camera access is not available over a PC link.
