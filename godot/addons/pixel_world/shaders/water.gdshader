// 湖面：按水深从「透明的浅滩」过渡到「不透明的深水」；天空反射、细碎波光、雨滴 / 脚步涟漪、
// 岸边浪花；积雪量高时从岸边向外结冰（冰面不透明）。
// 水深由 shore_z + 湖底剖面参数解析计算（与 Demo 里生成湖底网格的公式一致），不依赖深度缓冲，
// 因此在 Compatibility / Web 渲染器上也能用。
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_lambert, specular_schlick_ggx;

#include "res://addons/pixel_world/shaders/pw_common.gdshaderinc"

uniform vec4 shallow : source_color = vec4(0.47, 0.70, 0.72, 1.0);  // 浅滩：water_0 与 teal_0 之间
uniform vec4 mid : source_color = vec4(0.353, 0.525, 0.678, 1.0);   // water_1
uniform vec4 deep : source_color = vec4(0.200, 0.330, 0.470, 1.0);  // water_2 稍暗
uniform vec4 highlight : source_color = vec4(0.612, 0.765, 0.867, 1.0);
uniform vec4 foam : source_color = vec4(0.890, 0.914, 0.949, 1.0);
uniform vec4 ice : source_color = vec4(0.780, 0.863, 0.925, 1.0);
uniform vec4 ice_crack : source_color = vec4(0.651, 0.765, 0.859, 1.0);
uniform float texel_density = 32.0;
uniform float freeze_start = 0.4;
// 岸线（世界 Z，水在 +Z 一侧）与湖底剖面：d = 离岸距离
//   d < bend1：bed = -slope1 * d；bend1..bend2：再以 slope2 下降；之后近乎平坦
// 默认 shore_z 很远 = 没有岸，整片当深水处理。
uniform float shore_z = 100000.0;
uniform float slope1 = 0.35;
uniform float bend1 = 3.0;
uniform float slope2 = 0.4;
uniform float bend2 = 9.0;

varying vec3 wp;

float bed_y(float d) {
	if (d <= 0.0) {
		return 0.0;
	}
	if (d < bend1) {
		return -slope1 * d;
	}
	float y1 = -slope1 * bend1;
	if (d < bend2) {
		return y1 - slope2 * (d - bend1);
	}
	return y1 - slope2 * (bend2 - bend1) - 0.05 * min(d - bend2, 6.0);
}

// 波光短线：每格随机位置一条横线，按行左右漂移、随时间明灭
float dashes(vec2 cell, vec2 cs, float t, float speed, float seed, float density) {
	float row_i = floor(cell.y / cs.y);
	float dir = mod(row_i, 2.0) < 1.0 ? 1.0 : -1.0;
	vec2 pp = cell + vec2(floor(t * speed) * dir + row_i * 7.0, 0.0);
	vec2 ci = floor(pp / cs);
	vec2 lc = pp - ci * cs;
	float r = hash12(ci + seed);
	float row = floor(r * cs.y);
	float x0 = floor(fract(r * 7.31) * (cs.x - 9.0));
	float len = 3.0 + floor(fract(r * 3.17) * 6.0);
	float on = step(1.0 - density, sin(t * (0.4 + r * 0.6) + r * 40.0) * 0.5 + 0.5);
	return step(abs(lc.y - row), 0.1) * step(x0, lc.x) * step(lc.x, x0 + len - 1.0) * on;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = floor(wp.xz * texel_density);
	float t = TIME;
	bool has_shore = shore_z < 50000.0;
	float d = has_shore ? wp.z - shore_z : 100.0;
	float depth = max(wp.y - bed_y(d), 0.0);

	// 颜色和透明度随水深变化：浅滩几乎透明（看得见沙底、水草和鱼），越深越蓝越不透明
	vec3 c = mix(shallow.rgb, mid.rgb, smoothstep(0.0, 1.3, depth));
	c = mix(c, deep.rgb, smoothstep(1.3, 3.4, depth));
	float alpha = mix(0.16, 0.93, smoothstep(0.0, 2.8, depth));

	// 天空反射（掠射角更强）
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	c = mix(c, pw_sky_color.rgb, clamp(fres * 0.6 + 0.08, 0.0, 0.6));
	alpha = max(alpha, fres * 0.7);

	// 波光（深一些的地方才有）
	float lit = dashes(cell, vec2(28.0, 12.0), t, 1.0, 0.0, 0.3 + pw_wetness * 0.3) * smoothstep(0.8, 1.6, depth);
	c = mix(c, highlight.rgb, lit * 0.8);
	alpha = max(alpha, lit * 0.8);

	// 雨滴 / 脚步涟漪
	float rip = rain_ripples(wp.xz, t, pw_rain) + step_ripples(wp.xz);
	rip = clamp(rip, 0.0, 1.0);
	c = mix(c, foam.rgb, rip * 0.55);
	alpha = max(alpha, rip * 0.75);

	// 岸边浪花：水深接近 0 的一圈起伏白边 + 一道向岸推进的断续浪线
	if (has_shore) {
		float x = wp.x;
		float edge = 0.05 + 0.035 * sin(x * 1.3 + t * 1.3) + 0.02 * sin(x * 0.45 - t * 0.7);
		float foam1 = 1.0 - smoothstep(edge, edge + 0.02, depth);
		float wave_d = 0.12 + 0.18 * fract(t * 0.12);
		float foam2 = (1.0 - smoothstep(0.0, 0.015, abs(depth - wave_d))) * step(0.45, fract(x * 0.35 + sin(x * 1.1) * 0.15));
		float f = max(foam1, foam2 * 0.8);
		c = mix(c, foam.rgb, f);
		alpha = max(alpha, f * 0.9);
	}

	// 细碎起伏：让阳光在水面上闪烁
	vec2 q = wp.xz * 1.6 + vec2(t * 0.35, t * 0.22);
	float e = 0.08;
	float h0 = vnoise(q);
	float hx = vnoise(q + vec2(e, 0.0));
	float hz = vnoise(q + vec2(0.0, e));
	NORMAL_MAP = normalize(vec3((h0 - hx) / e * 0.12, (h0 - hz) / e * 0.12, 1.0)) * 0.5 + 0.5;

	// 结冰：有岸时从岸边向外推进，冰面不透明，两种色调成片分布，带细裂纹
	float freeze = smoothstep(freeze_start, 1.0, pw_snow_amount);
	float b = bayer4(cell);
	float frozen;
	if (has_shore) {
		float front = freeze * 40.0 - d + (vnoise(cell * 0.03) - 0.5) * 4.0;
		frozen = step(0.001, freeze) * step((b - 0.5) * 1.2, front);
	} else {
		frozen = step(hash12(cell) * 0.5 + 0.25, freeze);
	}
	vec3 ic = mix(ice.rgb, ice_crack.rgb, step(0.58, vnoise(cell * 0.025)));
	float crack = step(abs(vnoise(cell * 0.0125 + 3.0) - 0.5), 0.01);
	ic = mix(ic, mid.rgb, crack);
	c = mix(c, ic, frozen);
	alpha = mix(alpha, 1.0, frozen);

	ALBEDO = c;
	ALPHA = alpha;
	ROUGHNESS = mix(0.05, 0.6, frozen);
	SPECULAR = mix(0.55, 0.3, frozen);
}
