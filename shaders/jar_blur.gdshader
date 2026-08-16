shader_type canvas_item;
// Box-размытие спрайта (стекло-бутылка) для «пьяного» градуса Пита + опциональное
// обесцвечивание (дебафф Ир «Выцветший мир»).
// amount 0..1 → смещение выборки; при 0 — без размытия.
// grayscale 0..1 → доля перевода в чёрно-белое.

uniform float amount = 0.0;
uniform float grayscale = 0.0;

void fragment() {
	float o = amount * 0.014;
	vec4 c;
	if (o <= 0.0001) {
		c = texture(TEXTURE, UV);
	} else {
		c = texture(TEXTURE, UV) * 0.30;
		c += texture(TEXTURE, UV + vec2(o, 0.0)) * 0.14;
		c += texture(TEXTURE, UV + vec2(-o, 0.0)) * 0.14;
		c += texture(TEXTURE, UV + vec2(0.0, o)) * 0.14;
		c += texture(TEXTURE, UV + vec2(0.0, -o)) * 0.14;
		c += texture(TEXTURE, UV + vec2(o, o)) * 0.085;
		c += texture(TEXTURE, UV + vec2(-o, o)) * 0.085;
		c += texture(TEXTURE, UV + vec2(o, -o)) * 0.085;
		c += texture(TEXTURE, UV + vec2(-o, -o)) * 0.085;
	}
	if (grayscale > 0.0001) {
		float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		c.rgb = mix(c.rgb, vec3(l), grayscale);
	}
	COLOR = c;
}
