extends Control
## 메인 UI 컨트롤러. UI 를 코드로 구성하고 게임 흐름을 관리한다.

const CauldronView := preload("res://scripts/cauldron_view.gd")

var cauldron: Control
var status_label: Label
var progress_bar: ProgressBar
var jar_row: HBoxContainer
var ing_grid: GridContainer
var time_slider: HSlider
var time_label: Label
var brew_btn: Button
var cancel_btn: Button
var detect_label: Label
var toast_label: Label

# 오버레이(보관함/도감/설정)
var overlay: PanelContainer
var overlay_title: Label
var overlay_content: VBoxContainer
var current_panel := ""   # "", "inventory", "recipes", "settings"

# 설정 패널 라이브 갱신용 참조
var live_external_label: Label
var live_detect_label: Label

var _was_brewing := false
var _save_accum := 0.0

func _ready() -> void:
	# 창 설정
	var win := get_window()
	win.title = "🧪 물약 공방"
	win.always_on_top = true

	# 테마(한글 폰트)
	var th := Theme.new()
	var font := _load_korean_font()
	if font:
		th.default_font = font
	th.default_font_size = 15
	theme = th

	_build_ui()
	_connect_signals()

	# 제작 진행 타이머 (0.5초 간격)
	var t := Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	t.timeout.connect(_on_tick)
	add_child(t)

	_was_brewing = GameState.brew != null
	refresh_all()

func _load_korean_font() -> FontFile:
	var candidates := [
		"C:/Windows/Fonts/malgun.ttf",
		"C:/Windows/Fonts/malgunbd.ttf",
		"C:/Windows/Fonts/gulim.ttc",
		"C:/Windows/Fonts/batang.ttc",
		"C:/Windows/Fonts/NanumGothic.ttf",
	]
	for p in candidates:
		if FileAccess.file_exists(p):
			var f := FontFile.new()
			if f.load_dynamic_font(p) == OK:
				return f
	return null

# ============================================================
# UI 구성
# ============================================================
func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("1d1830")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)

	# --- 헤더 ---
	var header := HBoxContainer.new()
	vb.add_child(header)
	var title := Label.new()
	title.text = "🧪 물약 공방"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_mk_icon_button("📦", func(): _open_panel("inventory")))
	header.add_child(_mk_icon_button("📖", func(): _open_panel("recipes")))
	header.add_child(_mk_icon_button("⚙", func(): _open_panel("settings")))

	# --- 항아리 뷰 ---
	cauldron = CauldronView.new()
	cauldron.custom_minimum_size = Vector2(0, 230)
	cauldron.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cauldron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(cauldron)

	# --- 상태 라벨 ---
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.text = ""
	vb.add_child(status_label)

	# --- 진행 바 ---
	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 14)
	vb.add_child(progress_bar)

	# --- 항아리 재료 칩 ---
	var jar_head := HBoxContainer.new()
	vb.add_child(jar_head)
	var jl := Label.new()
	jl.text = "항아리:"
	jl.add_theme_color_override("font_color", Color("b9aee0"))
	jar_head.add_child(jl)
	jar_row = HBoxContainer.new()
	jar_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jar_head.add_child(jar_row)
	var clear_btn := Button.new()
	clear_btn.text = "비우기"
	clear_btn.pressed.connect(func(): GameState.clear_jar())
	jar_head.add_child(clear_btn)

	# --- 재료 트레이 ---
	var tray_lbl := Label.new()
	tray_lbl.text = "재료 담기 (최대 %d개)" % GameState.MAX_INGREDIENTS
	tray_lbl.add_theme_color_override("font_color", Color("b9aee0"))
	vb.add_child(tray_lbl)

	ing_grid = GridContainer.new()
	ing_grid.columns = 4
	ing_grid.add_theme_constant_override("h_separation", 6)
	ing_grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(ing_grid)
	for id in Recipes.INGREDIENTS.keys():
		var info = Recipes.INGREDIENTS[id]
		var b := Button.new()
		b.text = "● " + info.name
		b.add_theme_color_override("font_color", info.color)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cap_id: String = id
		b.pressed.connect(func(): _on_add_ingredient(cap_id))
		ing_grid.add_child(b)

	# --- 시간 설정 ---
	var time_head := HBoxContainer.new()
	vb.add_child(time_head)
	var tlab := Label.new()
	tlab.text = "제작 시간"
	tlab.add_theme_color_override("font_color", Color("b9aee0"))
	time_head.add_child(tlab)
	time_slider = HSlider.new()
	time_slider.min_value = 1
	time_slider.max_value = 120
	time_slider.step = 1
	time_slider.value = 10
	time_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_slider.value_changed.connect(func(_v): _update_time_label())
	time_head.add_child(time_slider)
	time_label = Label.new()
	time_label.custom_minimum_size = Vector2(52, 0)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_head.add_child(time_label)

	# --- 제작 / 취소 버튼 ---
	brew_btn = Button.new()
	brew_btn.text = "제작 시작"
	brew_btn.custom_minimum_size = Vector2(0, 40)
	brew_btn.add_theme_font_size_override("font_size", 18)
	brew_btn.pressed.connect(_on_brew_pressed)
	vb.add_child(brew_btn)

	cancel_btn = Button.new()
	cancel_btn.text = "제작 취소 (재료 회수)"
	cancel_btn.pressed.connect(func(): GameState.cancel_brew())
	cancel_btn.visible = false
	vb.add_child(cancel_btn)

	# --- 감지 상태 라벨 ---
	detect_label = Label.new()
	detect_label.add_theme_font_size_override("font_size", 12)
	detect_label.add_theme_color_override("font_color", Color("7f75a0"))
	detect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(detect_label)

	# --- 오버레이 ---
	_build_overlay()

	# --- 토스트 ---
	toast_label = Label.new()
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.position = Vector2(0, 60)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 20)
	toast_label.modulate = Color(1, 1, 1, 0)
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_label)

	_update_time_label()

func _mk_icon_button(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(38, 34)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	return b

func _build_overlay() -> void:
	overlay = PanelContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("221c38")
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	overlay.add_theme_stylebox_override("panel", sb)
	add_child(overlay)

	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 8)
	overlay.add_child(ov)

	var head := HBoxContainer.new()
	ov.add_child(head)
	overlay_title = Label.new()
	overlay_title.add_theme_font_size_override("font_size", 20)
	overlay_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(overlay_title)
	head.add_child(_mk_icon_button("✕", func(): _close_panel()))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ov.add_child(scroll)
	overlay_content = VBoxContainer.new()
	overlay_content.add_theme_constant_override("separation", 8)
	overlay_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(overlay_content)

func _connect_signals() -> void:
	GameState.jar_changed.connect(refresh_jar)
	GameState.brew_changed.connect(_on_brew_changed)
	GameState.inventory_changed.connect(func(): if current_panel == "inventory": _fill_inventory())
	GameState.apps_changed.connect(func(): if current_panel == "settings": _fill_settings())

# ============================================================
# 이벤트
# ============================================================
func _on_add_ingredient(id: String) -> void:
	if not GameState.add_ingredient(id):
		if GameState.brew != null:
			_show_toast("제작 중에는 재료를 넣을 수 없어요")
		else:
			_show_toast("항아리가 가득 찼어요")

func _on_brew_pressed() -> void:
	if GameState.brew != null:
		return
	if GameState.jar_ingredients.is_empty():
		_show_toast("재료를 먼저 넣어주세요")
		return
	GameState.start_brew(time_slider.value)
	_show_toast("제작 시작! PC를 사용하면 진행돼요")

func _on_brew_changed() -> void:
	var brewing := GameState.brew != null
	if _was_brewing and not brewing:
		# 방금 완성됨 — 마지막으로 만든 물약 안내
		cauldron.result_flash = 1.0
		var last := _latest_potion_name()
		if last != "":
			_show_toast("✨ %s 완성!" % last)
	_was_brewing = brewing
	refresh_all()

func _latest_potion_name() -> String:
	# inventory 중 방금 추가된 것을 정확히 알긴 어렵지만, 안내용으로 최근 항목 표시
	var names := []
	for id in GameState.inventory.keys():
		names.append(GameState.inventory[id].name)
	if names.is_empty():
		return ""
	return names[names.size() - 1]

func _on_tick() -> void:
	var active := Watcher.is_pc_active()
	GameState.tick_brew(0.5, active)

	cauldron.brewing = GameState.brew != null
	cauldron.active = active and GameState.brew != null
	cauldron.progress = GameState.brew_progress()

	refresh_status()

	# 설정 패널이 열려 있으면 라이브 정보 갱신
	if current_panel == "settings":
		_update_settings_live()

	# 주기적 저장 (10초)
	_save_accum += 0.5
	if _save_accum >= 10.0:
		_save_accum = 0.0
		if GameState.brew != null:
			GameState.save_game()

# ============================================================
# 새로고침
# ============================================================
func refresh_all() -> void:
	refresh_jar()
	refresh_controls()
	refresh_status()

func refresh_jar() -> void:
	for c in jar_row.get_children():
		c.queue_free()
	var colors := []
	if GameState.brew != null:
		for id in GameState.brew.ings:
			colors.append(Recipes.ingredient_color(id))
			var lbl := Label.new()
			lbl.text = "● " + Recipes.ingredient_name(id)
			lbl.add_theme_color_override("font_color", Recipes.ingredient_color(id))
			jar_row.add_child(lbl)
	else:
		if GameState.jar_ingredients.is_empty():
			var e := Label.new()
			e.text = "(비어 있음)"
			e.add_theme_color_override("font_color", Color("6a6088"))
			jar_row.add_child(e)
		for i in range(GameState.jar_ingredients.size()):
			var id: String = GameState.jar_ingredients[i]
			colors.append(Recipes.ingredient_color(id))
			var idx := i
			var b := Button.new()
			b.text = Recipes.ingredient_name(id) + " ✕"
			b.add_theme_color_override("font_color", Recipes.ingredient_color(id))
			b.pressed.connect(func(): GameState.remove_ingredient_at(idx))
			jar_row.add_child(b)
	cauldron.liquid_colors = colors
	refresh_controls()

func refresh_controls() -> void:
	var brewing := GameState.brew != null
	brew_btn.visible = not brewing
	cancel_btn.visible = brewing
	brew_btn.disabled = GameState.jar_ingredients.is_empty()
	time_slider.editable = not brewing
	for b in ing_grid.get_children():
		if b is Button:
			b.disabled = brewing or GameState.jar_ingredients.size() >= GameState.MAX_INGREDIENTS

func refresh_status() -> void:
	if GameState.brew != null:
		var p := GameState.brew_progress()
		progress_bar.value = p
		var real_remain := GameState.brew_remaining_sec() / maxf(GameState.time_scale, 0.001)
		var st := "제작 중… %d%%" % int(p * 100)
		if GameState.brew.active:
			st += "  ·  남은 활동시간 %s" % _fmt_time(real_remain)
		else:
			st += "  ·  대기 중 (등록한 앱을 사용하세요)"
		status_label.text = st
	else:
		progress_bar.value = 0.0
		if GameState.jar_ingredients.is_empty():
			status_label.text = "재료를 넣고 시간을 정한 뒤 제작을 시작하세요"
		else:
			status_label.text = "준비 완료 — 제작을 시작하세요"
	detect_label.text = Watcher.status_text()

func _update_time_label() -> void:
	time_label.text = "%d분" % int(time_slider.value)

func _fmt_time(sec: float) -> String:
	var s := int(round(sec))
	var h := s / 3600
	var m := (s % 3600) / 60
	var ss := s % 60
	if h > 0:
		return "%d시간 %d분" % [h, m]
	if m > 0:
		return "%d분 %d초" % [m, ss]
	return "%d초" % ss

# ============================================================
# 오버레이 패널
# ============================================================
func _open_panel(which: String) -> void:
	current_panel = which
	overlay.visible = true
	match which:
		"inventory":
			overlay_title.text = "📦 보관함"
			_fill_inventory()
		"recipes":
			overlay_title.text = "📖 레시피 도감"
			_fill_recipes()
		"settings":
			overlay_title.text = "⚙ 설정"
			_fill_settings()

func _close_panel() -> void:
	current_panel = ""
	overlay.visible = false

func _clear_overlay() -> void:
	for c in overlay_content.get_children():
		c.queue_free()

func _fill_inventory() -> void:
	_clear_overlay()
	if GameState.inventory.is_empty():
		var e := Label.new()
		e.text = "아직 만든 물약이 없어요."
		overlay_content.add_child(e)
		return
	for id in GameState.inventory.keys():
		var p = GameState.inventory[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var sw := ColorRect.new()
		sw.color = GameState.arr_to_color(p.color)
		sw.custom_minimum_size = Vector2(28, 28)
		row.add_child(sw)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var n := Label.new()
		n.text = "%s  ×%d" % [p.name, p.count]
		n.add_theme_font_size_override("font_size", 16)
		box.add_child(n)
		var d := Label.new()
		d.text = p.get("desc", "")
		d.add_theme_font_size_override("font_size", 12)
		d.add_theme_color_override("font_color", Color("9a90bc"))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(d)
		row.add_child(box)
		overlay_content.add_child(row)
		overlay_content.add_child(_hsep())

func _fill_recipes() -> void:
	_clear_overlay()
	var intro := Label.new()
	intro.text = "재료 조합과 시간대에 따라 다른 물약이 만들어집니다. 발견하면 이름이 공개돼요."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color("9a90bc"))
	overlay_content.add_child(intro)
	overlay_content.add_child(_hsep())
	for r in Recipes.RECIPES:
		var found: bool = GameState.discovered.has(r.id)
		var box := VBoxContainer.new()
		var title := Label.new()
		title.add_theme_font_size_override("font_size", 16)
		if found:
			title.text = "✔ " + r.name
			title.add_theme_color_override("font_color", r.color)
		else:
			title.text = "❓ 미발견 물약"
			title.add_theme_color_override("font_color", Color("8a80a6"))
		box.add_child(title)
		var ings := []
		for iid in r.ing:
			ings.append(Recipes.ingredient_name(iid))
		var info := Label.new()
		info.text = "재료: %s   ·   시간: %d~%d분" % [", ".join(ings), r.min, r.max]
		info.add_theme_font_size_override("font_size", 12)
		info.add_theme_color_override("font_color", Color("b9aee0"))
		box.add_child(info)
		if found:
			var d := Label.new()
			d.text = r.desc
			d.add_theme_font_size_override("font_size", 12)
			d.add_theme_color_override("font_color", Color("9a90bc"))
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(d)
		overlay_content.add_child(box)
		overlay_content.add_child(_hsep())

func _fill_settings() -> void:
	_clear_overlay()

	var guide := Label.new()
	guide.text = "PC 사용 감지: 아래에 등록한 프로그램이 화면 맨 앞(활성 창)일 때 '사용 중'으로 판단해 제작이 진행됩니다.\n\n등록 방법: 원하는 프로그램(예: 크롬)을 클릭해 활성화한 뒤, 이 창으로 돌아와 '현재 창 등록'을 누르세요."
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide.add_theme_color_override("font_color", Color("b9aee0"))
	overlay_content.add_child(guide)

	live_detect_label = Label.new()
	live_detect_label.add_theme_font_size_override("font_size", 12)
	live_detect_label.add_theme_color_override("font_color", Color("7fd0a0"))
	live_detect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_content.add_child(live_detect_label)

	live_external_label = Label.new()
	live_external_label.add_theme_font_size_override("font_size", 13)
	live_external_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_content.add_child(live_external_label)

	var add_btn := Button.new()
	add_btn.text = "➕ 현재(마지막) 외부 창 등록"
	add_btn.pressed.connect(_on_add_current_window)
	overlay_content.add_child(add_btn)

	overlay_content.add_child(_hsep())

	var reg_lbl := Label.new()
	reg_lbl.text = "등록된 프로그램"
	reg_lbl.add_theme_font_size_override("font_size", 16)
	overlay_content.add_child(reg_lbl)

	if GameState.registered_apps.is_empty():
		var e := Label.new()
		e.text = "(없음) — 위에서 프로그램을 등록하세요."
		e.add_theme_color_override("font_color", Color("8a80a6"))
		overlay_content.add_child(e)
	else:
		for i in range(GameState.registered_apps.size()):
			var a = GameState.registered_apps[i]
			var row := HBoxContainer.new()
			var nm := Label.new()
			var t: String = a.get("title", "")
			nm.text = a.name + ("  (%s)" % t if t.strip_edges() != "" else "")
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.add_theme_font_size_override("font_size", 13)
			row.add_child(nm)
			var idx := i
			var del := Button.new()
			del.text = "삭제"
			del.pressed.connect(func(): GameState.remove_app_at(idx))
			row.add_child(del)
			overlay_content.add_child(row)

	overlay_content.add_child(_hsep())

	# --- 테스트 옵션 ---
	var test_lbl := Label.new()
	test_lbl.text = "테스트 옵션"
	test_lbl.add_theme_font_size_override("font_size", 16)
	overlay_content.add_child(test_lbl)

	var force_cb := CheckBox.new()
	force_cb.text = "강제 진행 (PC 사용 여부 무시)"
	force_cb.button_pressed = GameState.force_active
	force_cb.toggled.connect(func(on):
		GameState.force_active = on
		GameState.save_game())
	overlay_content.add_child(force_cb)

	var speed_row := HBoxContainer.new()
	var sl := Label.new()
	sl.text = "제작 속도:"
	speed_row.add_child(sl)
	for mult in [1.0, 10.0, 60.0]:
		var b := Button.new()
		b.toggle_mode = true
		b.text = "%d배" % int(mult)
		b.button_pressed = is_equal_approx(GameState.time_scale, mult)
		var m: float = mult
		b.pressed.connect(func():
			GameState.time_scale = m
			GameState.save_game()
			_fill_settings())
		speed_row.add_child(b)
	overlay_content.add_child(speed_row)

	_update_settings_live()

func _update_settings_live() -> void:
	if live_detect_label:
		live_detect_label.text = Watcher.status_text()
	if live_external_label:
		var nm := Watcher.last_external_name
		if nm == "":
			live_external_label.text = "현재 감지된 외부 창: (없음 — 다른 프로그램을 클릭해 보세요)"
			live_external_label.add_theme_color_override("font_color", Color("8a80a6"))
		else:
			var reg = " ✔ 이미 등록됨" if GameState.is_app_registered(nm) else ""
			live_external_label.text = "현재 감지된 외부 창: %s%s" % [Watcher._display(nm, Watcher.last_external_title), reg]
			live_external_label.add_theme_color_override("font_color", Color("ffd447"))

func _on_add_current_window() -> void:
	var nm := Watcher.last_external_name
	if nm == "":
		_show_toast("먼저 다른 프로그램을 클릭해 활성화하세요")
		return
	if GameState.add_app(nm, Watcher.last_external_title):
		_show_toast("등록됨: %s" % nm)
	else:
		_show_toast("이미 등록된 프로그램이에요")

# ============================================================
# 유틸
# ============================================================
func _hsep() -> HSeparator:
	return HSeparator.new()

func _show_toast(text: String) -> void:
	toast_label.text = text
	toast_label.modulate = Color(1, 1, 1, 1)
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(toast_label, "modulate:a", 0.0, 0.6)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GameState.save_game()
		Watcher.stop_helper()
		get_tree().quit()
