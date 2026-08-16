shader_type canvas_item;
// Грязь Уборщика Пятого Дока: ПЛОТНОЕ грязное «стекло витрины» — почти сплошная
// оливково-бурая плёнка (как fillRect .85 в браузере) с тёмными разводами и
// потёками. Мешает смотреть — надо оттереть. Статично поверх всего окна. Гладко,
// без пикселей. Стирается маской губки (mask_tex.r: 1 грязно → 0 отмыто).

uniform sampler2D mask_tex : filter_linear, repeat_disable; // маска стирания
uniform float seed = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.5);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float erase = texture(mask_tex, uv).r;             // 1 грязно → 0 отмыто
	vec2 s2 = vec2(seed, seed * 1.7);

	// многомасштабная «мраморность» — грязь ложится неровно, не квадратом
	float big  = fbm(uv * vec2(2.4, 2.8) + s2);           // крупные сгущения/просветы
	float mid  = fbm(uv * vec2(5.2, 5.6) + s2 * 1.5);     // средние разводы
	float fine = fbm(uv * vec2(12.0, 12.0) + s2 * 2.3);   // мелкая живая грязь
	float smear = fbm(uv * vec2(1.5, 8.0) + s2 * 1.2);    // вытянутые мазки/потёки
	float mottle = clamp(big * 0.55 + mid * 0.32 + fine * 0.18, 0.0, 1.0);

	// цвет: оливково-бурый rgba(55,48,28) с тёмными мазками
	float darkness = clamp(mid * 0.55 + smear * 0.55 + fine * 0.30, 0.0, 1.0);
	vec3 col = mix(vec3(0.216, 0.188, 0.110), vec3(0.065, 0.058, 0.032), darkness);

	// плотность высокая (банку почти не видно), но заметно неровная — не «квадратом».
	// Форму пятна (рваную/лопастную кромку) задаёт маска erase из grime_overlay.gd.
	float dens = clamp(0.84 + 0.26 * mottle - 0.14 * fine, 0.0, 1.0);
	float a = dens * erase;

	COLOR = vec4(col, a);
}
