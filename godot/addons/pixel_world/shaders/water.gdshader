// 像素水面：近岸浅、远处深（有序抖动过渡）+ 漂移闪烁的短横线波光 + 岸边浪花；
// 积雪量高时从岸边向外结冰。所有效果都对齐到像素网格（texel_density）。
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_lambert, specular_schlick_ggx;

global uniform float pw_snow_amount;
global uniform float pw_wetness;

uniform vec4 deep : source_color = vec4(0.247, 0.392, 0.537, 1.0);       // water_2
uniform vec4 shallow : source_color = vec4(0.353, 0.525, 0.678, 1.0);    // water_1
uniform vec4 highlight : source_color = vec4(0.612, 0.765, 0.867, 1.0);  // water_0
uniform vec4 foam : source_color = vec4(0.890, 0.914, 0.949, 1.0);       // snow_1
uniform vec4 ice : source_color = vec4(0.780, 0.863, 0.925, 1.0);        // ice_0
uniform vec4 ice_crack : source_color = vec4(0.651, 0.765, 0.859, 1.0);  // ice_1
uniform float texel_density = 16.0;
uniform float freeze_start = 0.4;
// 岸线：世界 Z 坐标，水在 +Z 一侧。默认很远 = 没有岸（不画浪花，结冰均匀出现）。
// P2 的地形生成器会改成岸线距离贴图。
uniform float shore_z = 100000.0;
uniform float deep_distance = 10.0;   // 离岸多远变成深水（米）

varying vec3 wp;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

// 一层短横线：cs = 每格大小（像素），每格里随机位置一条 2~5 像素的横线，按行左右漂移、随时间闪烁
float dashes(vec2 cell, vec2 cs, float t, float speed, float seed, float density) {
	float row_i = floor(cell.y / cs.y);
	float dir = mod(row_i, 2.0) < 1.0 ? 1.0 : -1.0;
	vec2 pp = cell + vec2(floor(t * speed) * dir + row_i * 5.0, 0.0);
	vec2 ci = floor(pp / cs);
	vec2 lc = pp - ci * cs;
	float r = hash12(ci + seed);
	float row = floor(r * cs.y);
	float x0 = floor(fract(r * 7.31) * (cs.x - 5.0));
	float len = 2.0 + floor(fract(r * 3.17) * 4.0);
	float on = step(1.0 - density, fract(sin(t * (0.5 + r) + r * 40.0) * 0.5 + 0.5));
	return step(abs(lc.y - row), 0.1) * step(x0, lc.x) * step(lc.x, x0 + len - 1.0) * on;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = floor(wp.xz * texel_density);
	float t = TIME;
	float b = bayer4(cell);
	bool has_shore = shore_z < 50000.0;
	float d = has_shore ? (cell.y + 0.5) / texel_density - shore_z : deep_distance;  // 离岸距离（米）

	// 底色：浅 → 深，过渡带用有序抖动；再叠一点缓慢变化的大块明暗
	float depth_f = clamp(d / deep_distance, 0.0, 1.0) + (vnoise(cell * 0.03 + vec2(t * 0.05, 0.0)) - 0.5) * 0.35;
	vec3 c = mix(shallow.rgb, deep.rgb, step(0.5 + (b - 0.5) * 0.35, depth_f));

	// 波光（亮短线）+ 波谷（暗短线，只画在浅水区）
	float lit = dashes(cell, vec2(12.0, 5.0), t, 0.8, 0.0, 0.5 + pw_wetness * 0.3);
	float dark = dashes(cell + vec2(6.0, 2.0), vec2(16.0, 7.0), t, 0.5, 17.0, 0.35);
	c = mix(c, deep.rgb, dark * step(depth_f, 0.5));
	c = mix(c, highlight.rgb, lit);

	// 岸边浪花：贴岸一条起伏的白边 + 一道向岸边推进的断续浪线
	if (has_shore) {
		float x = cell.x;
		float edge = 0.18 + 0.1 * sin(x * 0.35 + t * 1.3) + 0.06 * sin(x * 0.13 - t * 0.7);
		float foam1 = step(d, edge);
		float wave_d = 0.55 + 0.35 * fract(t * 0.12);
		float foam2 = step(abs(d - wave_d), 0.04) * step(0.45, fract(x * 0.045 + sin(x * 0.21) * 0.15));
		c = mix(c, foam.rgb, max(foam1, foam2));
	}

	// 结冰：有岸时从岸边向外推进，边缘有序抖动；冰面两种色调成片分布，带细裂纹
	float freeze = smoothstep(freeze_start, 1.0, pw_snow_amount);
	float frozen;
	if (has_shore) {
		float front = freeze * 40.0 - d + (vnoise(cell * 0.06) - 0.5) * 4.0;
		frozen = step(0.001, freeze) * step((b - 0.5) * 1.2, front);
	} else {
		frozen = step(hash12(cell) * 0.5 + 0.25, freeze);
	}
	vec3 ic = mix(ice.rgb, ice_crack.rgb, step(0.58, vnoise(cell * 0.05)));
	float crack = step(abs(vnoise(cell * 0.025 + 3.0) - 0.5), 0.012);
	ic = mix(ic, shallow.rgb, crack);
	c = mix(c, ic, frozen);

	ALBEDO = c;
	ROUGHNESS = mix(0.15, 0.6, frozen);
	SPECULAR = 0.6;
}
