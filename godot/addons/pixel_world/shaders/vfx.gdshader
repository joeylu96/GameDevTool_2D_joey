// 动作特效通用材质：自发光、不受光照，按生命进度 progress（0..1）做出现 / 消散。
// mode：0 = 实心（火球、爆炸、闪光、护盾），1 = 横扫弧（斩击，按 UV.x 从起点扫到终点），
//       2 = 圆环（冲击波，UV.y 横向，中心亮两侧暗），3 = 法阵（极坐标符文圈，缓慢旋转），
//       4 = 光柱（底部亮、往上渐隐，边缘比中间亮，带上升的竖条纹）
// 混合用预乘 alpha：cover = 0 时是纯叠加发光，cover = 1 时完全盖住背后——白天亮背景下也能看出火焰的颜色，
// 不会一片白。rim = 1 时中间透明、只有边缘亮（护盾泡泡），rim = 0 时中间最实（火球）。
// 消散时按像素格子随机溶解，透明度分几档，和整体像素风格一致。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color_core : source_color = vec4(1.0, 0.95, 0.75, 1.0);
uniform vec4 color_edge : source_color = vec4(1.0, 0.55, 0.2, 1.0);
uniform float progress = 0.0;
uniform float intensity = 1.0;
uniform int mode = 0;
uniform float bands = 5.0;
uniform float opacity = 1.0;
uniform float cover = 0.35;
uniform float rim = 0.0;
uniform float grain = 24.0;  // 溶解格子密度（每单位 UV 多少格）

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float a = 1.0;
	float core = 0.0;
	if (mode == 1) {
		// 斩击：扫过的位置 head 从 0 走到 1.35，后面拖一条渐隐的尾巴；UV.y 是刀光宽度方向
		// 前 55% 的时间扫完整条弧，之后整条月牙停留、从尾部溶解消散
		float head = progress * 1.8;
		float behind = head - UV.x;
		a = step(0.0, behind) * (1.0 - smoothstep(0.3, 1.1, behind));
		a *= 1.0 - smoothstep(0.75, 1.0, progress);
		float w = 1.0 - abs(UV.y - 0.5) * 2.0;
		// 刀刃一侧（UV.y 大）是亮白的锋线，另一侧渐隐成颜色
		float edge = smoothstep(0.55, 0.95, UV.y);
		core = edge * (1.0 - smoothstep(0.0, 0.3, behind));
		a *= smoothstep(0.0, 0.25, w) * mix(0.55, 1.0, edge);
		// 尾巴按格子溶解
		a *= step(smoothstep(0.35, 1.0, behind) * 0.9, hash(floor(UV * vec2(grain * 2.0, 6.0))));
	} else if (mode == 2) {
		float w = 1.0 - abs(UV.y - 0.5) * 2.0;
		a = smoothstep(0.0, 0.8, w) * (1.0 - progress);
		a *= step(progress * 0.8, hash(floor(UV * vec2(grain * 3.0, 3.0))));
		core = smoothstep(0.7, 1.0, w);
	} else if (mode == 3) {
		vec2 c = UV - 0.5;
		float r = length(c) * 2.0;
		float ang = atan(c.y, c.x) + progress * 3.0;
		float ring1 = 1.0 - smoothstep(0.0, 0.035, abs(r - 0.92));
		float ring2 = 1.0 - smoothstep(0.0, 0.025, abs(r - 0.7));
		// 两圈之间的符文带：一圈分成 24 格，随机点亮其中一部分，每格内部再留一点空隙
		float seg = ang / 6.28318 * 24.0;
		float runes = step(0.45, hash(vec2(floor(seg), 3.0))) * step(0.2, fract(seg)) * step(fract(seg), 0.8)
			* step(0.75, r) * step(r, 0.87);
		// 内圈的五角星：五条边，取到最近一条边的距离
		float star = 0.0;
		for (int k = 0; k < 5; k++) {
			float a0 = float(k) * 2.51327 + progress * 3.0;
			vec2 p0 = vec2(cos(a0), sin(a0)) * 0.35;
			vec2 p1 = vec2(cos(a0 + 2.51327), sin(a0 + 2.51327)) * 0.35;
			vec2 e = p1 - p0;
			float t = clamp(dot(c - p0, e) / dot(e, e), 0.0, 1.0);
			star = max(star, 1.0 - smoothstep(0.0, 0.012, length(c - p0 - e * t)));
		}
		a = max(max(ring1, ring2), max(runes * 0.8, star * 0.7));
		a *= smoothstep(0.0, 0.15, progress) * (1.0 - smoothstep(0.75, 1.0, progress));
		core = ring1;
	} else if (mode == 4) {
		float f = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
		float h = 1.0 - UV.y;  // 圆柱 UV.y：顶部 0、底部 1
		float streak = 0.55 + 0.45 * step(0.5, hash(vec2(floor(UV.x * 32.0), floor(UV.y * 6.0 + progress * 14.0))));
		a = pow(1.0 - h, 1.6) * mix(0.25, 1.0, f) * streak;
		a *= smoothstep(0.0, 0.2, progress) * (1.0 - smoothstep(0.6, 1.0, progress));
		core = f * (1.0 - h);
	} else {
		// 实心：rim 决定是“中间实”（火球）还是“边缘亮”（泡泡）
		float f = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.5);
		core = mix(1.0 - f, f, rim);
		a = mix(mix(1.0, 0.55, f), mix(0.08, 1.0, f), rim);
		// 消散：后半段按像素格子随机溶解，而不是整体变淡
		float fade = smoothstep(0.35, 1.0, progress);
		a *= step(fade, hash(floor(UV * vec2(grain * 2.0, grain))) * 0.95 + 0.02);
	}
	a = clamp(floor(a * opacity * bands + 0.5) / bands, 0.0, 1.0);
	vec3 col = mix(color_edge.rgb, color_core.rgb, clamp(core, 0.0, 1.0));
	ALBEDO = col * a * intensity;
	ALPHA = a * cover;
}
