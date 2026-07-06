class_name RelationshipLines
extends Node2D

## 绘制成员关系连线：
## - 首领/部下：黄色
## - 信任：绿色
## - 敌对：红色

var _card_positions: Dictionary = {}   # member_name -> global_position

var _tex_yellow := preload("res://辛迪加素材/黄色连线.png")
var _tex_green := preload("res://辛迪加素材/绿色连线.png")
var _tex_red   := preload("res://辛迪加素材/红色连线.png")

const _LINE_WIDTH := 5.0
const _ICON_SCALE := 0.55
const _COLOR_HIERARCHY := Color(0.95, 0.82, 0.24, 0.85)
const _COLOR_TRUST := Color(0.20, 0.90, 0.30, 0.80)
const _COLOR_RIVALRY := Color(0.90, 0.20, 0.20, 0.80)

func update_positions(positions: Dictionary) -> void:
	_card_positions = positions
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(GameManager):
		return

	# 1) 收集并绘制信任/敌对关系线（优先级最高）
	var explicit_rels := {}
	for rel in GameManager.relationships:
		var pair_key := _make_pair_key(rel.member_a, rel.member_b)
		explicit_rels[pair_key] = rel

		if rel.type == GameManager.RelationType.TRUST:
			_draw_pair(rel.member_a, rel.member_b, _COLOR_TRUST, _tex_green)
		elif rel.type == GameManager.RelationType.RIVALRY:
			_draw_pair(rel.member_a, rel.member_b, _COLOR_RIVALRY, _tex_red)

	# 2) 绘制上下级黄线（如果不已被显式关系覆盖）
	var hierarchy_pairs := _collect_hierarchy_pairs()
	for pair_key in hierarchy_pairs:
		if explicit_rels.has(pair_key):
			continue
		var pair: Dictionary = hierarchy_pairs[pair_key]
		_draw_pair(pair["a"], pair["b"], _COLOR_HIERARCHY, _tex_yellow)

func _collect_hierarchy_pairs() -> Dictionary:
	var result: Dictionary = {}
	for div in GameManager.ALL_DIVISIONS:
		var leader = GameManager.get_division_leader(div)
		if leader == null or not leader.is_on_board:
			continue
		var subordinates: Array = GameManager.get_division_members(div)
		for sub in subordinates:
			if sub == null or not sub.is_on_board:
				continue
			var key := _make_pair_key(leader.member_name, sub.member_name)
			result[key] = {
				"a": leader.member_name,
				"b": sub.member_name
			}
	return result

func _draw_pair(a_name: String, b_name: String, line_color: Color, icon_tex: Texture2D):
	var pos_a = _card_positions.get(a_name)
	var pos_b = _card_positions.get(b_name)
	if pos_a == null or pos_b == null:
		return

	var local_a: Vector2 = to_local(pos_a)
	var local_b: Vector2 = to_local(pos_b)
	draw_line(local_a, local_b, line_color, _LINE_WIDTH, true)

	if icon_tex:
		var mid: Vector2 = (local_a + local_b) * 0.5
		var tex_size: Vector2 = icon_tex.get_size() * _ICON_SCALE
		draw_texture_rect(icon_tex, Rect2(mid - tex_size * 0.5, tex_size), false)

func _make_pair_key(a: String, b: String) -> String:
	if a <= b:
		return a + "|" + b
	return b + "|" + a
