// 接地阴影：细物体（栏杆、路灯、长椅）下方一块边缘柔和的固定暗影。
// 细物体不投实时阴影——太阳连续转动时，细长的实时阴影只占几个阴影贴图像素，每帧重新光栅化就会像电流一样抖；
// 这块暗影不随太阳动，完全稳定。
// UV：0..1 铺满矩形；UV2 = 矩形的米制尺寸（用来算出固定宽度的柔边）。顶点色 A = 强度。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://addons/pixel_world/shaders/pw_common.gdshaderinc"

uniform float feather = 0.32;  // 柔边宽度（米）

void fragment() {
	vec2 size = UV2;
	vec2 p = UV * size;                         // 矩形内的米制坐标
	vec2 d = min(p, size - p);                  // 到最近边的距离
	float k = smoothstep(0.0, feather, d.x) * smoothstep(0.0, feather, d.y);
	// 积雪时淡一些（雪地上的影子偏蓝偏浅），阴天、夜里光线本来就散，也淡一些
	float s = COLOR.a * k * (1.0 - 0.4 * pw_snow_amount) * (1.0 - 0.5 * pw_night_factor);
	ALBEDO = vec3(0.04, 0.05, 0.09);
	ALPHA = s;
}
