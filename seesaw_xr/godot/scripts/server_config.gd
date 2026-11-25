## Where the Python sidecar lives.
## 1. res://config/server.json is baked into the build (deploy script writes it from -ServerIp).
## 2. user://server.json overrides it at runtime, so you can change the IP without rebuilding:
##      adb push server.json /sdcard/Android/data/com.seesaw.xr/files/server.json
class_name ServerConfig
extends RefCounted

const BUNDLED := "res://config/server.json"
const OVERRIDE := "user://server.json"


static func load_config() -> Dictionary:
	var cfg := {"host": "127.0.0.1", "port": 8765}
	for path in [BUNDLED, OVERRIDE]:
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				cfg.merge(parsed, true)
	return cfg


static func probe_url() -> String:
	var c := load_config()
	return "http://%s:%d/probe" % [str(c["host"]), int(c["port"])]
