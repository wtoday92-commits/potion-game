shader_type canvas_item;
// Настоящее размытие содержимого банки (жидкость + сгустки) — Аптекарь Мо
// («состояние пациента») и градус Пита. Читает уже нарисованное под собой
// (screen_texture) и рисует размытую копию ТОЛЬКО внутри маски интерьера стекла,
// не трогая фон вокруг. amount 0..1 → сила box-размытия. Порт CSS blur(jarSvg).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D mask;              // альфа = внутренняя область стекла
uniform float amount = 0.0;

void fragment() {
	float m = texture(mask, UV).a;
	if (m < 0.02 || amount < 0.004) {
		COLOR = vec4(0.0);           // вне банки или без размытия — ничего не рисуем
	} else {
		vec2 o = amount * SCREEN_PIXEL_SIZE * 7.0;
		vec4 c = texture(screen_tex, SCREEN_UV) * 0.24;
		c += texture(screen_tex, SCREEN_UV + vec2(o.x, 0.0)) * 0.13;
		c += texture(screen_tex, SCREEN_UV + vec2(-o.x, 0.0)) * 0.13;
		c += texture(screen_tex, SCREEN_UV + vec2(0.0, o.y)) * 0.13;
		c += texture(screen_tex, SCREEN_UV + vec2(0.0, -o.y)) * 0.13;
		c += texture(screen_tex, SCREEN_UV + vec2(o.x, o.y)) * 0.06;
		c += texture(screen_tex, SCREEN_UV + vec2(-o.x, o.y)) * 0.06;
		c += texture(screen_tex, SCREEN_UV + vec2(o.x, -o.y)) * 0.06;
		c += texture(screen_tex, SCREEN_UV + vec2(-o.x, -o.y)) * 0.06;
		COLOR = vec4(c.rgb, m);
	}
}
