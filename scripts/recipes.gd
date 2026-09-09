extends Node
## 재료 / 레시피 데이터베이스와 결과 판정 로직.
## 오토로드 싱글턴(Recipes)으로 등록됨.

# 재료 정의: id -> { name, color, shape }
# shape 은 cauldron_view 가 아이콘을 그릴 때 사용하는 힌트.
var INGREDIENTS := {
	"herb":     {"name": "약초",   "color": Color("6cbf5a"), "shape": "leaf",     "price": 3},
	"mushroom": {"name": "버섯",   "color": Color("b5533b"), "shape": "mushroom", "price": 4},
	"crystal":  {"name": "수정",   "color": Color("57c7e3"), "shape": "crystal",  "price": 6},
	"slime":    {"name": "슬라임", "color": Color("9ad84a"), "shape": "blob",     "price": 4},
	"ember":    {"name": "불꽃",   "color": Color("ef8b3b"), "shape": "flame",    "price": 5},
	"dew":      {"name": "이슬",   "color": Color("a9d9ff"), "shape": "drop",     "price": 3},
	"bone":     {"name": "뼈",     "color": Color("e8e2cf"), "shape": "bone",     "price": 5},
	"petal":    {"name": "꽃잎",   "color": Color("f2a6c8"), "shape": "petal",    "price": 5},
}

# 레시피: ing(재료 id 목록, 순서 무관) + 시간 범위(분) -> 결과 물약
# min <= 설정시간(분) <= max 이고 재료 조합이 일치하면 해당 물약.
var RECIPES := [
	{
		"id": "vitality", "name": "활력의 물약", "color": Color("5fd06a"), "value": 12,
		"ing": ["herb", "dew"], "min": 1, "max": 15,
		"desc": "마시면 잠이 확 깨는 상쾌한 초록빛 물약.",
	},
	{
		"id": "flame", "name": "화염의 물약", "color": Color("ff7a2f"), "value": 14,
		"ing": ["ember", "crystal"], "min": 1, "max": 15,
		"desc": "병째로 뜨끈한, 손난로 대용 물약.",
	},
	{
		"id": "mana", "name": "마나 물약", "color": Color("3f7bff"), "value": 30,
		"ing": ["crystal", "dew"], "min": 15, "max": 60,
		"desc": "천천히 우려낸 깊고 푸른 마력의 정수.",
	},
	{
		"id": "poison", "name": "맹독 물약", "color": Color("7fbf3f"), "value": 16,
		"ing": ["mushroom", "slime"], "min": 1, "max": 20,
		"desc": "부글부글… 냄새만 맡아도 위험한 물약.",
	},
	{
		"id": "charm", "name": "매혹의 물약", "color": Color("ff7ab8"), "value": 22,
		"ing": ["petal", "dew"], "min": 1, "max": 30,
		"desc": "은은한 꽃향이 감도는 분홍빛 물약.",
	},
	{
		"id": "revive", "name": "부활의 물약", "color": Color("e23b4a"), "value": 60,
		"ing": ["bone", "ember"], "min": 30, "max": 180,
		"desc": "오래 고아낸, 생명을 되돌린다는 전설의 물약.",
	},
	{
		"id": "invisible", "name": "투명 물약", "color": Color("d8f0ff"), "value": 55,
		"ing": ["crystal", "petal", "dew"], "min": 30, "max": 180,
		"desc": "마시면 잠깐 모습이 흐릿해진다는 신비한 물약.",
	},
	{
		"id": "panacea", "name": "만병통치약", "color": Color("ffd447"), "value": 85,
		"ing": ["herb", "mushroom", "crystal"], "min": 15, "max": 90,
		"desc": "온갖 재료를 균형 있게 섞은 황금빛 명약.",
	},
	{
		"id": "ooze", "name": "점액 물약", "color": Color("b6e34a"), "value": 8,
		"ing": ["slime", "slime"], "min": 1, "max": 60,
		"desc": "던지면 끈적하게 달라붙는 장난용 물약.",
	},
	{
		"id": "lava", "name": "용암 물약", "color": Color("c0341d"), "value": 95,
		"ing": ["ember", "ember", "bone"], "min": 60, "max": 300,
		"desc": "위험천만! 아주 오래 끓여야 완성되는 물약.",
	},
]

# 재료가 없을 때 / 조합이 안 맞을 때의 결과
var UNKNOWN := {
	"id": "unknown", "name": "정체불명의 물약", "color": Color("8a7fa6"), "value": 5,
	"desc": "탁하고 미심쩍은 액체. 이게 대체 뭐지…?",
}
var FAILURE := {
	"id": "failure", "name": "맹물", "color": Color("cfe6f2"), "value": 1,
	"desc": "재료 없이 끓여봐야 그냥 물이다.",
}

func _sorted_key(ing: Array) -> String:
	var a = ing.duplicate()
	a.sort()
	return ",".join(a)

## 재료 목록(Array[String])과 설정시간(분)으로 결과 물약을 판정.
func resolve(ing: Array, minutes: float) -> Dictionary:
	if ing.is_empty():
		return FAILURE.duplicate()
	var key := _sorted_key(ing)
	for r in RECIPES:
		if _sorted_key(r.ing) == key and minutes >= r.min and minutes <= r.max:
			var res = r.duplicate()
			return res
	return UNKNOWN.duplicate()

## 특정 재료 조합의 모든 후보 레시피(시간대 무관)를 반환 — 도감/힌트용.
func recipes_for(ing: Array) -> Array:
	var key := _sorted_key(ing)
	var out := []
	for r in RECIPES:
		if _sorted_key(r.ing) == key:
			out.append(r)
	return out

## 물약 id 의 판매가(코인). 알 수 없으면 5.
func sell_value(id: String) -> int:
	if id == "unknown":
		return int(UNKNOWN.value)
	if id == "failure":
		return int(FAILURE.value)
	for r in RECIPES:
		if r.id == id:
			return int(r.value)
	return 5

## 재료 id 의 구매가(코인).
func buy_price(id: String) -> int:
	return int(INGREDIENTS.get(id, {}).get("price", 5))

func ingredient_color(id: String) -> Color:
	if INGREDIENTS.has(id):
		return INGREDIENTS[id].color
	return Color.GRAY

func ingredient_name(id: String) -> String:
	if INGREDIENTS.has(id):
		return INGREDIENTS[id].name
	return id
