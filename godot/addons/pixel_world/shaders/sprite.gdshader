// HD-2D 像素角色精灵：Y 轴公告板（永远竖直、转向镜头），从精灵表里按格子取一帧。
// 精灵本身已经画好了明暗（Blender 里分档上色），这里只叠加场景光照：
//   - 受太阳 / 路灯 / 夜晚影响，走进树荫会变暗（ATTENUATION 里有阴影）
//   - 背光时不会整个变黑（wrap 光照，最暗也保留 wrap_min）
//   - 影子 pass 里公告板朝向灯光，地上投出完整的人形影子
// 最近邻采样 + alpha 剪切：像素边缘锐利、不闪、能正确投影和遮挡。
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled;

uniform sampler2D sheet : source_color, filter_nearest, repeat_disable;
uniform vec2 grid = vec2(10.0, 8.0);   // 精灵表的列数（帧）、行数（方向）
uniform vec2 cell = vec2(0.0);         // 当前帧（列）、方向（行）
uniform float wrap_min = 0.55;
uniform float flash = 0.0;              // 受击闪白（0..1）
uniform float shadow_skew = 0.9;        // 影子 pass 里投影板每升高 1 米、往背光方向偏多少米

void vertex() {
	// 和 BaseMaterial3D 的 BILLBOARD_FIXED_Y 同样的写法：保留 Y 轴，X / Z 轴转向镜头
	// 影子 pass（太阳的正交投影）里公告板转向太阳，会和画面里那块（转向镜头）在中线相交，
	// 把角色自己的半边身子罩进影子里。所以影子 pass 里让投影板随高度往「背着太阳」的方向斜过去：
	// 脚底不动（地上的影子还是从脚下开始），越往上离得越远，角色身上就不会出现半明半暗的竖线。
	vec3 up_axis = vec3(0.0, 1.0, 0.0);
	if (PROJECTION_MATRIX[3][3] > 0.5) {
		up_axis -= INV_VIEW_MATRIX[2].xyz * shadow_skew;
	}
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(up_axis, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 t = texture(sheet, (cell + UV) / grid);
	ALBEDO = mix(t.rgb, vec3(1.0), flash);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}

void light() {
	// 公告板的法线永远朝镜头：用「朝上 + 朝镜头」的混合来算光，太阳越高越亮，背光也不至于发黑
	vec3 n = normalize(NORMAL + (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float w = mix(wrap_min, 1.0, clamp(dot(n, LIGHT) * 0.5 + 0.5, 0.0, 1.0));
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * w / PI;
}
