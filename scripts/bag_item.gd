extends Button
## 가방(인벤토리) 안의 재료 한 칸.
## 클릭하면 항아리에 담고, 항아리 위로 드래그해서 넣을 수도 있다.

var ing_id: String = ""

func _get_drag_data(_at_position: Vector2):
	if disabled or ing_id == "":
		return null
	# 드래그 미리보기(마우스를 따라다니는 라벨)
	var preview := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.65)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	preview.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = "● " + Recipes.ingredient_name(ing_id)
	lbl.add_theme_color_override("font_color", Recipes.ingredient_color(ing_id))
	preview.add_child(lbl)
	set_drag_preview(preview)
	return {"type": "ingredient", "id": ing_id}
