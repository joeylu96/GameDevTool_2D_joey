// 后期：移轴景深（上下边缘模糊）+ 阴天去饱和 + 闪电闪白 + 暗角。
shader_type canvas_item;

global uniform float pw_flash;
global uniform float pw_desaturate;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform bool tilt_shift = true;
uniform float focus_center = 0.55;
uniform float focus_width = 0.16;
uniform float blur_px = 2.5;
uniform float vignette = 0.22;
uniform float flash_strength = 0.55;
uniform vec4 flash_color : source_color = vec4(0.88, 0.92, 1.0, 1.0);

const int TAPS = 12;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = texture(screen_tex, uv).rgb;
	if (tilt_shift) {
		float d = max(abs(uv.y - focus_center) - focus_width, 0.0) / max(0.5 - focus_width, 0.01);
		float r = clamp(d, 0.0, 1.0) * blur_px;
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
	vec2 v = uv - 0.5;
	c *= 1.0 - vignette * dot(v, v) * 2.0;
	c = mix(c, flash_color.rgb, clamp(pw_flash * flash_strength, 0.0, 1.0));
	COLOR = vec4(c, 1.0);
}
