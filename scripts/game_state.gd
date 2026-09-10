extends Node
## 게임 전역 상태: 항아리 재료, 제작 진행, 보관함, 도감, 등록된 앱, 설정.
## 오토로드 싱글턴(GameState). user://save.json 에 저장.

signal jar_changed
signal brew_changed
signal inventory_changed
signal apps_changed
signal coins_changed
signal stock_changed
signal theme_changed
signal xp_changed
signal level_changed

const SAVE_PATH := "user://save.json"
const MAX_INGREDIENTS := 3

# 보유 코인 (재화)
var coins: int = 60

# 연금술사 레벨 / 경험치
var level: int = 1
var xp: int = 0

# 재료 재고: 재료 id -> 보유 개수 (첫 실행 기본값)
var ingredient_stock: Dictionary = {
	"herb": 3, "dew": 3, "mushroom": 2, "crystal": 2,
	"ember": 2, "slime": 1, "bone": 1, "petal": 1,
}

# 항아리에 담긴 재료 id 목록 (제작 시작 전)
var jar_ingredients: Array = []

# 진행 중인 제작. 없으면 null.
# { ings:Array, minutes:float, target_sec:float, acc_sec:float, active:bool, started:int }
var brew = null

# 보관함: potion_id -> { name, color(rgba array), desc, count }
var inventory: Dictionary = {}

# 발견한 레시피 id 목록 (도감)
var discovered: Array = []

# 방금 완성한 물약 (완성 알림용)
var last_made_name: String = ""
var last_made_grade: int = 0

# 등록된 앱: [{ name:String(소문자 프로세스명), title:String }]
var registered_apps: Array = []

# 설정
var time_scale: float = 1.0        # 제작 속도 배율(테스트용)
var force_active: bool = false      # true 면 PC 사용 여부와 무관하게 항상 진행
var theme_mode: String = "dark"    # 화면 테마: "dark" | "light"

## 현재 테마에 맞는 UI 색상을 역할(role) 이름으로 반환한다.
## 재료/물약/등급 등 콘텐츠 색은 여기서 다루지 않고 각자 색을 유지한다.
func col(role: String) -> Color:
	var light := theme_mode == "light"
	match role:
		"bg":         return Color("f4f0fa") if light else Color("1d1830")  # 창 배경
		"panel":      return Color("ffffff") if light else Color("221c38")  # 오버레이 패널
		"text":       return Color("2a2340") if light else Color("ece8f7")  # 기본 글자
		"text_muted": return Color("585074") if light else Color("b9aee0")  # 보조 글자
		"text_dim":   return Color("6f6690") if light else Color("9a90bc")  # 흐린 글자
		"text_faint": return Color("857b9e") if light else Color("8a80a6")  # 더 흐린 글자
		"text_ghost": return Color("9a92b0") if light else Color("6f6690")  # 가장 흐린 글자
		"gold":       return Color("b8860b") if light else Color("ffd447")  # 코인/강조
		"success":    return Color("2e8b57") if light else Color("7fd0a0")  # 성공/감지
	return Color("2a2340") if light else Color("ece8f7")

## 테마를 변경하고 저장 후 알린다.
func set_theme_mode(mode: String) -> void:
	if mode != "dark" and mode != "light":
		return
	if theme_mode == mode:
		return
	theme_mode = mode
	save_game()
	theme_changed.emit()

# ---------- 레벨 / 경험치 ----------
## 다음 레벨까지 필요한 경험치.
func xp_for_next() -> int:
	return 40 + level * 30

## 레벨에 따른 물약 품질(등급) 보너스. 등급 확률 계산 시 시간비율에 더해진다.
func level_bonus() -> float:
	return minf(0.02 * float(level - 1), 0.30)   # 레벨당 +2%, 최대 +30%

## 등급에 따른 경험치 보상.
func xp_reward(grade: int, is_real: bool) -> int:
	if not is_real:
		return 4
	return [12, 28, 60][clampi(grade, 0, 2)]

## 경험치를 더하고 필요 시 레벨업. 레벨업하면 level_changed 발신.
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	var leveled := false
	while xp >= xp_for_next():
		xp -= xp_for_next()
		level += 1
		leveled = true
	xp_changed.emit()
	if leveled:
		level_changed.emit()
	save_game()

func _ready() -> void:
	randomize()
	load_game()

func _exit_tree() -> void:
	save_game()

# ---------- 항아리 ----------
func available_stock(id: String) -> int:
	return int(ingredient_stock.get(id, 0))

func add_ingredient(id: String) -> bool:
	if brew != null:
		return false
	if jar_ingredients.size() >= MAX_INGREDIENTS:
		return false
	if available_stock(id) <= 0:
		return false
	ingredient_stock[id] = available_stock(id) - 1
	jar_ingredients.append(id)
	jar_changed.emit()
	stock_changed.emit()
	save_game()
	return true

func remove_ingredient_at(idx: int) -> void:
	if brew != null:
		return
	if idx >= 0 and idx < jar_ingredients.size():
		var id: String = jar_ingredients[idx]
		jar_ingredients.remove_at(idx)
		ingredient_stock[id] = available_stock(id) + 1
		jar_changed.emit()
		stock_changed.emit()
		save_game()

func clear_jar() -> void:
	if brew != null:
		return
	for id in jar_ingredients:
		ingredient_stock[id] = available_stock(id) + 1
	jar_ingredients.clear()
	jar_changed.emit()
	stock_changed.emit()
	save_game()

# ---------- 제작 ----------
func start_brew(minutes: float) -> bool:
	if brew != null or jar_ingredients.is_empty():
		return false
	brew = {
		"ings": jar_ingredients.duplicate(),
		"minutes": minutes,
		"target_sec": minutes * 60.0,
		"acc_sec": 0.0,
		"active": false,
		"started": Time.get_unix_time_from_system(),
	}
	jar_ingredients = []
	jar_changed.emit()
	brew_changed.emit()
	save_game()
	return true

## [디버그] 진행 중인 제작을 즉시 완료한다. 성공 시 true.
func debug_complete_brew() -> bool:
	if brew == null:
		return false
	brew.acc_sec = brew.target_sec
	_complete_brew()
	return true

func cancel_brew() -> void:
	if brew == null:
		return
	# 재료를 항아리로 돌려준다.
	jar_ingredients = brew.ings.duplicate()
	brew = null
	jar_changed.emit()
	brew_changed.emit()
	save_game()

## main 의 타이머가 매 틱 호출. dt(초, 배율 미적용), active(현재 PC 사용 중인지).
func tick_brew(dt: float, active: bool) -> void:
	if brew == null:
		return
	brew.active = active
	if active:
		brew.acc_sec += dt * time_scale
		if brew.acc_sec >= brew.target_sec:
			_complete_brew()

func _complete_brew() -> void:
	var result: Dictionary = Recipes.resolve(brew.ings, brew.minutes)
	# 등급 판정: 실패작/정체불명은 항상 일반, 그 외는 레시피 시간범위 안에서의
	# 설정시간 위치에 따라 확률적으로(범위 안에서 더 오래 끓일수록 상위 등급↑).
	var is_real: bool = result.id != "unknown" and result.id != "failure"
	var grade := 0
	if is_real:
		# 레시피 시간범위 내 위치 + 레벨 품질 보너스로 등급 판정
		var q := Recipes.time_ratio(brew.minutes, float(result.get("min", 1)), float(result.get("max", 1))) + level_bonus()
		grade = Recipes.roll_grade_from_ratio(q)
	last_made_name = String(result.name)
	last_made_grade = grade
	_add_potion(result, grade)
	brew = null
	brew_changed.emit()
	add_xp(xp_reward(grade, is_real))   # 경험치 획득 (내부에서 저장)
	save_game()

func brew_progress() -> float:
	if brew == null:
		return 0.0
	return clampf(brew.acc_sec / maxf(brew.target_sec, 0.001), 0.0, 1.0)

func brew_remaining_sec() -> float:
	if brew == null:
		return 0.0
	return maxf(brew.target_sec - brew.acc_sec, 0.0)

# ---------- 보관함 / 도감 ----------
func _add_potion(p: Dictionary, grade: int = 0) -> void:
	var id: String = p.id
	var key := "%s@%d" % [id, grade]   # 등급별로 따로 보관
	if inventory.has(key):
		inventory[key].count += 1
	else:
		var base := int(p.get("value", 5))
		var val := int(round(base * Recipes.grade_mult(grade)))
		inventory[key] = {
			"id": id,
			"name": p.name,
			"color": _color_to_arr(p.color),
			"desc": p.get("desc", ""),
			"grade": grade,
			"value": val,
			"count": 1,
		}
	if id != "unknown" and id != "failure" and not discovered.has(id):
		discovered.append(id)
	inventory_changed.emit()

func take_potion(key: String) -> void:
	if inventory.has(key):
		inventory[key].count -= 1
		if inventory[key].count <= 0:
			inventory.erase(key)
		inventory_changed.emit()
		save_game()

# ---------- 상점 / 판매 ----------
func buy_ingredient(id: String) -> bool:
	var price := int(Recipes.INGREDIENTS.get(id, {}).get("price", 5))
	if coins < price:
		return false
	coins -= price
	ingredient_stock[id] = available_stock(id) + 1
	coins_changed.emit()
	stock_changed.emit()
	save_game()
	return true

## 물약 1개 판매(등급 포함 key). 판매가(코인)를 반환, 실패 시 0.
func sell_potion(key: String) -> int:
	if not inventory.has(key):
		return 0
	var entry = inventory[key]
	var value := int(entry.get("value", Recipes.sell_value(String(entry.get("id", key)))))
	entry.count -= 1
	if entry.count <= 0:
		inventory.erase(key)
	coins += value
	inventory_changed.emit()
	coins_changed.emit()
	save_game()
	return value

# ---------- 등록된 앱 ----------
func is_app_registered(pname: String) -> bool:
	var low := pname.to_lower()
	for a in registered_apps:
		if a.name == low:
			return true
	return false

func add_app(pname: String, title: String) -> bool:
	if pname.strip_edges() == "":
		return false
	var low := pname.to_lower()
	if is_app_registered(low):
		return false
	registered_apps.append({"name": low, "title": title})
	apps_changed.emit()
	save_game()
	return true

func remove_app_at(idx: int) -> void:
	if idx >= 0 and idx < registered_apps.size():
		registered_apps.remove_at(idx)
		apps_changed.emit()
		save_game()

# ---------- 저장 / 불러오기 ----------
func _color_to_arr(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]

func arr_to_color(a) -> Color:
	if typeof(a) == TYPE_ARRAY and a.size() >= 3:
		return Color(a[0], a[1], a[2], a[3] if a.size() > 3 else 1.0)
	return Color.WHITE

func save_game() -> void:
	var data := {
		"jar": jar_ingredients,
		"brew": brew,
		"inventory": inventory,
		"discovered": discovered,
		"apps": registered_apps,
		"time_scale": time_scale,
		"force_active": force_active,
		"theme": theme_mode,
		"coins": coins,
		"level": level,
		"xp": xp,
		"stock": ingredient_stock,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return
	jar_ingredients = data.get("jar", [])
	brew = data.get("brew", null)
	inventory = data.get("inventory", {})
	discovered = data.get("discovered", [])
	registered_apps = data.get("apps", [])
	time_scale = float(data.get("time_scale", 1.0))
	force_active = bool(data.get("force_active", false))
	theme_mode = String(data.get("theme", "dark"))
	if theme_mode != "dark" and theme_mode != "light":
		theme_mode = "dark"
	coins = int(data.get("coins", coins))
	level = maxi(1, int(data.get("level", 1)))
	xp = maxi(0, int(data.get("xp", 0)))
	var saved_stock = data.get("stock", null)
	if typeof(saved_stock) == TYPE_DICTIONARY:
		var s := {}
		for k in saved_stock.keys():
			s[k] = int(saved_stock[k])
		ingredient_stock = s
	# brew 내부 숫자값들이 JSON 파싱으로 float 이 되도록 보정
	if brew != null:
		brew.minutes = float(brew.get("minutes", 1.0))
		brew.target_sec = float(brew.get("target_sec", 60.0))
		brew.acc_sec = float(brew.get("acc_sec", 0.0))
