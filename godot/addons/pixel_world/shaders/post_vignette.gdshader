// 暗角：乘法混合覆盖层，不读取屏幕（比在后期 pass 里做省一次整屏拷贝）
shader_type canvas_item;
render_mode blend_mul;

uniform float vignette = 0.22;

void fragment() {
	vec2 v = SCREEN_UV - 0.5;
	float k = 1.0 - vignette * dot(v, v) * 2.0;
	COLOR = vec4(k, k, k, 1.0);
}
