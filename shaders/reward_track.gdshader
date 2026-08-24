shader_type canvas_item;
// Полоса поощрений цикла: «живая» золотая жидкость с бликами и редкими
// звёздочками вокруг. Чем выше градация (glow), тем ярче и насыщеннее;
// на нуле полоса выцветает в серую. secret=1 — секретная фиолетовая градация.

uniform float fill : hint_range(0.0, 1.0) = 0.0;    // насколько залита (0..1)
uniform float glow : hint_range(0.0, 1.0) = 0.0;    // яркость градации (0..1)
uniform float secret : hint_range(0.0, 1.0) = 0.0;  // 0 — золото, 1 — фиолет
uniform float aspect = 8.0;                          // ширина/высота полосы
uniform float pad = 0.28;                            // поле под ореол, доли высоты
uniform vec4 empty_col : source_color = vec4(0.10, 0.10, 0.15, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	// Работаем в «единицах высоты полосы»: полоса занимает середину, по краям —
	// поле pad, в котором рисуется ореол и звёздочки.
	float inner_h = max(1.0 - pad * 2.0, 0.001);
	vec2 p = vec2(UV.x * aspect / inner_h, (UV.y - pad) / inner_h);
	float w = aspect / inner_h;                       // ширина в единицах высоты полосы

	// SDF таблетки (торцы — полукруги)
	vec2 half_size = vec2(w * 0.5, 0.5);
	vec2 d = abs(p - half_size) - (half_size - vec2(0.5, 0.5));
	float sd = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - 0.5;
	float aa = max(fwidth(sd), 0.0015) * 1.2;
	float mask = 1.0 - smoothstep(-aa, aa, sd);

	float t = TIME;
	float fx = UV.x;

	// --- залитая часть с мягким гребнем на границе ---
	float edge = 0.012;
	float filled = 1.0 - smoothstep(fill - edge, fill + edge, fx);
	float crest = exp(-pow((fx - fill) / max(edge * 2.2, 0.001), 2.0)) * step(0.001, fill);

	// --- «жидкость»: несколько бегущих волн разной частоты ---
	float wav = sin(p.x * 2.1 - t * 1.5) * 0.5
	          + sin(p.x * 5.7 + t * 2.2) * 0.28
	          + sin(p.x * 11.3 - t * 0.9) * 0.14;
	float depth = clamp(0.5 + wav * 0.35 + (0.5 - UV.y) * 0.8, 0.0, 1.0);

	// --- палитра: золото ↔ секретный фиолет ---
	vec3 c_dark = mix(vec3(0.42, 0.26, 0.03), vec3(0.24, 0.08, 0.40), secret);
	vec3 c_mid  = mix(vec3(1.00, 0.72, 0.18), vec3(0.68, 0.36, 1.00), secret);
	vec3 c_hi   = mix(vec3(1.00, 0.96, 0.74), vec3(0.94, 0.80, 1.00), secret);
	vec3 liquid = mix(c_dark, c_mid, smoothstep(0.05, 0.75, depth));
	liquid = mix(liquid, c_hi, smoothstep(0.72, 1.0, depth) * 0.85);

	// бегущий блик поперёк полосы
	float band = fract(fx * 0.85 - t * 0.14);
	float shine = exp(-pow((band - 0.5) * 7.0, 2.0));
	liquid += c_hi * shine * (0.10 + 0.22 * glow);

	// выцветание при низкой градации: к серому
	float lum = dot(liquid, vec3(0.299, 0.587, 0.114));
	liquid = mix(vec3(lum) * 0.60, liquid, 0.20 + 0.80 * glow);
	liquid *= 0.62 + 0.38 * glow;

	vec3 col = mix(empty_col.rgb, liquid, filled);
	col += c_hi * crest * (0.35 + 0.5 * glow);

	// тонкая рамка по контуру
	float rim = smoothstep(0.055, 0.0, abs(sd));
	col = mix(col, mix(vec3(0.45, 0.42, 0.55), c_hi, filled * (0.3 + 0.6 * glow)), rim * 0.75);

	// --- звёздочки: редкие, едва заметные, живут и внутри, и вокруг полосы ---
	vec2 cell = vec2(UV.x * aspect * 2.6, UV.y * 2.6);
	vec2 gi = floor(cell);
	vec2 gf = fract(cell) - 0.5;
	float h = hash21(gi);
	float tw = sin(t * 2.4 + h * 41.0) * 0.5 + 0.5;
	float star = smoothstep(0.24, 0.0, length(gf * vec2(1.0, 1.0)))
	           * smoothstep(0.55, 1.0, tw) * step(0.80, h);
	// ярче над залитой частью, слабее по «хвосту»
	star *= (0.25 + 0.75 * filled) * glow;
	col += c_hi * star * 0.9;

	// --- ореол вокруг полосы ---
	float halo = smoothstep(0.40, 0.0, max(sd, 0.0)) * (1.0 - mask);
	float a = mask + halo * (0.10 + 0.32 * glow) * (0.25 + 0.75 * filled) + star * 0.55;
	COLOR = vec4(col, clamp(a, 0.0, 1.0) * empty_col.a);
}
