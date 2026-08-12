shader_type canvas_item;
// Атмосферный фон сцены: тёмный космо-градиент + медленно дрейфующие неоновые
// туманности + редкие мерцающие звёзды + виньетка. Тянется на весь экран,
// панели/рамка рисуются поверх. Всё анимируется от TIME, без ассетов.

uniform vec2 resolution = vec2(720.0, 1280.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float ar = resolution.x / resolution.y;

	// базовый вертикальный градиент
	vec3 col = mix(vec3(0.07, 0.06, 0.12), vec3(0.02, 0.02, 0.045), uv.y);

	// дрейфующие туманности (аспект-скорректированное пространство)
	vec2 q = vec2(uv.x * ar, uv.y);
	float t = TIME * 0.05;
	vec2 n1 = vec2((0.28 + 0.12 * sin(t * 1.3)) * ar, 0.30 + 0.10 * cos(t));
	col += vec3(0.24, 0.10, 0.40) * smoothstep(0.55, 0.0, length(q - n1)) * 0.45;
	vec2 n2 = vec2((0.72 + 0.10 * cos(t * 0.8)) * ar, 0.74 + 0.10 * sin(t * 1.1));
	col += vec3(0.05, 0.24, 0.34) * smoothstep(0.55, 0.0, length(q - n2)) * 0.42;
	vec2 n3 = vec2((0.55 + 0.14 * sin(t * 0.6 + 2.0)) * ar, 0.5 + 0.16 * cos(t * 0.7));
	col += vec3(0.20, 0.06, 0.28) * smoothstep(0.5, 0.0, length(q - n3)) * 0.30;

	// редкие мерцающие звёзды
	vec2 g = floor(uv * vec2(110.0, 195.0));
	float s = hash(g);
	float star = step(0.987, s);
	float tw = 0.5 + 0.5 * sin(TIME * 2.0 + s * 40.0);
	col += vec3(0.8, 0.85, 1.0) * star * tw * 0.6;

	// виньетка
	float vig = smoothstep(1.15, 0.35, length(uv - 0.5) * 1.35);
	col *= mix(0.55, 1.0, vig);

	COLOR = vec4(col, 1.0);
}
