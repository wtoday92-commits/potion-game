shader_type canvas_item;
// Тёмный текстурный фон-подложка под портретом NPC — как внутри металлической
// рамки (frame_round_src.png): холодный сине-серый радиальный градиент + полутон
// (halftone) + виньетка по краю. Круглая маска: снаружи прозрачно, чтобы за
// кольцом просвечивал цветной ореол тира. Радиус подобран под проём рамки.

uniform vec3 center_col : source_color = vec3(0.17, 0.22, 0.24);
uniform vec3 edge_col : source_color = vec3(0.07, 0.10, 0.11);
uniform float radius = 0.72;    // радиус круга (в долях полуширины контрола)

void fragment() {
	vec2 p = UV - 0.5;
	float d = length(p) * 2.0;   // 0 в центре, 1 у края контрола

	vec3 col = mix(center_col, edge_col, smoothstep(0.0, 1.05, d));

	// полутон — мягкие точки
	vec2 g = fract(UV * 46.0) - 0.5;
	float dots = smoothstep(0.34, 0.28, length(g));
	col *= mix(1.0, 0.87, dots);

	// виньетка: темнее к ободу
	col *= mix(1.0, 0.62, smoothstep(radius * 0.6, radius, d));

	float a = 1.0 - smoothstep(radius - 0.03, radius, d);
	COLOR = vec4(col, a);
}
