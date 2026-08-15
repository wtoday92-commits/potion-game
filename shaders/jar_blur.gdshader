shader_type canvas_item;
// Простое box-размытие спрайта (стекло-бутылка) для «пьяного» градуса Пита.
// amount 0..1 → смещение выборки; при 0 — идентичность (без размытия).

uniform float amount = 0.0;

void fragment() {
	float o = amount * 0.014;
	if (o <= 0.0001) {
		COLOR = texture(TEXTURE, UV);
	} else {
		vec4 c = texture(TEXTURE, UV) * 0.30;
		c += texture(TEXTURE, UV + vec2(o, 0.0)) * 0.14;
		c += texture(TEXTURE, UV + vec2(-o, 0.0)) * 0.14;
		c += texture(TEXTURE, UV + vec2(0.0, o)) * 0.14;
		c += texture(TEXTURE, UV + vec2(0.0, -o)) * 0.14;
		c += texture(TEXTURE, UV + vec2(o, o)) * 0.085;
		c += texture(TEXTURE, UV + vec2(-o, o)) * 0.085;
		c += texture(TEXTURE, UV + vec2(o, -o)) * 0.085;
		c += texture(TEXTURE, UV + vec2(-o, -o)) * 0.085;
		COLOR = c;
	}
}
