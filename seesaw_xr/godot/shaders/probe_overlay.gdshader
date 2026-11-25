// See/Saw style overlay pass.
// Used as `next_pass` on every mesh material: it re-draws each surface once more and
// paints the cluster label that the capture camera saw at that world position.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform bool enabled = false;
uniform mat4 capture_vp;                       // projection * view of the capture camera
uniform sampler2D labels : filter_nearest, repeat_disable;  // R8, value = cluster id
uniform vec4 palette[8];
uniform float attn[8];                         // per-cluster mean CLS attention, 0..1
uniform int highlight = -1;                    // cluster under the reticle
uniform float opacity = 0.72;
uniform float feather = 0.04;                  // soft edge at the frustum border

varying vec3 world_pos;

void vertex() {
	VERTEX += NORMAL * 0.003;                  // tiny push to avoid z-fighting with the surface
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (!enabled) {
		discard;
	}
	vec4 clip = capture_vp * vec4(world_pos, 1.0);
	if (clip.w <= 0.0) {
		discard;                               // behind the capture camera
	}
	vec2 ndc = clip.xy / clip.w;
	if (abs(ndc.x) > 1.0 || abs(ndc.y) > 1.0) {
		discard;                               // outside the capture frustum
	}
	vec2 uv = vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
	int id = clamp(int(round(texture(labels, uv).r * 255.0)), 0, 7);

	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float fade = smoothstep(0.0, feather, edge);

	float brightness = mix(0.35, 1.0, attn[id]);   // intensity channel = attention
	float a = opacity * fade;
	if (highlight >= 0 && id != highlight) {
		a *= 0.55;                              // the aimed group stands out
	}
	ALBEDO = palette[id].rgb * brightness;
	ALPHA = a;
}
