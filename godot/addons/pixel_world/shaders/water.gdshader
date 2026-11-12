// 像素水面：量化到像素网格的波纹；积雪量高时逐渐结冰。
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_lambert, specular_schlick_ggx;

global uniform float pw_snow_amount;
global uniform float pw_wetness;

uniform vec4 deep : source_color = vec4(0.247, 0.392, 0.537, 1.0);
uniform vec4 shallow : source_color = vec4(0.353, 0.525, 0.678, 1.0);
uniform vec4 highlight : source_color = vec4(0.612, 0.765, 0.867, 1.0);
uniform vec4 ice : source_color = vec4(0.780, 0.863, 0.925, 1.0);
uniform vec4 ice_crack : source_color = vec4(0.651, 0.765, 0.859, 1.0);
uniform float texel_density = 16.0;
uniform float freeze_start = 0.4;

varying vec3 wp;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = floor(wp.xz * texel_density);
	vec2 p = cell / texel_density;
	float t = TIME;
	float w = sin(p.x * 1.1 + t * 0.7 + sin(p.y * 0.6 + t * 0.4) * 2.0) * sin(p.y * 1.9 - t * 0.5);
	float n = hash12(cell);
	vec3 c = mix(deep.rgb, shallow.rgb, step(0.15, w));
	c = mix(c, highlight.rgb, step(0.82 - pw_wetness * 0.1, w + n * 0.12));

	float freeze = smoothstep(freeze_start, 1.0, pw_snow_amount);
	float frozen = step(n * 0.5 + 0.25, freeze);
	vec2 big = floor(wp.xz * 0.7);
	float crack = step(0.93, hash12(cell + big * 13.0));
	vec3 ic = mix(ice.rgb, ice_crack.rgb, crack);
	c = mix(c, ic, frozen);

	ALBEDO = c;
	ROUGHNESS = mix(0.15, 0.6, frozen);
	SPECULAR = 0.6;
}
