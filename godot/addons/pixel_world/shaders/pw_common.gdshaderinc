// PixelWorld 公共 shader 代码：全局参数 + 噪声 + 涟漪。被 pixel_world / water 共用。

global uniform float pw_snow_amount;
global uniform float pw_wetness;
global uniform float pw_night_factor;
global uniform vec2 pw_wind;
global uniform float pw_rain;
global uniform vec4 pw_sky_color;
global uniform vec4 pw_light_color;
// 涟漪源：xy = 世界 XZ，z = 已经过的秒数，w = 强度
global uniform vec4 pw_step0;
global uniform vec4 pw_step1;
global uniform vec4 pw_step2;
global uniform vec4 pw_step3;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

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

// 4x4 Bayer 有序抖动阈值（0..1）
float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

// 雨滴涟漪：p = 世界 XZ（米）。每 ~0.6 米一格，格内随机位置周期性落下一滴，圆环向外扩散。
// rain 越大，参与的格子越多。返回 0..1。
float rain_ripples(vec2 p, float t, float rain) {
	if (rain <= 0.01) {
		return 0.0;
	}
	float sum = 0.0;
	for (int k = 0; k < 2; k++) {
		vec2 q = p * 1.6 + float(k) * vec2(0.37, 0.71);
		vec2 ci = floor(q);
		vec2 f = fract(q);
		float r = hash12(ci + float(k) * 19.7);
		vec2 c = vec2(hash12(ci + 1.7), hash12(ci + 3.3)) * 0.5 + 0.25;
		float ph = fract(t * (0.7 + r * 0.6) + r * 7.0);
		float d = length(f - c);
		float ring = 1.0 - smoothstep(0.0, 0.035, abs(d - ph * 0.3));
		sum += ring * (1.0 - ph) * step(r, rain);
	}
	return clamp(sum, 0.0, 1.0);
}

// 单个涟漪源：两道向外扩散、逐渐变淡的圆环
float step_ripple(vec2 p, vec4 s) {
	if (s.w <= 0.0 || s.z > 2.0) {
		return 0.0;
	}
	float age = s.z;
	float d = length(p - s.xy);
	float fade = s.w * clamp(1.0 - age / 2.0, 0.0, 1.0);
	float w = 0.03 + age * 0.025;
	float r1 = age * 0.85;
	float r2 = age * 0.85 - 0.25;
	float ring = 1.0 - smoothstep(0.0, w, abs(d - r1));
	ring += 0.6 * (1.0 - smoothstep(0.0, w, abs(d - r2))) * step(0.0, r2);
	return ring * fade;
}

float step_ripples(vec2 p) {
	return clamp(step_ripple(p, pw_step0) + step_ripple(p, pw_step1)
		+ step_ripple(p, pw_step2) + step_ripple(p, pw_step3), 0.0, 1.0);
}
