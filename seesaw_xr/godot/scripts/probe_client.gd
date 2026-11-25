## Captures the aimed view with a square off-screen camera and sends it to the sidecar.
## Emits `finished` with the JSON answer, or `failed` with a short message.
class_name ProbeClient
extends Node

signal finished(result: Dictionary, capture_vp: Projection, timing: Dictionary)
signal failed(message: String)

const CAPTURE_SIZE := 448

var busy := false

var _painter: OverlayPainter
var _vp: SubViewport
var _cam: Camera3D
var _http: HTTPRequest
var _pending_vp: Projection
var _t_send := 0
var _capture_ms := 0.0


func setup(painter: OverlayPainter) -> void:
	_painter = painter


func _ready() -> void:
	# square capture camera = the probe "frustum"; it shares the main 3D world
	_vp = SubViewport.new()
	_vp.size = Vector2i(CAPTURE_SIZE, CAPTURE_SIZE)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_cam = Camera3D.new()
	_vp.add_child(_cam)
	_cam.current = true
	_http = HTTPRequest.new()
	_http.timeout = 60.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func probe(view: Transform3D, fov: float) -> void:
	if busy:
		return
	busy = true
	var t0 := Time.get_ticks_usec()
	_cam.global_transform = view
	_cam.fov = fov
	_painter.set_capturing(true)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	_pending_vp = _cam.get_camera_projection() * Projection(_cam.global_transform.affine_inverse())
	_painter.set_capturing(false)
	_capture_ms = (Time.get_ticks_usec() - t0) / 1000.0

	_t_send = Time.get_ticks_usec()
	var err := _http.request_raw(ServerConfig.probe_url(), PackedStringArray(["Content-Type: image/png"]),
			HTTPClient.METHOD_POST, img.save_png_to_buffer())
	if err != OK:
		busy = false
		failed.emit("Could not send the request (error %d)." % err)


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	var roundtrip_ms := (Time.get_ticks_usec() - _t_send) / 1000.0
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		failed.emit("Sidecar not reachable at %s" % ServerConfig.probe_url())
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not d is Dictionary:
		failed.emit("Sidecar sent an unreadable answer.")
		return
	finished.emit(d, _pending_vp, {"capture_ms": _capture_ms, "roundtrip_ms": roundtrip_ms})
