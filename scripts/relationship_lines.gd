class_name RelationshipLines
extends Node2D

## 绘制成员之间的信赖(绿)和竞争(红)关系连线

var _card_positions: Dictionary = {}   # member_name -> global_position

var _tex_green := preload("res://辛迪加素材/绿色连线.png")
var _tex_red   := preload("res://辛迪加素材/红色连线.png")

func update_positions(positions: Dictionary) -> void:
	_card_positions = positions
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(GameManager):
		return
	for rel in GameManager.relationships:
		var pos_a = _card_positions.get(rel.member_a)
		var pos_b = _card_positions.get(rel.member_b)
		if pos_a == null or pos_b == null:
			continue

		# 转换到本地坐标
		var local_a: Vector2 = to_local(pos_a)
		var local_b: Vector2 = to_local(pos_b)

		var color: Color
		if rel.type == GameManager.RelationType.TRUST:
			color = Color(0.2, 0.9, 0.3, 0.7)
		else:
			color = Color(0.9, 0.2, 0.2, 0.7)

		# 绘制有宽度的线
		draw_line(local_a, local_b, color, 4.0, true)

		# 在线的中点绘制关系图标
		var mid: Vector2 = (local_a + local_b) * 0.5
		var tex: Texture2D = _tex_green if rel.type == GameManager.RelationType.TRUST else _tex_red
		if tex:
			var tex_size := tex.get_size()
			draw_texture_rect(tex, Rect2(mid - tex_size * 0.25, tex_size * 0.5), false)
