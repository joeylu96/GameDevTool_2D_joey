// PixelWorld 统一材质：所有场景模型共用。
// 程序化贴图（近处最近邻清晰、远处 mipmap 平滑）+ 积雪 / 潮湿 / 水洼 / 夜间自发光 / 风动 / 水下焦散，
// 均由全局参数驱动。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

#include "res://addons/pixel_world/shaders/pw_common.gdshaderinc"

// 线性过滤 + 下方的「锐利双线性」采样：近处贴图像素边缘锐利，镜头移动时边缘平滑过渡（不闪烁），远处走 mipmap
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
// true：UV 以米为单位，按 texel_density 换算成贴图像素（保证全场景像素颗粒一致）
uniform bool uv_in_meters = true;
uniform bool pixel_aa = true;   // false = 等同最近邻采样（对比 / 调试用）
uniform float texel_density = 32.0;
uniform float roughness_base = 0.9;

uniform sampler2D emission_tex : filter_nearest, repeat_enable, hint_default_black;
uniform float emission_full = 0.0;          // 1 = 整个表面发光（灯泡、窗玻璃）
uniform vec4 emission_color : source_color = vec4(1.0, 0.8, 0.45, 1.0);
uniform float emission_energy = 1.6;
uniform float emission_random_off = 0.0;    // 夜里随机熄灯的比例（按顶点色 R 区分每扇窗）

uniform float snow_receive = 1.0;
uniform float snow_patchiness = 0.0;        // >0：积雪成片斑驳（道路被踩过的效果）
uniform vec4 snow_color : source_color = vec4(0.890, 0.914, 0.949, 1.0);
uniform vec4 snow_color_alt : source_color = vec4(0.835, 0.867, 0.925, 1.0);
uniform float wet_receive = 1.0;
uniform float puddles = 0.0;                // >0：下雨时这个表面会出现积水（地面）
uniform float sway = 0.0;                   // 风动幅度（树）
uniform float caustics = 0.0;               // >0：水下焦散光斑（湖底）
uniform float water_level = -0.45;

// 地形混合模式（野外地形）：albedo_tex 是草地；顶点色 R / G / B = 沙 / 岩石 / 湖底的权重（0..1），
// 交界用噪声打乱，得到清晰但不规则的边（不是沿三角形走的锯齿）。此模式下顶点色不当色调用。
uniform bool terrain_mode = false;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D bed_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 object_origin;
varying vec4 inst_tint;

void vertex() {
	object_origin = MODEL_MATRIX[3].xyz;
	// MultiMesh 实例的自定义数据：rgb = 色调，a = 1 表示启用（每棵树颜色略有不同，避免一模一样）
	inst_tint = INSTANCE_CUSTOM;
	if (sway > 0.0) {
		float h = max(VERTEX.y - 0.6, 0.0);
		// 合批后多棵树在同一个网格里：每棵树的相位存在 UV2.x；没有 UV2 时按物体位置算
		float seed = UV2.x > 0.0 ? UV2.x : object_origin.x * 0.37 + object_origin.z * 0.29;
		float phase = TIME * 1.6 + seed;
		// 微风（晴天）时不摆，免得精细贴图细碎闪烁；起风后才明显摇动
		float amp = smoothstep(0.3, 1.0, length(pw_wind)) * 1.4;
		float s = (sin(phase) * 0.6 + sin(phase * 2.3) * 0.4) * amp;
		vec2 off = (pw_wind + vec2(0.2, 0.0)) * s * h * h * 0.012 * sway;
		VERTEX.xz += off;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// 按米为单位的 UV 对任意贴图做「锐利双线性」采样（见 fragment 里的说明）
vec3 sample_m(sampler2D t, vec2 uv_m, float density) {
	vec2 ts = vec2(textureSize(t, 0));
	vec2 uv = uv_m * density / ts;
	vec2 px = uv * ts;
	vec2 fw = max(abs(dFdx(px)) + abs(dFdy(px)), vec2(1e-4));
	vec2 seam = floor(px + 0.5);
	vec2 sharp = seam + clamp((px - seam) / fw, -0.5, 0.5);
	sharp = mix(sharp, px, smoothstep(0.75, 1.25, max(fw.x, fw.y)));
	return textureGrad(t, sharp / ts, dFdx(uv), dFdy(uv)).rgb;
}

// 权重 w 加噪声后在 0.5 附近做窄过渡：边界清晰、形状不规则
float blend_edge(float w, vec2 p, float seed) {
	float n = vnoise(p * 2.2 + seed) * 0.6 + vnoise(p * 6.0 + seed * 3.0) * 0.4;
	return smoothstep(0.46, 0.54, w + (n - 0.5) * 0.45);
}

void fragment() {
	vec2 tex_size = vec2(textureSize(albedo_tex, 0));
	vec2 uv = uv_in_meters ? UV * texel_density / tex_size : UV;
	// 锐利双线性：贴图像素内部取纯色，只在像素边界上用约 1 个屏幕像素做过渡。
	// 最近邻采样在镜头做亚像素移动时，整格像素会来回翻转，看起来就是闪烁。
	vec2 px = uv * tex_size;
	vec2 fw = max(abs(dFdx(px)) + abs(dFdy(px)), vec2(1e-4));  // 一个屏幕像素覆盖多少贴图像素
	vec2 seam = floor(px + 0.5);
	vec2 sharp = seam + clamp((px - seam) / fw, -0.5, 0.5);
	sharp = mix(sharp, px, smoothstep(0.75, 1.25, max(fw.x, fw.y)));  // 缩小时退回普通采样
	if (!pixel_aa) {
		sharp = floor(px) + 0.5;
	}
	vec4 tex = textureGrad(albedo_tex, sharp / tex_size, dFdx(uv), dFdy(uv)) * albedo_color;
	// 顶点色 RGB = 每个实例的色调（白色 = 不变）；MultiMesh 实例也可以用自定义数据给色调
	vec3 col = tex.rgb * COLOR.rgb;
	if (inst_tint.a > 0.5) {
		col *= inst_tint.rgb;
	}
	if (terrain_mode) {
		col = tex.rgb;
		vec2 wp2 = world_pos.xz;
		col = mix(col, sample_m(sand_tex, UV, texel_density), blend_edge(COLOR.r, wp2, 1.0));
		col = mix(col, sample_m(bed_tex, UV, texel_density), blend_edge(COLOR.b, wp2, 7.0));
		col = mix(col, sample_m(rock_tex, UV, texel_density), blend_edge(COLOR.g, wp2, 13.0));
	}

	// 以「贴图像素」为单位的格子坐标：积雪颗粒与贴图像素对齐
	vec3 cell = uv_in_meters
		? vec3(floor(UV * texel_density), dot(floor(world_normal * 3.0 + 0.5), vec3(1.0, 7.0, 13.0)) + dot(object_origin, vec3(1.3, 0.0, 2.1)))
		: floor(world_pos * texel_density);

	// 积雪：朝上的面。阈值 = 随机 + 成团噪声，积雪过程中一簇簇随机长出来，而不是整齐的网格；
	// 积满后整面成块。
	float up = clamp((world_normal.y - 0.45) / 0.35, 0.0, 1.0);
	float s = clamp(pw_snow_amount * snow_receive, 0.0, 1.0);
	float above_water = caustics > 0.0 ? step(water_level + 0.02, world_pos.y) : 1.0;
	s *= above_water;  // 水下的湖底不积雪
	float cov = up * s * 1.8 - 0.1;
	if (snow_patchiness > 0.0) {
		vec2 q = floor(world_pos.xz * texel_density) / texel_density;
		cov += (vnoise(q * 0.9) * 0.65 + vnoise(q * 2.7) * 0.35 - 0.5) * snow_patchiness * 2.0 * min(s * 3.0, 1.0);
		cov = (cov - 0.5) * 3.0 + 0.5;
	}
	float snow = 0.0;
	if (cov > 0.0) {  // 没有积雪时跳过噪声计算（性能）
		float h = vnoise(cell.xy * 0.07 + cell.z * 3.7) * 0.72 + vnoise(cell.xy * 0.22 + 9.0) * 0.16
			+ hash13(cell + 41.0) * 0.12;
		snow = step(h, cov);
		vec3 sc = mix(snow_color.rgb, snow_color_alt.rgb, step(0.62, vnoise(cell.xy * 0.12 + cell.z * 1.7)));
		col = mix(col, sc, snow);
	}

	// 潮湿：变暗 + 更光滑
	float wet = pw_wetness * wet_receive * (1.0 - snow) * mix(0.5, 1.0, up) * above_water;
	col *= 1.0 - 0.35 * wet;
	float rough = mix(roughness_base, 0.4, wet);
	float spec = mix(0.15, 0.4, wet);

	// 水洼：平地上随潮湿度长出来，反射天空，雨滴 / 脚步涟漪
	if (puddles > 0.0 && pw_wetness > 0.02) {
		float flat_k = smoothstep(0.92, 0.98, world_normal.y);
		float n = vnoise(world_pos.xz * 0.3) * 0.6 + vnoise(world_pos.xz * 0.95 + 11.0) * 0.4;
		float thr = 1.0 - clamp(pw_wetness, 0.0, 1.0) * 0.38 * puddles;
		float pud = smoothstep(thr, thr + 0.025, n) * flat_k * (1.0 - snow);
		if (pud > 0.0) {
			float rip = rain_ripples(world_pos.xz, TIME, pw_rain) + step_ripples(world_pos.xz);
			vec3 pc = mix(col * 0.5, pw_sky_color.rgb * 0.75, 0.5) + rip * 0.22;
			col = mix(col, pc, pud);
			rough = mix(rough, 0.04, pud);
			spec = mix(spec, 0.6, pud);
		}
	}

	// 水下焦散：白天在浅水湖底流动的光网
	if (caustics > 0.0) {
		float depth = water_level - world_pos.y;
		if (depth > 0.0) {
			vec2 q = world_pos.xz * 1.1;
			float c1 = vnoise(q + vec2(TIME * 0.35, TIME * 0.2));
			float c2 = vnoise(q * 1.35 - vec2(TIME * 0.25, -TIME * 0.3) + 5.0);
			float cst = pow(clamp(1.0 - abs(c1 - c2) * 5.0, 0.0, 1.0), 10.0);
			float k = caustics * smoothstep(0.0, 0.25, depth) * clamp(1.0 - depth / 2.5, 0.0, 1.0) * (1.0 - pw_night_factor);
			col += cst * k * 0.16 * pw_light_color.rgb;
		}
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;

	// 夜间发光；顶点色 A 作为每扇窗的随机数（没有顶点色时为 1 = 常亮）
	float em = clamp(texture(emission_tex, UV).r + emission_full, 0.0, 1.0);
	float on = step(emission_random_off, COLOR.a);
	EMISSION = emission_color.rgb * emission_energy * em * on * pw_night_factor * (1.0 - snow);
}
