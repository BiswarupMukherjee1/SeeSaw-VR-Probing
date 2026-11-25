## In-world text panel (works in VR, where a 2D HUD would not be visible).
## Mounted on the left controller on the Quest, floating in front of the camera on the desktop.
class_name HudPanel
extends Label3D

const HELP_XR := "Trigger: probe  ·  A: overlay  ·  B: HUD"
const HELP_DESKTOP := "SPACE probe · WASD move · O overlay · H HUD"

var _xr := false


func setup(is_xr: bool) -> void:
	_xr = is_xr
	font_size = 32
	pixel_size = 0.0005 if is_xr else 0.0011
	outline_size = 10
	outline_modulate = Color(0, 0, 0, 0.9)
	no_depth_test = true
	render_priority = 10
	double_sided = true
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	show_state({}, 0, 0.0, 0.0, "Aim and probe.")


func show_state(last: Dictionary, probe_count: int, capture_ms: float, roundtrip_ms: float, status: String) -> void:
	var t := "See/Saw XR\n"
	if last.is_empty():
		t += "Backend: (no probe yet)\n"
	else:
		var tm: Dictionary = last.get("timing_ms", {})
		t += "%s\n" % last.get("backend", "?")
		t += "Probe #%d  K=%d  colour match: %s\n" % [probe_count, int(last.get("k", 8)),
				"on" if last.get("matched_colors", false) else "off"]
		t += "Total %.0f ms = capture %.0f + net %.0f\n" % [capture_ms + roundtrip_ms, capture_ms, roundtrip_ms]
		t += "encoder %.0f · kmeans %.0f · upsample %.0f ms\n" % [tm.get("encoder", 0.0), tm.get("kmeans", 0.0), tm.get("upsample", 0.0)]
	t += status + "\n"
	t += HELP_XR if _xr else HELP_DESKTOP
	text = t
