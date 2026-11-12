// PixelWorld 统一材质：所有场景模型共用。
// 像素贴图（Nearest）+ 积雪 / 潮湿 / 夜间自发光 / 风动，均由全局参数驱动。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

global uniform float pw_snow_amount;
global uniform float pw_wetness;
global uniform float pw_night_factor;
global uniform vec2 pw_wind;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
// true：UV 以米为单位，按 texel_density 换算成贴图像素（保证全场景像素颗粒一致）
uniform bool uv_in_meters = true;
uniform float texel_density = 16.0;
uniform float roughness_base = 0.9;

uniform sampler2D emission_tex : filter_nearest, repeat_enable, hint_default_black;
uniform float emission_full = 0.0;          // 1 = 整个表面发光（灯泡）
uniform vec4 emission_color : source_color = vec4(1.0, 0.8, 0.45, 1.0);
uniform float emission_energy = 1.6;
uniform float emission_random_off = 0.0;    // 夜里随机熄灯的比例（窗户）

uniform float snow_receive = 1.0;
uniform float snow_patchiness = 0.0;        // >0：积雪成片斑驳（道路被踩过的效果）
uniform vec4 snow_color : source_color = vec4(0.890, 0.914, 0.949, 1.0);
uniform vec4 snow_color_alt : source_color = vec4(0.835, 0.867, 0.925, 1.0);
uniform float wet_receive = 1.0;
uniform float sway = 0.0;                   // 风动幅度（树）

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 object_origin;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash13(vec3(i, 1.0));
	float b = hash13(vec3(i + vec2(1.0, 0.0), 1.0));
	float c = hash13(vec3(i + vec2(0.0, 1.0), 1.0));
	float d = hash13(vec3(i + vec2(1.0, 1.0), 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 4x4 Bayer 有序抖动阈值（0..1），像素画常用的过渡方式
float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

void vertex() {
	object_origin = MODEL_MATRIX[3].xyz;
	if (sway > 0.0) {
		float h = max(VERTEX.y - 0.6, 0.0);
		float phase = TIME * 1.6 + object_origin.x * 0.37 + object_origin.z * 0.29;
		float s = (sin(phase) * 0.6 + sin(phase * 2.3) * 0.4) * (0.15 + length(pw_wind));
		vec2 off = (pw_wind + vec2(0.2, 0.0)) * s * h * h * 0.012 * sway;
		// 量化到像素网格，摆动呈「一格一格」的像素感
		off = floor(off * texel_density + 0.5) / texel_density;
		VERTEX.xz += off;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 tex_size = vec2(textureSize(albedo_tex, 0));
	vec2 uv = uv_in_meters ? UV * texel_density / tex_size : UV;
	vec4 tex = texture(albedo_tex, uv) * albedo_color;
	vec3 col = tex.rgb;

	// 以「贴图像素」为单位的格子坐标，用于积雪的像素级抖动边缘
	vec3 cell = uv_in_meters
		? vec3(floor(UV * texel_density), dot(floor(world_normal * 3.0 + 0.5), vec3(1.0, 7.0, 13.0)) + dot(object_origin, vec3(1.3, 0.0, 2.1)))
		: floor(world_pos * texel_density);
	float h = bayer4(cell.xy + floor(cell.z));

	// 积雪：朝上的面；有序抖动形成像素化的过渡边缘
	float up = clamp((world_normal.y - 0.45) / 0.35, 0.0, 1.0);
	float s = clamp(pw_snow_amount * snow_receive, 0.0, 1.0);
	float cov = up * s * 1.25 - 0.1;
	if (snow_patchiness > 0.0) {
		vec2 q = floor(world_pos.xz * texel_density) / texel_density;
		cov += (vnoise(q * 0.9) * 0.65 + vnoise(q * 2.7) * 0.35 - 0.5) * snow_patchiness * 2.0 * min(s * 3.0, 1.0);
	}
	float snow = step(h, cov);
	vec3 sc = mix(snow_color.rgb, snow_color_alt.rgb, step(0.8, hash13(cell + 17.0)));
	col = mix(col, sc, snow);

	// 潮湿：变暗 + 更光滑
	float wet = pw_wetness * wet_receive * (1.0 - snow) * mix(0.5, 1.0, up);
	col *= 1.0 - 0.35 * wet;

	ALBEDO = col;
	ROUGHNESS = mix(roughness_base, 0.4, wet);
	SPECULAR = mix(0.15, 0.4, wet);

	// 夜间发光
	float em = clamp(texture(emission_tex, UV).r + emission_full, 0.0, 1.0);
	float on = step(emission_random_off, hash13(floor(world_pos * 0.8) + 3.0));
	EMISSION = emission_color.rgb * emission_energy * em * on * pw_night_factor * (1.0 - snow);
}
