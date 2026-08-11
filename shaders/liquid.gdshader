shader_type canvas_item;
// Жидкость + сгустки ВНУТРИ нарисованной бутыли. Клиппинг по маске интерьера
// (bottle_interior.png). Рисуется ПОЗАДИ бутыли, видна через прозрачное стекло.

uniform vec4 liquid_col : source_color = vec4(0.55, 0.25, 0.85, 1.0);
uniform sampler2D mask;              // альфа = внутренняя область стекла
uniform float fill = 0.88;           // уровень жидкости в интерьере
uniform float interior_top = 0.15;
uniform float interior_bot = 0.95;
uniform float interior_left = 0.24;
uniform float interior_right = 0.75;
uniform float aspect = 0.558;        // ширина/высота контрола (для круглых сгустков)
uniform vec4 blobs[12];
uniform int blob_n = 0;

void fragment() {
	float m = texture(mask, UV).a;
	if (m < 0.02) {
		COLOR = vec4(0.0);
	} else {
		float liq_top = interior_bot - (interior_bot - interior_top) * fill;
		vec4 col = vec4(0.0);

		if (UV.y > liq_top) {
			float t = clamp((UV.y - liq_top) / max(0.0001, interior_bot - liq_top), 0.0, 1.0);
			vec3 topc = clamp(liquid_col.rgb * 1.22 + 0.03, vec3(0.0), vec3(1.0));
			vec3 botc = liquid_col.rgb * 0.60;
			col = vec4(mix(topc, botc, t), 0.96);
			// тень цилиндра по бокам
			float cx = (interior_left + interior_right) * 0.5;
			float hw = (interior_right - interior_left) * 0.5;
			float sidex = clamp(abs(UV.x - cx) / max(0.0001, hw), 0.0, 1.0);
			col.rgb *= mix(1.06, 0.80, sidex);
			// блик поверхности
			col.rgb += smoothstep(0.010, 0.0, abs(UV.y - liq_top)) * 0.45;
			// полутон
			vec2 gp = vec2(UV.x * aspect, UV.y) * 95.0;
			col.rgb *= mix(0.9, 1.0, smoothstep(0.30, 0.42, length(fract(gp) - 0.5)));
		}

		// сгустки: глянцевые объёмные шарики
		for (int i = 0; i < 12; i++) {
			if (i >= blob_n) { break; }
			float br = blobs[i].z;
			vec2 dd = UV - blobs[i].xy;
			dd.x *= aspect;
			float rr = length(dd) / max(0.0001, br);
			if (rr < 1.08) {
				vec2 lp = dd / max(0.0001, br);
				float z = sqrt(max(0.0, 1.0 - min(rr * rr, 1.0)));
				vec3 n = normalize(vec3(lp, z + 0.001));
				vec3 L = normalize(vec3(-0.5, -0.6, 0.75));
				float dif = clamp(dot(n, L), 0.0, 1.0);
				float spec = pow(dif, 26.0);
				vec3 bcol = liquid_col.rgb * (0.45 + 0.8 * dif) + spec * 1.1;
				col.rgb = mix(col.rgb, bcol, smoothstep(1.0, 0.93, rr));
				float outline = smoothstep(0.85, 1.0, rr) - smoothstep(1.0, 1.08, rr);
				col.rgb = mix(col.rgb, vec3(0.02, 0.02, 0.04), clamp(outline, 0.0, 1.0) * 0.7);
				float kant = smoothstep(0.78, 0.9, rr) - smoothstep(0.92, 1.0, rr);
				col.rgb += clamp(kant, 0.0, 1.0) * 0.14;
			}
		}

		col.a *= m;   // клип по интерьеру бутыли
		COLOR = col;
	}
}
