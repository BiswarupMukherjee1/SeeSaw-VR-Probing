# See/Saw XR (Quest 3 + desktop fallback)

Modular version of the [desktop prototype](../docs/desktop-prototype.md). The same app runs on the
Meta Quest 3 (OpenXR) and, when no headset is found, on the desktop with mouse and keyboard.

```
seesaw_xr/
  godot/                 Godot 4.7 project
    scripts/
      main.gd            wires the modules together
      xr_rig.gd          player: Quest controllers or desktop camera, "where am I aiming"
      probe_client.gd    capture the aimed view, call the sidecar, measure capture + network time
      overlay_painter.gd paint the returned groups onto the 3D scene
      hud_panel.gd       in-world status/latency text (readable in VR)
      server_config.gd   sidecar address (config/server.json, override user://server.json)
      room_builder.gd    built-in demo room
    shaders/probe_overlay.gdshader
    config/server.json   host/port of the sidecar (the deploy script writes this)
    export_presets.cfg   preset "MetaQuest" (OpenXR, arm64, internet permission)
  sidecar/               Python: DINOv2 + k-means service
    seesaw_sidecar/      backends.py  clustering.py  prober.py  http_server.py  __main__.py
    run_sidecar.ps1      starts it with all caches inside the project folder
  deploy/
    deploy_quest.ps1     Windows: write IP -> export APK -> adb install -> launch
    deploy_quest.sh      Linux: same thing
```

## 1. Start the sidecar

Create a Python 3.10+ virtual environment and install `sidecar/requirements.txt` (for an NVIDIA GPU install the
CUDA build of torch, see the comment in that file). Then:

```powershell
cd sidecar
.\run_sidecar.ps1 -Lan          # -Lan = reachable from the headset; leave it out for desktop only
```

Or, on any OS: `python -m seesaw_sidecar --host 0.0.0.0` from the `sidecar/` folder.

It prints `headset server address: 192.168.x.x`. That is the IP you give the deploy script. The first start
downloads `facebook/dinov2-small` from Hugging Face. A quick plumbing test without torch:
`python -m seesaw_sidecar --backend rgb` (or `.\run_sidecar.ps1 -Backend rgb`). The first time, Windows Firewall asks
about `python.exe`: allow **Private networks**.

## 2. Try it on the desktop first

Open `godot/project.godot` in Godot 4.7.2 and press F5 (with the sidecar running).
SPACE or click = probe, WASD = move, right click = mouse look, O = overlay, H = HUD.
Godot prints a harmless "OpenXR failed to start" message on a PC without a headset.

## 3. Put it on the Quest 3

One-time on the headset: Meta Horizon phone app > Developer Mode on. Plug in the USB cable, put the headset on,
accept **Allow USB debugging** (tick "Always allow"). You also need the Godot 4.7.2 Android export templates, the
Android SDK and JDK 17.

```powershell
adb devices                                   # must list the Quest as "device"
cd deploy
$env:GODOT = "path\to\Godot_v4.7.2-stable_win64_console.exe"
.\deploy_quest.ps1 -ServerIp 192.168.x.x      # the address printed by the sidecar
```

The first build downloads Gradle (a few hundred MB) into `.cache\gradle` and takes several minutes.
Later builds are fast. Rebuilding is only needed when code changes; to change just the IP, push a file instead:

```powershell
'{"host":"192.168.1.60","port":8765}' | Set-Content -Encoding ascii server.json
adb push server.json /sdcard/Android/data/com.seesaw.xr/files/server.json
```

The headset and the PC must be on the same network. Some Wi-Fi networks block device-to-device traffic:
if the HUD says "Sidecar not reachable", use a phone hotspot for both. Check from the headset browser:
`http://<ip>:8765/` should show `{"ok": true, ...}`.

Linux: `ANDROID_HOME=... GODOT=/path/to/godot ./deploy/deploy_quest.sh 192.168.x.x`.

### Controls in the headset

| Input | Action |
|---|---|
| Right trigger | probe the view along the laser (capture from the head, centred 3 m along the ray) |
| A | overlay on/off |
| B | HUD on/off (HUD is on the left wrist) |
| Left stick | walk |
| Right stick | turn |

## Status and limitations

* Verified: the scripts load with no errors (headless Godot import and parse, run in CI), a desktop probe works end
  to end with the RGB backend, the PowerShell scripts parse. The DINOv2 pipeline itself is the one validated in the
  desktop prototype.
* **Not verified**: running on the headset, and the first Gradle export.
* The laser is a fixed 3 m aim ray (no collision shapes in the demo room).
* Not implemented yet: comparison lens / second model, FeatUp upsampling (bilinear feature upsampling is used instead),
  mixed reality, and a depth test for the overlay (see the [main README](../README.md#roadmap)).
