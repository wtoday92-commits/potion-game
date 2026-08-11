shader_type canvas_item;
// Потёртое дерево (доски + волокна + пятна/потёртости). Без внешних текстур.

uniform vec4 wood_dark : source_color = vec4(0.24, 0.14, 0.07, 1.0);
uniform vec4 wood_light : source_color = vec4(0.47, 0.30, 0.16, 1.0);
uniform float planks = 8.0;       // число досок по вертикали
uniform float grain_scale = 42.0; // частота волокон

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float row = uv.y * planks;
	float pi = floor(row);
	float inp = fract(row);
	float pr = hash(vec2(pi, 7.0));

	// волокна вдоль доски (по X), слегка волнистые
	float wobble = fbm(vec2(uv.x * 3.0, pi * 2.0)) * 0.15;
	float grain = fbm(vec2(uv.x * grain_scale, (uv.y + wobble) * grain_scale * 0.15 + pi * 10.0));
	float tone = clamp(grain * 0.7 + pr * 0.35, 0.0, 1.0);
	vec3 col = mix(wood_dark.rgb, wood_light.rgb, tone);

	// стыки досок — тёмные
	float gap = smoothstep(0.0, 0.05, inp) * smoothstep(0.0, 0.05, 1.0 - inp);
	col *= mix(0.5, 1.0, gap);

	// потёртости/пятна
	float wear = fbm(uv * vec2(5.0, 9.0) + pr * 3.0);
	col *= mix(0.78, 1.06, wear);

	COLOR = vec4(col, 1.0);
}
