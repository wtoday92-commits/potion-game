shader_type canvas_item;
// Банка-зелье целиком в шейдере: стекло, градиент жидкости, неон-ободок со
// свечением, блик, сгустки. Геометрия тела задаётся из скрипта (body_min/size).

uniform vec4 liquid_col : source_color = vec4(0.3, 1.0, 0.45, 1.0);
uniform vec4 rim_col : source_color = vec4(0.35, 0.88, 1.0, 1.0);
uniform vec2 body_min = vec2(0.15, 0.10);   // левый-верхний угол тела, 0..1
uniform vec2 body_size = vec2(0.70, 0.85);  // размер тела, доли
uniform float fill = 0.9;                   // доля высоты тела под жидкостью
uniform float corner = 0.05;                // радиус скругления (в долях высоты)
uniform float aspect = 0.76;                // ширина/высота контрола
uniform vec4 blobs[12];                      // xy — позиция (0..1), z — радиус (в долях высоты)
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
	p.x *= aspect;                          // изотропное пространство (единица = высота)
	vec2 halfc = vec2(half.x * aspect, half.y);
	float d = sd_round_box(p, halfc, corner);

	vec4 col = vec4(0.0);
	float body_bot = body_min.y + body_size.y;
	float liq_top = body_bot - body_size.y * fill;

	if (d < 0.0) {
		// стекло
		col = vec4(0.05, 0.07, 0.12, 0.5);
		// жидкость (снизу вверх), вертикальный градиент + блик поверхности
		if (uv.y > liq_top) {
			float t = clamp((uv.y - liq_top) / max(0.0001, body_bot - liq_top), 0.0, 1.0);
			vec3 lc = mix(liquid_col.rgb * 1.2, liquid_col.rgb * 0.7, t);
			col = vec4(lc, 0.92);
			float surf = smoothstep(0.012, 0.0, abs(uv.y - liq_top));
			col.rgb += surf * 0.4;
		}
		// сгустки
		for (int i = 0; i < 12; i++) {
			if (i >= blob_n) { break; }
			vec2 dd = uv - blobs[i].xy;
			dd.x *= aspect;
			float bdist = length(dd);
			float br = blobs[i].z;
			float inside = smoothstep(br, br * 0.72, bdist);
			col.rgb = mix(col.rgb, liquid_col.rgb * 1.5 + vec3(0.08), inside * 0.9);
		}
		// диагональный блик стекла (верх-лево)
		float streak = smoothstep(0.26, 0.0, abs((p.x + 0.12) - (uv.y - body_min.y) * 0.6));
		col.rgb += streak * 0.05;
	}

	// неоновый ободок + внешнее свечение
	float edge = smoothstep(0.014, 0.0, abs(d));
	float glow = smoothstep(0.06, 0.0, max(d, 0.0));
	col.rgb += rim_col.rgb * edge * 0.85;
	col.rgb += rim_col.rgb * glow * 0.22;
	col.a = max(col.a, max(edge, glow * 0.3));

	COLOR = col;
}
