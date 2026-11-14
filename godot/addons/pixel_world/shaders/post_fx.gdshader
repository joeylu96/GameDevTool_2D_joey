// 后期（需要读屏幕的部分）：移轴景深（上下边缘模糊，上方更重，按分辨率缩放）+ 阴天去饱和。
// 只在开了移轴或有去饱和时才启用；暗角 / 闪电见 PWPostFX 的覆盖层。
shader_type canvas_item;

global uniform float pw_desaturate;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform bool tilt_shift = true;
uniform float focus_center = 0.55;
uniform float focus_width = 0.18;
uniform float blur_px = 3.2;      // 720p 下的最大模糊半径（像素）；更高分辨率按比例放大，效果一致
uniform float far_boost = 1.3;    // 画面上方（远处）比下方（近处）模糊得更重，更像微缩模型

const int TAPS = 16;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = texture(screen_tex, uv).rgb;
	if (tilt_shift) {
		float d = max(abs(uv.y - focus_center) - focus_width, 0.0) / max(0.5 - focus_width, 0.01);
		d = smoothstep(0.0, 1.0, clamp(d, 0.0, 1.0));   // 清晰带边缘柔和过渡，不出现一条分界线
		float res_scale = (1.0 / SCREEN_PIXEL_SIZE.y) / 720.0;
		float r = d * blur_px * res_scale * (uv.y < focus_center ? far_boost : 1.0);
		if (r > 0.05) {
			vec3 acc = c;
			for (int i = 0; i < TAPS; i++) {
				float a = float(i) * 2.39996;
				float rr = r * sqrt((float(i) + 0.5) / float(TAPS));
				acc += texture(screen_tex, uv + vec2(cos(a), sin(a)) * rr * SCREEN_PIXEL_SIZE).rgb;
			}
			c = acc / float(TAPS + 1);
		}
	}
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), pw_desaturate * 0.6);
	// 暗角和闪电闪白在 PWPostFX 的覆盖层里做（不需要读屏幕）
	COLOR = vec4(c, 1.0);
}
