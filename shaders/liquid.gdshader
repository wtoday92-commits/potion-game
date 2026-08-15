shader_type canvas_item;
// Живая жидкость + органические сгустки ВНУТРИ нарисованной бутыли.
// Клиппинг по маске интерьера (bottle_interior.png). Рисуется ПОЗАДИ бутыли,
// видна через прозрачное стекло. Вся анимация — от TIME + uniform tilt (плескание),
// который считает скрипт по физике покачивания банки.

uniform vec4 liquid_col : source_color = vec4(0.55, 0.25, 0.85, 1.0);
uniform sampler2D mask;              // альфа = внутренняя область стекла
uniform float fill = 0.88;           // уровень жидкости в интерьере
uniform float interior_top = 0.15;
uniform float interior_bot = 0.95;
uniform float interior_left = 0.24;
uniform float interior_right = 0.75;
uniform float aspect = 0.558;        // ширина/высота контрола (для круглых сгустков)
uniform float tilt = 0.0;            // наклон поверхности от плескания (радианы, из скрипта)
uniform float slosh = 0.0;           // энергия плескания 0..1 (усиливает волны/дрейф)
uniform vec4 blobs[12];              // xy=центр(UV), z=радиус(UV), w=фаза/сид 0..1
uniform int blob_n = 0;
uniform float blur = 0.0;            // «пьяное» размытие 0..1 (Пит, градус) — мылит жидкость и сгустки

void fragment() {
	float m = texture(mask, UV).a;
	if (m < 0.02) {
		COLOR = vec4(0.0);
	} else {
		float cx = (interior_left + interior_right) * 0.5;
		float base_top = interior_bot - (interior_bot - interior_top) * fill;

		// Поверхность: наклон от плескания + мягкая бегущая волна (сильнее при slosh)
		float dx = UV.x - cx;
		float wave = (0.004 + 0.010 * slosh) * sin(dx * 26.0 + TIME * 2.4)
		           + 0.0035 * sin(dx * 14.0 - TIME * 1.5);
		float liq_top = base_top + tilt * dx * aspect + wave;

		vec4 col = vec4(0.0);

		if (UV.y > liq_top) {
			float t = clamp((UV.y - liq_top) / max(0.0001, interior_bot - liq_top), 0.0, 1.0);
			vec3 topc = clamp(liquid_col.rgb * 1.22 + 0.03, vec3(0.0), vec3(1.0));
			vec3 botc = liquid_col.rgb * 0.60;
			col = vec4(mix(topc, botc, t), 0.96);
			// тень цилиндра по бокам
			float hw = (interior_right - interior_left) * 0.5;
			float sidex = clamp(abs(UV.x - cx) / max(0.0001, hw), 0.0, 1.0);
			col.rgb *= mix(1.06, 0.80, sidex);
			// блик поверхности (следует за наклонённой волной); мылится при blur
			col.rgb += smoothstep(0.012 + blur * 0.07, 0.0, abs(UV.y - liq_top)) * 0.45 * (1.0 - 0.6 * blur);
			// полутон
			vec2 gp = vec2(UV.x * aspect, UV.y) * 95.0;
			col.rgb *= mix(0.9, 1.0, smoothstep(0.30, 0.42, length(fract(gp) - 0.5)));
		}

		// сгустки: округлые «желейные» капли — светлая заливка, тёмная окаёмка,
		// блик сверху-слева и глянцевая точка. Слегка покачиваются и дрейфуют.
		for (int i = 0; i < 12; i++) {
			if (i >= blob_n) { break; }
			float br = blobs[i].z;
			float ph = blobs[i].w;

			// мягкий дрейф внутри жидкости + снос по плесканию (амплитуды малы,
			// чтобы капли не слипались и оставались считаемыми)
			vec2 c = blobs[i].xy;
			c.x += (0.006 + 0.008 * slosh) * sin(TIME * 0.55 + ph * 30.0) + tilt * 0.04;
			c.y += 0.008 * sin(TIME * 0.80 + ph * 18.0);

			vec2 dd = UV - c;
			dd.x *= aspect;
			float ang = atan(dd.y, dd.x);
			// почти круглый контур с лёгкой органикой (у каждой капли своя фаза)
			float wob = 1.0
			         + 0.055 * sin(ang * 3.0 + ph * 41.0 + TIME * 0.9)
			         + 0.030 * sin(ang * 5.0 - ph * 23.0 + TIME * 0.6);
			float reff = max(0.0001, br * wob);
			vec2 lp = dd / reff;
			float q = length(lp);

			// края мылятся при blur (пьяный градус) — сгусток теряет чёткость
			float edge = 0.05 + blur * 0.55;
			float alpha = 1.0 - smoothstep(1.0 - edge, 1.0, q);
			if (alpha > 0.001) {
				// светлая полупрозрачная заливка «пузыря» (ярче жидкости)
				vec3 fillc = clamp(liquid_col.rgb * 1.55 + 0.14, vec3(0.0), vec3(1.0));
				// объёмная подтень к низу-справа
				float shade = mix(1.12, 0.72, clamp(lp.x * 0.5 + lp.y * 0.6 + 0.5, 0.0, 1.0));
				vec3 body = fillc * shade;
				// КРУПНЫЙ мягкий блик сверху-слева (как на пузыре)
				float hl = 1.0 - smoothstep(0.0, 0.52, length(lp - vec2(-0.32, -0.40)));
				body = mix(body, clamp(fillc * 1.45 + 0.4, vec3(0.0), vec3(1.0)), hl * 0.8 * (1.0 - 0.5 * blur));
				// яркая глянцевая точка
				float glint = 1.0 - smoothstep(0.0, 0.16, length(lp - vec2(-0.30, -0.36)));
				body += glint * 0.6 * (1.0 - blur);
				// светлая обводка-ободок (приятный контур пузыря)
				float lite = smoothstep(0.66, 0.84, q) * (1.0 - smoothstep(0.84, 0.98, q));
				body += lite * 0.4 * (1.0 - 0.6 * blur);
				// тёмная окаёмка у самого края
				float rim = smoothstep(0.86, 0.995, q);
				body = mix(body, liquid_col.rgb * 0.25, rim * 0.8);
				col.rgb = mix(col.rgb, body, alpha);
			}
		}

		col.a *= m;   // клип по интерьеру бутыли
		COLOR = col;
	}
}
