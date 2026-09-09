extends Control
## 항아리 + 연금술사 캐릭터를 코드로 그리는 위젯.
## main 이 아래 상태 변수를 갱신하면 애니메이션/그림이 바뀐다.
## 가방에서 재료를 드래그해 이 위에 놓으면 항아리에 담긴다.

signal ingredient_dropped(id)

var drop_hover: bool = false   # 드래그한 재료가 위에 올라와 있는지

var brewing: bool = false          # 제작 중인지
var active: bool = false            # 현재 PC 사용 중(진행 중)인지
var progress: float = 0.0          # 0..1
var liquid_colors: Array = []      # 항아리에 담긴 재료 색 목록(Color)
var result_flash: float = 0.0      # 완성 연출용(0..1, main 이 트리거)

var _t: float = 0.0
var _bubbles: Array = []           # {x, y, r, speed}

func _ready() -> void:
	for i in range(10):
		_bubbles.append(_new_bubble())

func _can_drop_data(_at_position: Vector2, data) -> bool:
	var ok: bool = typeof(data) == TYPE_DICTIONARY and data.get("type", "") == "ingredient"
	if ok != drop_hover:
		drop_hover = ok
		queue_redraw()
	return ok

func _drop_data(_at_position: Vector2, data) -> void:
	drop_hover = false
	ingredient_dropped.emit(String(data.get("id", "")))

func _new_bubble() -> Dictionary:
	return {
		"x": randf_range(0.35, 0.65),
		"y": randf_range(0.0, 1.0),
		"r": randf_range(2.5, 6.0),
		"speed": randf_range(0.15, 0.4),
	}

func _process(delta: float) -> void:
	_t += delta
	# 드래그가 끝났는데 하이라이트가 남아있으면 해제
	if drop_hover and not get_viewport().gui_is_dragging():
		drop_hover = false
	if result_flash > 0.0:
		result_flash = maxf(result_flash - delta * 0.8, 0.0)
	# 활발히 제작 중일 때만 거품이 빠르게 올라온다.
	var rate := 1.0 if active else 0.15
	for b in _bubbles:
		b.y -= b.speed * delta * rate
		if b.y < 0.0:
			b.x = randf_range(0.35, 0.65)
			b.y = 1.0
			b.r = randf_range(2.5, 6.0)
	queue_redraw()

func _liquid_color() -> Color:
	if liquid_colors.is_empty():
		return Color("2a2340")  # 빈 항아리(어두운 액체)
	var r := 0.0; var g := 0.0; var bl := 0.0
	for c in liquid_colors:
		r += c.r; g += c.g; bl += c.b
	var n := float(liquid_colors.size())
	return Color(r / n, g / n, bl / n, 1.0)

func _ellipse(center: Vector2, rx: float, ry: float, n: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

func _draw() -> void:
	var w := size.x
	var h := size.y
	var cx := w * 0.5

	# --- 좌표 기준 ---
	var pot_cx := cx
	var pot_top_y := h * 0.42
	var pot_bot_y := h * 0.90
	var pot_top_r := w * 0.30
	var pot_bot_r := w * 0.24
	var rim_ry := pot_top_r * 0.34

	# --- 바닥 그림자 ---
	draw_colored_polygon(_ellipse(Vector2(pot_cx, pot_bot_y + 6), pot_bot_r * 1.05, 12), Color(0, 0, 0, 0.18))

	# --- 항아리 뒤쪽 림(테두리) ---
	draw_colored_polygon(_ellipse(Vector2(pot_cx, pot_top_y), pot_top_r, rim_ry), Color("3a3350"))

	# --- 액체 ---
	var liquid := _liquid_color()
	var fill = 0.35 + progress * 0.5 if brewing else (0.5 if not liquid_colors.is_empty() else 0.35)
	var liquid_top_y = lerp(pot_bot_y - 8, pot_top_y + rim_ry * 0.4, fill)
	# 액체 옆면(사다리꼴)
	var liq_top_r = lerp(pot_bot_r, pot_top_r, (liquid_top_y - pot_bot_y) / (pot_top_y - pot_bot_y))
	var side := PackedVector2Array([
		Vector2(pot_cx - liq_top_r, liquid_top_y),
		Vector2(pot_cx + liq_top_r, liquid_top_y),
		Vector2(pot_cx + pot_bot_r, pot_bot_y),
		Vector2(pot_cx - pot_bot_r, pot_bot_y),
	])
	draw_colored_polygon(side, liquid.darkened(0.15))
	# 액체 표면(타원)
	var surf := _ellipse(Vector2(pot_cx, liquid_top_y), liq_top_r, liq_top_r * 0.32)
	draw_colored_polygon(surf, liquid)
	var wobble := sin(_t * 3.0) * 0.04 + 1.0
	draw_colored_polygon(_ellipse(Vector2(pot_cx, liquid_top_y), liq_top_r * 0.5 * wobble, liq_top_r * 0.16), liquid.lightened(0.18))

	# --- 거품 ---
	if brewing:
		for b in _bubbles:
			var bx = pot_cx + (b.x - 0.5) * liq_top_r * 1.6
			var by = lerp(pot_bot_y, liquid_top_y, b.y)
			if by < liquid_top_y:
				continue
			draw_circle(Vector2(bx, by), b.r, liquid.lightened(0.3))

	# --- 항아리 앞면(반투명 유리) ---
	var body := PackedVector2Array([
		Vector2(pot_cx - pot_top_r, pot_top_y),
		Vector2(pot_cx + pot_top_r, pot_top_y),
		Vector2(pot_cx + pot_bot_r, pot_bot_y),
		Vector2(pot_cx - pot_bot_r, pot_bot_y),
	])
	draw_colored_polygon(body, Color(0.75, 0.85, 1.0, 0.12))
	# 유리 하이라이트
	draw_line(Vector2(pot_cx - pot_top_r * 0.6, pot_top_y + rim_ry),
		Vector2(pot_cx - pot_bot_r * 0.6, pot_bot_y - 10),
		Color(1, 1, 1, 0.18), 6.0)
	# 앞쪽 림 (드래그 재료가 위에 있으면 강조)
	var rim := _ellipse(Vector2(pot_cx, pot_top_y), pot_top_r, rim_ry)
	if drop_hover:
		draw_polyline(_close(rim), Color("ffe680"), 6.0)
	else:
		draw_polyline(_close(rim), Color("cfc7e0"), 4.0)

	# --- 연금술사 캐릭터 ---
	_draw_character(Vector2(w * 0.14, pot_top_y + 6), liquid)

	# --- 상태 이펙트 ---
	if brewing and not active:
		# 대기 중: Zzz
		var zp := Vector2(pot_cx + pot_top_r * 0.7, pot_top_y - 10)
		_draw_zzz(zp)
	if result_flash > 0.0:
		var a := result_flash
		draw_colored_polygon(_ellipse(Vector2(pot_cx, liquid_top_y), liq_top_r * (1.3 + (1.0 - a)), liq_top_r * 0.6 * (1.3 + (1.0 - a))), Color(1, 1, 0.8, 0.35 * a))

func _close(p: PackedVector2Array) -> PackedVector2Array:
	var q = p.duplicate()
	if q.size() > 0:
		q.append(q[0])
	return q

func _draw_character(base: Vector2, liquid: Color) -> void:
	# base = 캐릭터 발 근처 기준점(항아리 왼쪽)
	var bob := 0.0
	var stir := 0.0
	if brewing and active:
		bob = sin(_t * 6.0) * 3.0
		stir = _t * 7.0
	elif brewing and not active:
		bob = sin(_t * 1.2) * 1.5  # 꾸벅꾸벅
	var body_c := Color("6b4fb0")   # 로브
	var skin := Color("f2c9a0")
	var hat := Color("4a3488")

	var hip := base + Vector2(0, bob)
	# 로브(삼각형 몸통)
	draw_colored_polygon(PackedVector2Array([
		hip + Vector2(-18, 0), hip + Vector2(18, 0), hip + Vector2(10, -46), hip + Vector2(-10, -46),
	]), body_c)
	# 머리
	var head := hip + Vector2(0, -58)
	draw_circle(head, 12, skin)
	# 모자(고깔)
	draw_colored_polygon(PackedVector2Array([
		head + Vector2(-14, -6), head + Vector2(14, -6), head + Vector2(0, -34),
	]), hat)
	draw_colored_polygon(_ellipse(head + Vector2(0, -6), 16, 5), hat.lightened(0.1))
	# 눈
	draw_circle(head + Vector2(-4, 0), 1.6, Color.BLACK)
	draw_circle(head + Vector2(4, 0), 1.6, Color.BLACK)
	# 젓는 팔 + 국자
	var shoulder := hip + Vector2(12, -40)
	var hand := shoulder + Vector2(cos(stir) * 8 + 22, sin(stir) * 6 + 6)
	draw_line(shoulder, hand, body_c.darkened(0.1), 5.0)
	draw_line(hand, hand + Vector2(6, 14), Color("caa76a"), 3.0)  # 국자 손잡이
	draw_circle(hand + Vector2(6, 16), 4, liquid)

func _draw_zzz(p: Vector2) -> void:
	var font := get_theme_default_font()
	var fs := 14
	var col := Color(1, 1, 1, 0.7)
	var off := sin(_t * 2.0) * 3.0
	if font:
		draw_string(font, p + Vector2(0, off), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		draw_string(font, p + Vector2(9, -8 + off), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 3, col)
		draw_string(font, p + Vector2(20, -18 + off), "Z", HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 6, col)
