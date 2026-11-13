// 路灯地面光斑：代替实时点光源（Web 端省性能）。
// 平滑渐变：中心最亮，向外按平方反比衰减并在边缘柔和地归零；不分档，没有一圈圈的台阶。
// 叠加一点极轻的随机抖动，避免 8 位颜色在大面积暗部渐变里出现色带。
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform float pw_night_factor;

uniform vec4 light_color : source_color = vec4(1.0, 0.788, 0.396, 1.0);
uniform float intensity = 0.55;
// 光斑中心「热点」的大小（越小越集中）
uniform float falloff = 0.35;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;          // 0 = 中心，1 = 边缘
	float att = 1.0 / (1.0 + (d * d) / (falloff * falloff));  // 平方反比，中心不爆亮
	float edge = 1.0 - smoothstep(0.55, 1.0, d);                // 边缘平滑归零，不出现方形 / 圆形硬边
	float f = att * edge;
	f += (hash12(FRAGCOORD.xy) - 0.5) / 255.0;                  // 抖动消色带
	ALBEDO = light_color.rgb * max(f, 0.0) * intensity * pw_night_factor;
}
