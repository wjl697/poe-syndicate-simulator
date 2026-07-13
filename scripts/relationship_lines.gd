class_name RelationshipLines
extends Node2D

## 绘制成员关系连线：
## - 首领/部下：黄麻绳
## - 信任：绿麻绳
## - 敌对：红麻绳

var _card_positions: Dictionary = {}   # member_name -> global_position

# 沙盒连线实时预览参数
var preview_start_member: String = ""
var preview_target_pos: Vector2 = Vector2.ZERO
var preview_relation_type: int = -1

var _tex_yellow := preload("res://辛迪加素材/黄色连线.png")
var _tex_green := preload("res://辛迪加素材/绿色连线.png")
var _tex_red   := preload("res://辛迪加素材/红色连线.png")

var _atlas_yellow: AtlasTexture
var _atlas_green: AtlasTexture
var _atlas_red: AtlasTexture

func _ready() -> void:
	# 裁剪出大图中央实际的麻绳纹理区域
	_atlas_yellow = AtlasTexture.new()
	_atlas_yellow.atlas = _tex_yellow
	_atlas_yellow.region = Rect2(383, 187, 65, 14)

	_atlas_green = AtlasTexture.new()
	_atlas_green.atlas = _tex_green
	_atlas_green.region = Rect2(375, 219, 66, 13)

	_atlas_red = AtlasTexture.new()
	_atlas_red.atlas = _tex_red
	_atlas_red.region = Rect2(386, 199, 49, 14)

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
			_draw_pair(rel.member_a, rel.member_b, _atlas_green)
		elif rel.type == GameManager.RelationType.RIVALRY:
			_draw_pair(rel.member_a, rel.member_b, _atlas_red)

	# 2) 绘制上下级黄线（如果不已被显式关系覆盖）
	var hierarchy_pairs := _collect_hierarchy_pairs()
	for pair_key in hierarchy_pairs:
		if explicit_rels.has(pair_key):
			continue
		var pair: Dictionary = hierarchy_pairs[pair_key]
		_draw_pair(pair["a"], pair["b"], _atlas_yellow)

	# 3) 绘制沙盒拖拽连线实时预览（仅在选中第一张卡片时）
	if preview_start_member != "":
		var pos_a = _card_positions.get(preview_start_member)
		if pos_a != null:
			var local_a = to_local(pos_a)
			var local_b = preview_target_pos
			var color := Color.WHITE
			match preview_relation_type:
				0: color = Color(0.2, 0.9, 0.3, 0.8) # 绿（信任）
				1: color = Color(0.9, 0.2, 0.2, 0.8) # 红（仇敌）
				2: color = Color(0.8, 0.8, 0.8, 0.6) # 灰白（清除）
			_draw_dashed_line(local_a, local_b, color, 3.0, 10.0, 6.0)

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

func _draw_pair(a_name: String, b_name: String, rope_tex: AtlasTexture):
	var pos_a = _card_positions.get(a_name)
	var pos_b = _card_positions.get(b_name)
	if pos_a == null or pos_b == null:
		return

	var local_a: Vector2 = to_local(pos_a)
	var local_b: Vector2 = to_local(pos_b)

	if rope_tex:
		var dir := local_b - local_a
		var dist := dir.length()
		var angle := dir.angle()
		
		var src_region := rope_tex.region
		var tex_w := src_region.size.x
		var tex_h := src_region.size.y
		
		# 临时应用旋转和平移变换，使得本地 X 轴对齐两个节点的连线方向
		draw_set_transform(local_a, angle, Vector2.ONE)
		
		# 手动循环平铺绘制麻绳纹理，防止使用 draw_texture_rect 导致纹理被拉伸模糊失去螺纹细节
		var x := 0.0
		while x < dist:
			var draw_w := minf(tex_w, dist - x)
			# 截取当前平铺分段的源矩形区域 (特别注意处理最后一小段裁剪)
			var src_rect := Rect2(src_region.position.x, src_region.position.y, draw_w, tex_h)
			var dest_rect := Rect2(x, -tex_h * 0.5, draw_w, tex_h)
			
			draw_texture_rect_region(rope_tex.atlas, dest_rect, src_rect, Color.WHITE, false)
			x += tex_w
			
		# 还原变换矩阵
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _make_pair_key(a: String, b: String) -> String:
	if a <= b:
		return a + "|" + b
	return b + "|" + a

func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float = 2.0, dash_length: float = 8.0, gap_length: float = 6.0):
	var dir := to - from
	var length := dir.length()
	if length == 0.0:
		return
	var norm := dir.normalized()
	var current := 0.0
	while current < length:
		var end := minf(current + dash_length, length)
		draw_line(from + norm * current, from + norm * end, color, width)
		current += dash_length + gap_length
