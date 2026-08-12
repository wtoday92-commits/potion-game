extends Node
## «Сок» — переиспользуемые хелперы анимации (автозагрузка `Juice`). Всё на
## Tween/частицах, без ассетов. Цель — чтобы любой экран/механика оживали одним
## вызовом, а не ad-hoc твинами по месту. Держим тут, чтобы стиль был единым.

# Плавное появление узла (фейд по альфе). Для смены экранов.
func fade_in(node: CanvasItem, dur: float = 0.18) -> void:
	if node == null:
		return
	node.modulate.a = 0.0
	var t := node.create_tween()
	t.tween_property(node, "modulate:a", 1.0, dur).set_ease(Tween.EASE_OUT)

# Каскадное появление списка узлов (по очереди, фейдом). Безопасно в контейнерах
# (позицию не трогаем — её перезапишет layout, только альфа).
func stagger_fade(nodes: Array, step: float = 0.08, dur: float = 0.26) -> void:
	var d: float = 0.0
	for n in nodes:
		var ci := n as CanvasItem
		if ci != null:
			ci.modulate.a = 0.0
			var t: Tween = ci.create_tween()
			t.tween_interval(d)
			t.tween_property(ci, "modulate:a", 1.0, dur).set_ease(Tween.EASE_OUT)
			d += step

# «Печать»: прилетает крупным и ужимается до 1.0 с overshoot + доводка поворота.
func pop(node: Control, from_scale: float = 1.6, dur: float = 0.42) -> void:
	if node == null:
		return
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(from_scale, from_scale)
	node.rotation = deg_to_rad(7.0)
	var t := node.create_tween()
	t.set_parallel(true)
	t.tween_property(node, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "rotation", 0.0, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Бесконечный мягкий пульс (акцент на элементе).
func pulse(node: Control, amp: float = 1.06, dur: float = 0.7) -> void:
	if node == null:
		return
	node.pivot_offset = node.size * 0.5
	var t := node.create_tween().set_loops()
	t.tween_property(node, "scale", Vector2(amp, amp), dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(node, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# Плавный «набег» числа в подписи (рейтинг/чаевые/опыт).
func count_up(label: Label, from_val: int, to_val: int, fmt: String = "%d", dur: float = 0.5) -> void:
	if label == null:
		return
	var t := label.create_tween()
	t.tween_method(func(v: float): label.text = fmt % int(round(v)), float(from_val), float(to_val), dur)

# Всплеск частиц (конфетти/искры) в глобальной точке. parent — узел в дереве,
# частицы сами удаляются. Один вызов на «идеал»/успех.
func burst(parent: Node, at_global: Vector2, color: Color, amount: int = 28) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var p := CPUParticles2D.new()
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.9
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 170.0
	p.initial_velocity_max = 340.0
	p.gravity = Vector2(0, 620)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	p.color = color
	parent.add_child(p)
	p.global_position = at_global
	var tm := parent.get_tree().create_timer(1.8)
	tm.timeout.connect(p.queue_free)
