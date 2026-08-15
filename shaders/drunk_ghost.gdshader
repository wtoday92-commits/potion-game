shader_type canvas_item;
// «Двоение в глазах»: поверх экрана рисуем полупрозрачную смещённую копию картинки.
// amount 0..1 — сила. Читает уже отрисованный кадр (hint_screen_texture).

uniform float amount = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	if (amount <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec2 off = vec2(0.012, 0.007) * amount;
		vec3 a = texture(screen_tex, SCREEN_UV + off).rgb;
		vec3 b = texture(screen_tex, SCREEN_UV - off * 0.6).rgb;
		COLOR = vec4((a + b) * 0.5, amount * 0.5);   // призрак-двойник поверх
	}
}
