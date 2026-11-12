// 路灯地面光斑：代替实时点光源（Web 端省性能），按像素网格分级。
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform float pw_night_factor;

uniform vec4 light_color : source_color = vec4(1.0, 0.788, 0.396, 1.0);
uniform float intensity = 0.45;
uniform float size_m = 5.0;
uniform float texel_density = 16.0;
uniform float bands = 4.0;

void fragment() {
	vec2 cells = vec2(size_m * texel_density);
	vec2 uv = (floor(UV * cells) + 0.5) / cells;
	float f = clamp(1.0 - length(uv - 0.5) * 2.0, 0.0, 1.0);
	f = f * f;
	f = floor(f * bands + 0.5) / bands;
	ALBEDO = light_color.rgb * f * intensity * pw_night_factor;
}
