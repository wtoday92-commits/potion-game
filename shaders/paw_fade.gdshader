shader_type canvas_item;
// Кошачья лапа (Бабушка Мурра): мягкий размытый край + плавное затухание книзу —
// лапа будто «входит» в кадр и растворяется внизу. Порт CSS-маски/blur лапы.

uniform float blur = 0.006;        // радиус размытия края (в UV текстуры)
uniform float fade_from = 0.5;     // с какой доли высоты начинается затухание
uniform float fade_to = 1.0;       // где стала полностью прозрачной (низ)

void fragment() {
	// лёгкое box-размытие → мягкий, не резкий контур лапы
	vec4 c = texture(TEXTURE, UV) * 0.36;
	c += texture(TEXTURE, UV + vec2(blur, 0.0)) * 0.16;
	c += texture(TEXTURE, UV + vec2(-blur, 0.0)) * 0.16;
	c += texture(TEXTURE, UV + vec2(0.0, blur)) * 0.16;
	c += texture(TEXTURE, UV + vec2(0.0, -blur)) * 0.16;
	// плавный градиент прозрачности книзу (UV.y=1 — низ)
	c.a *= 1.0 - smoothstep(fade_from, fade_to, UV.y);
	COLOR = c;
}
