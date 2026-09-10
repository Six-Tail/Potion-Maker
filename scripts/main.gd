extends Control
## 메인 UI 컨트롤러. UI 를 코드로 구성하고 게임 흐름을 관리한다.

const CauldronView := preload("res://scripts/cauldron_view.gd")
const BagItem := preload("res://scripts/bag_item.gd")

var cauldron: Control
var status_label: Label
var remain_label: Label
var progress_bar: ProgressBar
var jar_slots_row: HBoxContainer
var clear_btn: Button
var bag_grid: GridContainer
var bag_buttons: Dictionary = {}   # 재료 id -> BagItem 버튼
var time_input: LineEdit
var grade_hint: RichTextLabel
var brew_btn: Button
var cancel_btn: Button
var detect_label: Label
var coins_label: Label
var toast_label: Label
var lv_label: Label
var xp_bar: ProgressBar
var xp_text: Label

# 전체 UI 루트(테마 변경 시 통째로 다시 만든다)
var _root: Control

# 오버레이(상점/보관함/도감/설정)
var overlay: PanelContainer
var overlay_title: Label
var overlay_content: VBoxContainer
var current_panel := ""

# 설정 패널 라이브 갱신용 참조
var live_external_label: Label
var live_detect_label: Label

# 창 본문 드래그 이동
var _dragging := false
var _drag_offset := Vector2i.ZERO

var _was_brewing := false
var _save_accum := 0.0

func _ready() -> void:
	var win := get_window()
	win.title = "🧪 물약 공방"
	win.always_on_top = true

	var th := Theme.new()
	var font := _load_korean_font()
	if font:
		th.default_font = font
	th.default_font_size = 15
	_apply_theme_colors(th)
	theme = th

	_build_ui()
	_connect_signals()

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
		"C:/Windows/Fonts/NanumGothic.ttf",
	]
	for p in candidates:
		if FileAccess.file_exists(p):
			var f := FontFile.new()
			if f.load_dynamic_font(p) == OK:
				# 이모지 폴백 (아이콘이 깨지지 않도록)
				var emoji := "C:/Windows/Fonts/seguiemj.ttf"
				if FileAccess.file_exists(emoji):
					var ef := FontFile.new()
					if ef.load_dynamic_font(emoji) == OK:
						f.fallbacks = [ef]
				return f
	return null

# ============================================================
# 테마
# ============================================================
## 현재 테마에 맞는 기본 글자색을 Theme 리소스에 반영한다.
## (색 지정이 없는 라벨/버튼/체크박스/입력창이 라이트·다크 모드에 맞게 보이도록)
## 둥근 StyleBoxFlat (여백 없음) — 카드/바/트랙 등에 사용
func _sb_plain(color: Color, radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	return sb

## 둥근 StyleBoxFlat (버튼용 내부 여백 포함)
func _sb_pad(color: Color, radius: int = 10, pv: int = 6, ph: int = 10) -> StyleBoxFlat:
	var sb := _sb_plain(color, radius)
	sb.content_margin_top = pv
	sb.content_margin_bottom = pv
	sb.content_margin_left = ph
	sb.content_margin_right = ph
	return sb

## 버튼을 지정 색(bg/글자)으로 스타일링(상태별 포함)
func _style_button(b: Button, bg: Color, fg: Color, radius: int = 12, pv: int = 6, ph: int = 10) -> void:
	b.add_theme_stylebox_override("normal", _sb_pad(bg, radius, pv, ph))
	b.add_theme_stylebox_override("hover", _sb_pad(bg.lightened(0.06), radius, pv, ph))
	b.add_theme_stylebox_override("pressed", _sb_pad(bg.darkened(0.08), radius, pv, ph))
	var dis := _sb_pad(bg, radius, pv, ph); dis.bg_color = Color(bg.r, bg.g, bg.b, 0.45)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_stylebox_override("focus", _sb_pad(Color.TRANSPARENT, radius, pv, ph))
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, fg)
	b.add_theme_color_override("font_disabled_color", Color(fg.r, fg.g, fg.b, 0.5))

func _apply_theme_colors(th: Theme) -> void:
	var t := GameState.col("text")
	for cls in ["Label", "Button", "CheckBox", "LineEdit"]:
		th.set_color("font_color", cls, t)
	th.set_color("font_hover_color", "Button", t)
	th.set_color("font_pressed_color", "Button", t)
	th.set_color("font_focus_color", "Button", t)
	th.set_color("font_hover_color", "CheckBox", t)
	th.set_color("font_pressed_color", "CheckBox", t)
	th.set_color("default_color", "RichTextLabel", t)

	# --- 기본 위젯 스타일(둥근 형태로 통일) ---
	var btn := GameState.col("slot")
	th.set_stylebox("normal", "Button", _sb_pad(btn, 10))
	th.set_stylebox("hover", "Button", _sb_pad(btn.lightened(0.05), 10))
	th.set_stylebox("pressed", "Button", _sb_pad(btn.darkened(0.07), 10))
	var bd := _sb_pad(btn, 10); bd.bg_color = Color(btn.r, btn.g, btn.b, 0.45)
	th.set_stylebox("disabled", "Button", bd)
	th.set_stylebox("focus", "Button", _sb_pad(Color.TRANSPARENT, 10))

	var le := _sb_pad(GameState.col("panel"), 8)
	le.set_border_width_all(1)
	le.border_color = GameState.col("border")
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", le)

	th.set_stylebox("background", "ProgressBar", _sb_plain(GameState.col("track"), 7))
	th.set_stylebox("fill", "ProgressBar", _sb_plain(GameState.col("progress"), 7))

	th.set_stylebox("panel", "PanelContainer", _sb_card(GameState.col("panel"), 14))

## 카드/패널용 둥근 스타일(넉넉한 내부 여백)
func _sb_card(color: Color, radius: int = 14) -> StyleBoxFlat:
	var sb := _sb_plain(color, radius)
	for m in ["content_margin_left", "content_margin_right", "content_margin_top", "content_margin_bottom"]:
		sb.set(m, 10)
	return sb

## 테마 변경 시 UI 를 통째로 다시 만들어 모든 색을 새 팔레트로 갱신한다.
func _rebuild_ui() -> void:
	var panel := current_panel
	current_panel = ""
	overlay = null
	if is_instance_valid(_root):
		_root.queue_free()
	bag_buttons.clear()
	_apply_theme_colors(theme)
	_build_ui()
	refresh_all()
	if panel != "":
		_open_panel(panel)

# ============================================================
# UI 구성
# ============================================================
func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = GameState.col("bg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vb)

	# --- 헤더 (제목 + 부제 + 코인 + 메뉴) ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	vb.add_child(header)
	var titlebox := VBoxContainer.new()
	titlebox.add_theme_constant_override("separation", 0)
	titlebox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titlebox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(titlebox)
	var title := Label.new()
	title.text = "물약 공방"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", GameState.col("text"))
	titlebox.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Your cozy work companion"
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", GameState.col("subtitle"))
	titlebox.add_child(subtitle)
	coins_label = Label.new()
	coins_label.add_theme_font_size_override("font_size", 15)
	coins_label.add_theme_color_override("font_color", GameState.col("gold"))
	coins_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(coins_label)
	header.add_child(_mk_icon_button("🛒", func(): _open_panel("shop")))
	header.add_child(_mk_icon_button("🎒", func(): _open_panel("inventory")))
	header.add_child(_mk_icon_button("📖", func(): _open_panel("recipes")))
	header.add_child(_mk_icon_button("⚙", func(): _open_panel("settings")))

	# --- 레벨 / 경험치 ---
	var lv_row := HBoxContainer.new()
	lv_row.add_theme_constant_override("separation", 6)
	lv_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(lv_row)
	lv_label = Label.new()
	lv_label.add_theme_font_size_override("font_size", 13)
	lv_label.add_theme_color_override("font_color", GameState.col("gold"))
	lv_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lv_row.add_child(lv_label)
	xp_bar = ProgressBar.new()
	xp_bar.min_value = 0.0
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size = Vector2(0, 8)
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv_row.add_child(xp_bar)
	xp_text = Label.new()
	xp_text.add_theme_font_size_override("font_size", 11)
	xp_text.add_theme_color_override("font_color", GameState.col("text_dim"))
	xp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lv_row.add_child(xp_text)

	# --- 상태 (● 상태) ---
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", GameState.col("success"))
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(status_label)

	# --- 진행 바 ---
	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 14)
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(progress_bar)

	# --- 남은 시간 안내 ---
	remain_label = Label.new()
	remain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	remain_label.add_theme_font_size_override("font_size", 12)
	remain_label.add_theme_color_override("font_color", GameState.col("text_muted"))
	remain_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(remain_label)

	# --- 캐릭터 카드 ---
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _sb_card(GameState.col("card"), 16))
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(card)
	cauldron = CauldronView.new()
	cauldron.custom_minimum_size = Vector2(0, 170)
	cauldron.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cauldron.mouse_filter = Control.MOUSE_FILTER_STOP
	cauldron.ingredient_dropped.connect(_on_add_ingredient)
	cauldron.character_tex = _load_character_tex()
	card.add_child(cauldron)

	# --- 항아리 슬롯 + 비우기 ---
	var jar_head := HBoxContainer.new()
	jar_head.add_theme_constant_override("separation", 6)
	jar_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(jar_head)
	jar_slots_row = HBoxContainer.new()
	jar_slots_row.add_theme_constant_override("separation", 8)
	jar_slots_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jar_head.add_child(jar_slots_row)
	clear_btn = Button.new()
	clear_btn.text = "비우기"
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.pressed.connect(func(): GameState.clear_jar())
	jar_head.add_child(clear_btn)

	# --- 제작하기 버튼 ---
	brew_btn = Button.new()
	brew_btn.text = "제작하기"
	brew_btn.custom_minimum_size = Vector2(0, 48)
	brew_btn.focus_mode = Control.FOCUS_NONE
	brew_btn.add_theme_font_size_override("font_size", 19)
	_style_button(brew_btn, GameState.col("accent"), GameState.col("accent_text"), 14, 10, 12)
	brew_btn.pressed.connect(_on_brew_pressed)
	vb.add_child(brew_btn)

	cancel_btn = Button.new()
	cancel_btn.text = "제작 취소 (재료 회수)"
	cancel_btn.custom_minimum_size = Vector2(0, 40)
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.pressed.connect(func(): GameState.cancel_brew())
	cancel_btn.visible = false
	vb.add_child(cancel_btn)

	# --- 제작 시간(텍스트 입력) ---
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 6)
	vb.add_child(time_row)
	var tlab := Label.new()
	tlab.text = "제작 시간"
	tlab.add_theme_color_override("font_color", GameState.col("text_muted"))
	tlab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_row.add_child(tlab)
	time_input = LineEdit.new()
	time_input.text = "10"
	time_input.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_input.custom_minimum_size = Vector2(70, 0)
	time_input.max_length = 3
	time_input.text_changed.connect(_on_time_text_changed)
	time_row.add_child(time_input)
	var minlab := Label.new()
	minlab.text = "분 (1~600)"
	minlab.add_theme_color_override("font_color", GameState.col("text_muted"))
	minlab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	minlab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_row.add_child(minlab)

	# --- 예상 등급 확률 ---
	grade_hint = RichTextLabel.new()
	grade_hint.bbcode_enabled = true
	grade_hint.fit_content = true
	grade_hint.scroll_active = false
	grade_hint.add_theme_font_size_override("normal_font_size", 12)
	grade_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(grade_hint)

	# --- 점선 구분 ---
	var divider := Label.new()
	divider.text = "· · · · · · · · · · · · · · · · · · · · · · · ·"
	divider.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	divider.add_theme_color_override("font_color", GameState.col("text_ghost"))
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(divider)

	# --- 재료 가방 ---
	var bag_label := Label.new()
	bag_label.text = "재료 가방"
	bag_label.add_theme_font_size_override("font_size", 13)
	bag_label.add_theme_color_override("font_color", GameState.col("text_muted"))
	bag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(bag_label)

	bag_grid = GridContainer.new()
	bag_grid.columns = 4
	bag_grid.add_theme_constant_override("h_separation", 8)
	bag_grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(bag_grid)
	for id in Recipes.INGREDIENTS.keys():
		var info = Recipes.INGREDIENTS[id]
		var b := BagItem.new()
		b.ing_id = id
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_color_override("font_color", info.color)
		var cap_id: String = id
		b.pressed.connect(func(): _on_add_ingredient(cap_id))
		bag_grid.add_child(b)
		bag_buttons[id] = b

	# --- 감지 상태(작게) ---
	detect_label = Label.new()
	detect_label.add_theme_font_size_override("font_size", 11)
	detect_label.add_theme_color_override("font_color", GameState.col("text_faint"))
	detect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(detect_label)

	_build_overlay()

	# --- 토스트 ---
	toast_label = Label.new()
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.position = Vector2(0, 96)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 18)
	toast_label.modulate = Color(1, 1, 1, 0)
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(toast_label)

## 캐릭터 일러스트를 로드(없으면 null → 코드 항아리 그림으로 대체)
func _load_character_tex() -> Texture2D:
	if ResourceLoader.exists("res://assets/character.png"):
		return load("res://assets/character.png")
	return null

func _mk_icon_button(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(38, 34)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(cb)
	return b

func _build_overlay() -> void:
	overlay = PanelContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = GameState.col("panel")
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	overlay.add_theme_stylebox_override("panel", sb)
	_root.add_child(overlay)

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
	GameState.jar_changed.connect(_on_jar_changed)
	GameState.brew_changed.connect(_on_brew_changed)
	GameState.inventory_changed.connect(func(): if current_panel == "inventory": _fill_inventory())
	GameState.apps_changed.connect(func(): if current_panel == "settings": _fill_settings())
	GameState.coins_changed.connect(_on_coins_changed)
	GameState.stock_changed.connect(_on_stock_changed)
	GameState.theme_changed.connect(_rebuild_ui)
	GameState.xp_changed.connect(_refresh_level)
	GameState.level_changed.connect(_on_level_up)

# ============================================================
# 창 본문 드래그 이동
# ============================================================
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _is_drag_area(get_viewport().gui_get_hovered_control()):
				_dragging = true
				_drag_offset = get_window().position - DisplayServer.mouse_get_position()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		get_window().position = DisplayServer.mouse_get_position() + _drag_offset

func _process(_delta: float) -> void:
	# 마우스 릴리즈를 놓친 경우 대비
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false

func _is_drag_area(c: Control) -> bool:
	if c == null:
		return true
	if c is Button or c is Slider or c is LineEdit or c is ScrollBar:
		return false
	return true

# ============================================================
# 이벤트
# ============================================================
func _on_add_ingredient(id: String) -> void:
	if id == "":
		return
	if not GameState.add_ingredient(id):
		if GameState.brew != null:
			_show_toast("제작 중에는 재료를 넣을 수 없어요")
		elif GameState.jar_ingredients.size() >= GameState.MAX_INGREDIENTS:
			_show_toast("항아리가 가득 찼어요")
		else:
			_show_toast("%s 재고가 없어요 (상점에서 구매)" % Recipes.ingredient_name(id))

func _on_time_text_changed(s: String) -> void:
	var clean := ""
	for ch in s:
		if ch >= "0" and ch <= "9":
			clean += ch
	if clean != s:
		time_input.text = clean
		time_input.caret_column = clean.length()
	_update_grade_hint()

func _update_grade_hint() -> void:
	if grade_hint == null:
		return
	var t := time_input.text.strip_edges()
	var m := clampi(int(t) if t.is_valid_int() else 0, 0, 600)
	# 현재 재료+시간으로 만들어질 물약을 판정해, 그 레시피의 시간범위 기준으로
	# 등급 확률을 보여준다. (레시피 없음/시간범위 밖이면 항상 일반)
	var res := Recipes.resolve(GameState.jar_ingredients, float(m))
	var p: Array
	if res.id != "unknown" and res.id != "failure":
		# 레시피 시간범위 내 위치 + 레벨 품질 보너스
		var q := Recipes.time_ratio(float(m), float(res.get("min", 1)), float(res.get("max", 1))) + GameState.level_bonus()
		p = Recipes.grade_probabilities_ratio(q)
	else:
		p = [1.0, 0.0, 0.0]
	grade_hint.text = "예상 등급   [color=#b8b8b8]★일반 %d%%[/color]    [color=#5fd06a]★희귀 %d%%[/color]    [color=#4a9bff]★고급 %d%%[/color]" % [roundi(p[0] * 100), roundi(p[1] * 100), roundi(p[2] * 100)]

func _read_minutes() -> int:
	var t := time_input.text.strip_edges()
	var m := int(t) if t.is_valid_int() else 10
	m = clampi(m, 1, 600)
	time_input.text = str(m)
	return m

func _on_brew_pressed() -> void:
	if GameState.brew != null:
		return
	if GameState.jar_ingredients.is_empty():
		_show_toast("재료를 먼저 넣어주세요")
		return
	GameState.start_brew(_read_minutes())
	_show_toast("제작 시작! 등록한 앱을 사용하면 진행돼요")

func _on_brew_changed() -> void:
	var brewing := GameState.brew != null
	if _was_brewing and not brewing:
		cauldron.result_flash = 1.0
		var last := GameState.last_made_name
		if last != "":
			var g := GameState.last_made_grade
			var gname := Recipes.grade_name(g)
			_show_toast("✨ ★%s %s 완성!" % [gname, last], Recipes.grade_color(g))
			if not get_window().has_focus():
				Watcher.notify("물약 공방 — 완성!", "[%s] %s 이(가) 완성되었어요." % [gname, last])
	_was_brewing = brewing
	refresh_all()

func _on_coins_changed() -> void:
	_refresh_coins()
	if current_panel == "shop":
		_fill_shop()
	elif current_panel == "inventory":
		_fill_inventory()

func _on_stock_changed() -> void:
	refresh_controls()
	if current_panel == "shop":
		_fill_shop()

func _on_jar_changed() -> void:
	refresh_jar_slots()
	refresh_controls()
	refresh_status()

func _on_tick() -> void:
	var active := Watcher.is_pc_active()
	GameState.tick_brew(0.5, active)

	cauldron.brewing = GameState.brew != null
	cauldron.active = active and GameState.brew != null
	cauldron.progress = GameState.brew_progress()

	refresh_status()
	if current_panel == "settings":
		_update_settings_live()

	_save_accum += 0.5
	if _save_accum >= 10.0:
		_save_accum = 0.0
		if GameState.brew != null:
			GameState.save_game()

# ============================================================
# 새로고침
# ============================================================
func refresh_all() -> void:
	refresh_jar_slots()
	refresh_controls()
	refresh_status()
	_refresh_level()

func _refresh_level() -> void:
	if lv_label == null:
		return
	var need := GameState.xp_for_next()
	lv_label.text = "⚗ Lv.%d" % GameState.level
	xp_bar.max_value = need
	xp_bar.value = GameState.xp
	xp_text.text = "%d/%d XP" % [GameState.xp, need]

func _on_level_up() -> void:
	_refresh_level()
	var bonus := int(round(GameState.level_bonus() * 100.0))
	_show_toast("⚗ 레벨 업! Lv.%d — 품질 보너스 +%d%%" % [GameState.level, bonus], GameState.col("gold"))

func refresh_jar_slots() -> void:
	for c in jar_slots_row.get_children():
		c.queue_free()
	var brewing := GameState.brew != null
	var ings: Array = GameState.brew.ings if brewing else GameState.jar_ingredients
	var colors := []
	for i in range(GameState.MAX_INGREDIENTS):
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(0, 46)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.focus_mode = Control.FOCUS_NONE
		slot.clip_text = true
		if i < ings.size():
			var id: String = ings[i]
			colors.append(Recipes.ingredient_color(id))
			slot.text = "● " + Recipes.ingredient_name(id)
			slot.add_theme_color_override("font_color", Recipes.ingredient_color(id))
			if brewing:
				slot.disabled = true
			else:
				var idx := i
				slot.tooltip_text = "클릭하면 가방으로 되돌립니다"
				slot.pressed.connect(func(): GameState.remove_ingredient_at(idx))
		else:
			slot.text = "＋"
			slot.disabled = true
			slot.add_theme_font_size_override("font_size", 20)
			slot.add_theme_color_override("font_disabled_color", GameState.col("slot_fg"))
		jar_slots_row.add_child(slot)
	cauldron.liquid_colors = colors

func refresh_controls() -> void:
	var brewing := GameState.brew != null
	brew_btn.visible = not brewing
	cancel_btn.visible = brewing
	brew_btn.disabled = GameState.jar_ingredients.is_empty()
	time_input.editable = not brewing
	clear_btn.visible = (not brewing) and not GameState.jar_ingredients.is_empty()
	var jar_full := GameState.jar_ingredients.size() >= GameState.MAX_INGREDIENTS
	for id in bag_buttons.keys():
		var b: Button = bag_buttons[id]
		var stock := GameState.available_stock(id)
		b.text = "%s %d" % [Recipes.ingredient_name(id), stock]
		b.disabled = brewing or jar_full or stock <= 0
	_refresh_coins()
	_update_grade_hint()

func _refresh_coins() -> void:
	if coins_label:
		coins_label.text = "🪙 %d" % GameState.coins

func refresh_status() -> void:
	if GameState.brew != null:
		var p := GameState.brew_progress()
		progress_bar.value = p
		var real_remain := GameState.brew_remaining_sec() / maxf(GameState.time_scale, 0.001)
		if GameState.brew.active:
			status_label.text = "● 일하는 중 (%d%%)" % int(p * 100)
			status_label.add_theme_color_override("font_color", GameState.col("success"))
			remain_label.text = "완성까지 %s 남았어요." % _fmt_time(real_remain)
		else:
			status_label.text = "● 대기 중 (%d%%)" % int(p * 100)
			status_label.add_theme_color_override("font_color", GameState.col("text_dim"))
			remain_label.text = "등록한 앱을 사용하면 제작이 진행돼요."
	else:
		progress_bar.value = 0.0
		status_label.text = "● 준비"
		status_label.add_theme_color_override("font_color", GameState.col("success"))
		if GameState.jar_ingredients.is_empty():
			remain_label.text = "재료를 항아리에 넣고 제작을 시작하세요."
		else:
			remain_label.text = "준비 완료 — 제작을 시작하세요."
	detect_label.text = Watcher.status_text()

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
		"shop":
			overlay_title.text = "🛒 상점"
			_fill_shop()
		"inventory":
			overlay_title.text = "🎒 보관함"
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

func _coin_header() -> void:
	var cl := Label.new()
	cl.text = "보유 코인: 🪙 %d" % GameState.coins
	cl.add_theme_color_override("font_color", GameState.col("gold"))
	overlay_content.add_child(cl)
	overlay_content.add_child(_hsep())

func _fill_inventory() -> void:
	_clear_overlay()
	_coin_header()
	if GameState.inventory.is_empty():
		var e := Label.new()
		e.text = "아직 만든 물약이 없어요."
		overlay_content.add_child(e)
		return
	for key in GameState.inventory.keys():
		var p = GameState.inventory[key]
		var grade := int(p.get("grade", 0))
		var value := int(p.get("value", Recipes.sell_value(String(p.get("id", key)))))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var sw := ColorRect.new()
		sw.color = GameState.arr_to_color(p.color)
		sw.custom_minimum_size = Vector2(28, 28)
		row.add_child(sw)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var n := Label.new()
		n.add_theme_font_size_override("font_size", 16)
		# 등급 ★ + 물약명 + 개수 (★ 색상으로 등급 구분)
		n.text = "★ %s  %s  ×%d" % [Recipes.grade_name(grade), p.name, p.count]
		n.add_theme_color_override("font_color", Recipes.grade_color(grade))
		box.add_child(n)
		var d := Label.new()
		d.text = p.get("desc", "")
		d.add_theme_font_size_override("font_size", 12)
		d.add_theme_color_override("font_color", GameState.col("text_dim"))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(d)
		row.add_child(box)
		var cap_key: String = key
		var sell := Button.new()
		sell.text = "판매 🪙%d" % value
		sell.focus_mode = Control.FOCUS_NONE
		sell.pressed.connect(func(): _on_sell(cap_key))
		row.add_child(sell)
		overlay_content.add_child(row)
		overlay_content.add_child(_hsep())

func _on_sell(key: String) -> void:
	var v := GameState.sell_potion(key)
	if v > 0:
		_show_toast("판매 +🪙%d" % v)

func _fill_shop() -> void:
	_clear_overlay()
	var intro := Label.new()
	intro.text = "재료를 구매해 물약을 만들고, 완성한 물약은 보관함에서 팔아 코인을 모으세요."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", GameState.col("text_dim"))
	overlay_content.add_child(intro)
	_coin_header()
	for id in Recipes.INGREDIENTS.keys():
		var info = Recipes.INGREDIENTS[id]
		var price := Recipes.buy_price(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var sw := ColorRect.new()
		sw.color = info.color
		sw.custom_minimum_size = Vector2(24, 24)
		row.add_child(sw)
		var nm := Label.new()
		nm.text = "%s   (보유 %d)" % [info.name, GameState.available_stock(id)]
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var cap_id: String = id
		var buy := Button.new()
		buy.text = "구매 🪙%d" % price
		buy.focus_mode = Control.FOCUS_NONE
		buy.disabled = GameState.coins < price
		buy.pressed.connect(func(): _on_buy(cap_id))
		row.add_child(buy)
		overlay_content.add_child(row)

func _on_buy(id: String) -> void:
	if GameState.buy_ingredient(id):
		_show_toast("%s 구매!" % Recipes.ingredient_name(id))
	else:
		_show_toast("코인이 부족해요")

func _fill_recipes() -> void:
	_clear_overlay()
	var intro := Label.new()
	intro.text = "재료 조합과 시간대에 따라 다른 물약이 만들어집니다. 발견하면 이름이 공개돼요.\n제작 시간이 길수록 높은 등급(★일반<희귀<고급)이 나올 확률이 오르고, 등급이 높을수록 비싸게 팔립니다."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", GameState.col("text_dim"))
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
			title.add_theme_color_override("font_color", GameState.col("text_faint"))
		box.add_child(title)
		var ings := []
		for iid in r.ing:
			ings.append(Recipes.ingredient_name(iid))
		var info := Label.new()
		info.text = "재료: %s   ·   시간: %d~%d분" % [", ".join(ings), r.min, r.max]
		info.add_theme_font_size_override("font_size", 12)
		info.add_theme_color_override("font_color", GameState.col("text_muted"))
		box.add_child(info)
		if found:
			var d := Label.new()
			d.text = r.desc + "   (일반 판매가 🪙%d)" % int(r.value)
			d.add_theme_font_size_override("font_size", 12)
			d.add_theme_color_override("font_color", GameState.col("text_dim"))
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(d)
		overlay_content.add_child(box)
		overlay_content.add_child(_hsep())

func _fill_settings() -> void:
	_clear_overlay()

	var guide := Label.new()
	guide.text = "PC 사용 감지: 아래에 등록한 프로그램이 화면 맨 앞(활성 창)일 때 '사용 중'으로 판단해 제작이 진행됩니다.\n\n등록 방법: 원하는 프로그램(예: 크롬)을 클릭해 활성화한 뒤, 이 창으로 돌아와 '현재 창 등록'을 누르세요."
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide.add_theme_color_override("font_color", GameState.col("text_muted"))
	overlay_content.add_child(guide)

	live_detect_label = Label.new()
	live_detect_label.add_theme_font_size_override("font_size", 12)
	live_detect_label.add_theme_color_override("font_color", GameState.col("success"))
	live_detect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_content.add_child(live_detect_label)

	live_external_label = Label.new()
	live_external_label.add_theme_font_size_override("font_size", 13)
	live_external_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_content.add_child(live_external_label)

	var add_btn := Button.new()
	add_btn.text = "➕ 현재(마지막) 외부 창 등록"
	add_btn.focus_mode = Control.FOCUS_NONE
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
		e.add_theme_color_override("font_color", GameState.col("text_faint"))
		overlay_content.add_child(e)
	else:
		for i in range(GameState.registered_apps.size()):
			var a = GameState.registered_apps[i]
			var row := HBoxContainer.new()
			var nm := Label.new()
			var t: String = a.get("title", "")
			nm.text = a.name + ("  (%s)" % t if t.strip_edges() != "" else "")
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			nm.add_theme_font_size_override("font_size", 13)
			row.add_child(nm)
			var idx := i
			var del := Button.new()
			del.text = "삭제"
			del.focus_mode = Control.FOCUS_NONE
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
	force_cb.focus_mode = Control.FOCUS_NONE
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
		b.focus_mode = Control.FOCUS_NONE
		b.text = "%d배" % int(mult)
		b.button_pressed = is_equal_approx(GameState.time_scale, mult)
		var m: float = mult
		b.pressed.connect(func():
			GameState.time_scale = m
			GameState.save_game()
			_fill_settings())
		speed_row.add_child(b)
	overlay_content.add_child(speed_row)

	var instant_btn := Button.new()
	instant_btn.text = "⚡ 즉시 제작 완료 (디버그)"
	instant_btn.focus_mode = Control.FOCUS_NONE
	instant_btn.pressed.connect(_on_debug_complete)
	overlay_content.add_child(instant_btn)

	overlay_content.add_child(_hsep())

	# --- 화면 테마 ---
	var theme_lbl := Label.new()
	theme_lbl.text = "화면 테마"
	theme_lbl.add_theme_font_size_override("font_size", 16)
	overlay_content.add_child(theme_lbl)

	var theme_hint := Label.new()
	theme_hint.text = "밝은/어두운 화면을 선택하세요. (현재 선택한 테마 버튼은 비활성화됩니다)"
	theme_hint.add_theme_font_size_override("font_size", 12)
	theme_hint.add_theme_color_override("font_color", GameState.col("text_dim"))
	theme_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_content.add_child(theme_hint)

	var theme_row := HBoxContainer.new()
	theme_row.add_theme_constant_override("separation", 6)
	for entry in [["🌙 다크", "dark"], ["☀ 라이트", "light"]]:
		var b := Button.new()
		b.text = entry[0]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mode: String = entry[1]
		b.disabled = GameState.theme_mode == mode
		b.pressed.connect(func(): GameState.set_theme_mode(mode))
		theme_row.add_child(b)
	overlay_content.add_child(theme_row)

	overlay_content.add_child(_hsep())

	# --- 위젯 창 ---
	var win_lbl := Label.new()
	win_lbl.text = "위젯 창"
	win_lbl.add_theme_font_size_override("font_size", 16)
	overlay_content.add_child(win_lbl)

	var hint := Label.new()
	hint.text = "창의 빈 공간을 잡고 드래그하면 위치를 옮길 수 있어요."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", GameState.col("text_dim"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_content.add_child(hint)

	var top_cb := CheckBox.new()
	top_cb.text = "항상 위에 표시"
	top_cb.focus_mode = Control.FOCUS_NONE
	top_cb.button_pressed = get_window().always_on_top
	top_cb.toggled.connect(func(on): get_window().always_on_top = on)
	overlay_content.add_child(top_cb)

	var snap_lbl := Label.new()
	snap_lbl.text = "화면 구석으로 이동"
	snap_lbl.add_theme_color_override("font_color", GameState.col("text_muted"))
	overlay_content.add_child(snap_lbl)

	var snap_row := HBoxContainer.new()
	for entry in [["↖", 0], ["↗", 1], ["↙", 2], ["↘", 3]]:
		var b := Button.new()
		b.text = entry[0]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var corner: int = entry[1]
		b.pressed.connect(func(): _snap_window(corner))
		snap_row.add_child(b)
	overlay_content.add_child(snap_row)

	_update_settings_live()

func _update_settings_live() -> void:
	if live_detect_label:
		live_detect_label.text = Watcher.status_text()
	if live_external_label:
		var nm := Watcher.last_external_name
		if nm == "":
			live_external_label.text = "현재 감지된 외부 창: (없음 — 다른 프로그램을 클릭해 보세요)"
			live_external_label.add_theme_color_override("font_color", GameState.col("text_faint"))
		else:
			var reg = " ✔ 이미 등록됨" if GameState.is_app_registered(nm) else ""
			live_external_label.text = "현재 감지된 외부 창: %s%s" % [Watcher._display(nm, Watcher.last_external_title), reg]
			live_external_label.add_theme_color_override("font_color", GameState.col("gold"))

## [디버그] 진행 중인 제작을 즉시 완료. 완성 알림은 brew_changed 로 자동 표시된다.
func _on_debug_complete() -> void:
	if not GameState.debug_complete_brew():
		_show_toast("진행 중인 제작이 없어요")

func _on_add_current_window() -> void:
	var nm := Watcher.last_external_name
	if nm == "":
		_show_toast("먼저 다른 프로그램을 클릭해 활성화하세요")
		return
	if GameState.add_app(nm, Watcher.last_external_title):
		_show_toast("등록됨: %s" % nm)
	else:
		_show_toast("이미 등록된 프로그램이에요")

## 창을 화면 구석으로 이동. corner: 0=좌상 1=우상 2=좌하 3=우하
func _snap_window(corner: int) -> void:
	var win := get_window()
	var scr := DisplayServer.screen_get_usable_rect(win.current_screen)
	var ws := win.size
	var margin := 12
	var x := scr.position.x + margin
	var y := scr.position.y + margin
	if corner == 1 or corner == 3:
		x = scr.position.x + scr.size.x - ws.x - margin
	if corner == 2 or corner == 3:
		y = scr.position.y + scr.size.y - ws.y - margin
	win.position = Vector2i(x, y)

# ============================================================
# 유틸
# ============================================================
func _hsep() -> HSeparator:
	return HSeparator.new()

func _show_toast(text: String, col: Color = Color.WHITE) -> void:
	toast_label.add_theme_color_override("font_color", col)
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
