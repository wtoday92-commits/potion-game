shader_type canvas_item;
// Банка-зелье целиком в шейдере: объёмная жидкость (градиент + тень цилиндра +
// полутон), блик стекла, неон-ободок и ГЛЯНЦЕВЫЕ объёмные сгустки (тёмный
// контур + светлый кант + блик — видны на любом цвете жидкости).

uniform vec4 liquid_col : source_color = vec4(0.55, 0.25, 0.85, 1.0);
uniform vec4 rim_col : source_color = vec4(0.35, 0.88, 1.0, 1.0);
uniform vec2 body_min = vec2(0.15, 0.10);
uniform vec2 body_size = vec2(0.70, 0.85);
uniform float fill = 0.9;
uniform float corner = 0.05;
uniform float aspect = 0.76;
uniform vec4 blobs[12];   // xy — позиция (0..1), z — радиус (в долях высоты)
uniform int blob_n = 0;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 uv = UV;
	vec2 c = body_min + body_size * 0.5;
	vec2 half = body_size * 0.5;
	vec2 p = uv - c;
	p.x *= aspect;
	vec2 halfc = vec2(half.x * aspect, half.y);
	float d = sd_round_box(p, halfc, corner);

	vec4 col = vec4(0.0);
	float body_top = body_min.y;
	float body_bot = body_min.y + body_size.y;
	float liq_top = body_bot - body_size.y * fill;

	if (d < 0.0) {
		// ---- стекло (пустая часть) ----
		col = vec4(0.06, 0.08, 0.14, 0.55);

		// ---- жидкость ----
		if (uv.y > liq_top) {
			float t = clamp((uv.y - liq_top) / max(0.0001, body_bot - liq_top), 0.0, 1.0);
			vec3 topc = clamp(liquid_col.rgb * 1.25 + 0.04, vec3(0.0), vec3(1.0));
			vec3 botc = liquid_col.rgb * 0.60;
			vec3 lc = mix(topc, botc, t);
			col = vec4(lc, 0.96);

			// тень цилиндра по бокам (объём)
			float sidex = clamp(abs(p.x) / max(0.0001, halfc.x), 0.0, 1.0);
			col.rgb *= mix(1.06, 0.80, sidex);

			// блик поверхности жидкости (мениск)
			float surf = smoothstep(0.016, 0.0, abs(uv.y - liq_top));
			col.rgb += surf * 0.5;

			// полутоновая «комикс»-текстура
			vec2 gp = vec2(uv.x * aspect, uv.y) * 92.0;
			float dots = length(fract(gp) - 0.5);
			col.rgb *= mix(0.90, 1.0, smoothstep(0.30, 0.42, dots));
		}

		// ---- сгустки: глянцевые объёмные шарики ----
		for (int i = 0; i < 12; i++) {
			if (i >= blob_n) { break; }
			float br = blobs[i].z;
			vec2 dd = uv - blobs[i].xy;
			dd.x *= aspect;
			float rr = length(dd) / max(0.0001, br);   // 0..1 внутри
			if (rr < 1.08) {
				vec2 lp = dd / max(0.0001, br);
				float z = sqrt(max(0.0, 1.0 - min(rr * rr, 1.0)));
				vec3 n = normalize(vec3(lp, z + 0.001));
				vec3 L = normalize(vec3(-0.5, -0.6, 0.75));
				float dif = clamp(dot(n, L), 0.0, 1.0);
				float spec = pow(dif, 26.0);
				vec3 bcol = liquid_col.rgb * (0.45 + 0.8 * dif) + spec * 1.1;
				col.rgb = mix(col.rgb, bcol, smoothstep(1.0, 0.93, rr));      // тело
				float outline = smoothstep(0.85, 1.0, rr) - smoothstep(1.0, 1.08, rr);
				col.rgb = mix(col.rgb, vec3(0.02, 0.02, 0.04), clamp(outline, 0.0, 1.0) * 0.7); // тёмный контур
				float kant = smoothstep(0.78, 0.9, rr) - smoothstep(0.92, 1.0, rr);
				col.rgb += clamp(kant, 0.0, 1.0) * 0.14;                       // светлый кант
			}
		}

		// ---- блик стекла (диагональ, верх-лево) ----
		float sx = (p.x + halfc.x) / (2.0 * halfc.x);
		float sy = (uv.y - body_top) / max(0.0001, body_size.y);
		float streak = smoothstep(0.10, 0.0, abs(sx - 0.20 - sy * 0.08));
		col.rgb += streak * (0.10 + 0.10 * (1.0 - sy));
		float toph = smoothstep(0.10, 0.0, sy) * (1.0 - smoothstep(0.0, 1.0, abs(sx - 0.5) * 1.8));
		col.rgb += toph * 0.10;
	}

	// ---- неоновый ободок + внешнее свечение ----
	float edge = smoothstep(0.012, 0.0, abs(d));
	float glow = smoothstep(0.055, 0.0, max(d, 0.0));
	col.rgb += rim_col.rgb * edge * 0.9;
	col.rgb += rim_col.rgb * glow * 0.22;
	col.a = max(col.a, max(edge, glow * 0.3));

	COLOR = col;
}
