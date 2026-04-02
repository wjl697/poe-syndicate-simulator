class_name SyndicateBoard
extends Node2D

## 辛迪加面板 — 管理4个部门列、主脑区、未分配区以及关系连线

signal card_clicked(member_name: String)
signal card_hovered(member_name: String, screen_pos: Vector2)
signal card_unhovered(member_name: String)

# ===== 布局常量（世界坐标） =====
const COLUMN_X := {
	GameManager.Division.TRANSPORT:     -980,
	GameManager.Division.FORTIFICATION:  -300,
	GameManager.Division.RESEARCH:        280,
	GameManager.Division.INTERVENTION:   800,
}
const BADGE_Y      := -800
const PROGRESS_Y   := -620
const LEADER_Y := {
	GameManager.Division.TRANSPORT:     -720,
	GameManager.Division.FORTIFICATION: -430,
	GameManager.Division.RESEARCH:      -430,
	GameManager.Division.INTERVENTION:  -720,
}

# 审讯区（底部中央，最多3人横排）
const PRISON_Y     := 950
const PRISON_X_GAP := 350

# 自由人散落区域
const FREE_CENTER  := Vector2(0, 420)
const FREE_X_GAP   := 300

const MASTERMIND_Y := -1050
const CARD_SCALE   := 0.9

# ---- 成员散落排列模式 ----
# 根据部门成员数量(1~4)动态选择排列模式
# 每个 Vector2 是相对于首领位置的偏移 (dx, dy)
# 参考原版：上一下二，卡片不叠加（4人除外）

# 1人：居中下方
const _SLOTS_1 := [Vector2(0, 350)]
# 2人：左右并排
const _SLOTS_2 := [Vector2(-220, 350), Vector2(220, 350)]
# 3人：上一下二
const _SLOTS_3 := [Vector2(0, 350), Vector2(-220, 700), Vector2(220, 700)]
# 4人：两排两列（部下点位）
const _SLOTS_4 := [Vector2(-220, 350), Vector2(220, 350), Vector2(-220, 700), Vector2(220, 700)]

# 每个部门额外的散落方向偏移（避免部下卡片在中心挤压）
const _DIV_BIAS := {
	GameManager.Division.TRANSPORT:     -100.0, # 往左下方推
	GameManager.Division.FORTIFICATION: -150.0, # 往更左边推，远离科研部
	GameManager.Division.RESEARCH:       150.0, # 往更右侧推
	GameManager.Division.INTERVENTION:   100.0, # 往右侧推
}

# 抖动范围 — 基于成员名字的 hash，保证同一成员位置稳定
const JITTER_X := 35
const JITTER_Y := 20

# ===== 动态禁区与自定义排序容器 =====
var _dynamic_guards: Array[Rect2] = []
var _custom_slots: Dictionary = {}    # Division -> Array[Vector2] (世界坐标)
var _leader_slots: Dictionary = {}    # Division -> Vector2 (首领专属坐标)


# ===== 子节点 =====
var _cards: Dictionary = {}           # member_name -> MemberCard
var _rel_lines_placeholder = null     # (已移除关系连线)
var _badges: Dictionary = {}          # Division -> Sprite2D
var _mastermind_card: Sprite2D

# 纹理
var _tex_mastermind   := preload("res://辛迪加素材/主脑/卡塔莉娜.png")
var _tex_mastermind_badge := preload("res://辛迪加素材/主脑标志.png")

func _ready():
	# 将所有依赖全局坐标系初始化的调用包裹在一个延迟函数中，避免顺序错乱
	call_deferred("_late_init")
	
	_build_divisions()
	_build_mastermind()
	# _build_relationship_layer() (已移除)
	_create_cards()
	_layout_cards()

	# 连接信号
	GameManager.board_changed.connect(_on_board_changed)
	GameManager.intelligence_changed.connect(_on_intel_changed)
	GameManager.member_revealed.connect(_on_member_revealed)

# ===== 延迟初始化 =====
func _late_init():
	# 1. 抓取禁区状态
	_update_guard_rects_state()
	# 2. 解析特殊的自定义坑位
	_parse_custom_slots()
	# 3. 强制执行一次整体排版更新
	_layout_cards()
	print("【初始化】首轮排版完成")

# ===== 构建部门标识和进度条 =====
func _build_divisions():
	for div in GameManager.ALL_DIVISIONS:
		var cx: float = COLUMN_X[div]

		# 部门角标
		var badge := Sprite2D.new()
		var badge_tex = load(GameManager.DIVISION_BADGE_PATHS[div])
		if badge_tex:
			badge.texture = badge_tex
			badge.scale = Vector2(0.7, 0.7)
		badge.position = Vector2(cx, BADGE_Y)
		add_child(badge)
		_badges[div] = badge

		# (已移除部门文字标签)


		# (已移除旧版进度条，现在由 MemberCard 自行管理显示)



# ===== 构建主脑区域 =====
func _build_mastermind():
	# 主脑标志
	var badge := Sprite2D.new()
	badge.texture = _tex_mastermind_badge
	badge.position = Vector2(0, MASTERMIND_Y - 120)
	badge.scale = Vector2(0.5, 0.5)
	add_child(badge)

	# 主脑头像
	_mastermind_card = Sprite2D.new()
	_mastermind_card.texture = _tex_mastermind
	_mastermind_card.position = Vector2(0, MASTERMIND_Y)
	_mastermind_card.scale = Vector2(0.5, 0.5)
	add_child(_mastermind_card)

	# 主脑名称
	var lbl := Label.new()
	lbl.text = "主脑 · 卡塔莉娜"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 52)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("shadow_offset_x", 3)
	lbl.add_theme_constant_override("shadow_offset_y", 3)
	lbl.position = Vector2(-160, MASTERMIND_Y + 140)
	lbl.size = Vector2(320, 60)
	add_child(lbl)

# (已移除 _build_relationship_layer)


# 核心同步函数：自定义排版槽位解析
func _parse_custom_slots():
	_custom_slots.clear()
	_leader_slots.clear()
	var canvas_trans = get_viewport().get_canvas_transform()
	
	var div_groups = {
		GameManager.Division.TRANSPORT: "transport_slot",
		GameManager.Division.FORTIFICATION: "fortification_slot",
		GameManager.Division.RESEARCH: "research_slot",
		GameManager.Division.INTERVENTION: "intervention_slot",
		GameManager.Division.NONE: "unassigned_slot"
	}

	var leader_groups = {
		GameManager.Division.TRANSPORT: "leader_transport_slot",
		GameManager.Division.FORTIFICATION: "leader_fortification_slot",
		GameManager.Division.RESEARCH: "leader_research_slot",
		GameManager.Division.INTERVENTION: "leader_intervention_slot",
	}
	
	for div in leader_groups:
		var nodes = get_tree().get_nodes_in_group(leader_groups[div])
		for node in nodes:
			if node is Control:
				var vp_rect = node.get_global_rect()
				var global_pos = canvas_trans.affine_inverse() * vp_rect.get_center()
				_leader_slots[div] = to_local(global_pos)
				break # 取第一个即可
	
	for div in div_groups:
		var nodes = get_tree().get_nodes_in_group(div_groups[div])
		if nodes.size() > 0:
			var slots: Array[Vector2] = []
			var slot_map := {}
			for node in nodes:
				if node is Control:
					var vp_rect = node.get_global_rect()
					var vp_center = vp_rect.get_center()
					var global_pos = canvas_trans.affine_inverse() * vp_center
					var local_pos = to_local(global_pos)
					
					# 提取名字末尾数字，如 Slot_Transport_1 -> 1
					var parts = node.name.split("_")
					var num_str = parts[parts.size()-1]
					if num_str.is_valid_int():
						slot_map[num_str.to_int()] = local_pos
			
			# 按数字顺序装载所有存在的坑位
			var keys = slot_map.keys()
			keys.sort()
			for idx in keys:
				slots.append(slot_map[idx])
			
			_custom_slots[div] = slots
			print("【同步站位】", GameManager.DIVISION_NAMES.get(div, "自由人区域"), " 读取了 ", slots.size(), " 个自动排版坑位！")


# 核心同步函数：抓取视口（屏幕）范围
func _update_guard_rects_state():
	_dynamic_guards.clear()
	var nodes = get_tree().get_nodes_in_group("guard_zone")
	
	for node in nodes:
		if node is Control:
			var vp_rect = node.get_global_rect()
			_dynamic_guards.append(vp_rect)

	# 重新布局
	_layout_cards()

# ===== 创建所有成员卡片 =====
func _create_cards():
	for mname in GameManager.members:
		var member_state = GameManager.members[mname]
		if not member_state.is_on_board:
			continue  # 不在场的成员不创建卡片
		var card := MemberCard.new()
		card.scale = Vector2(CARD_SCALE, CARD_SCALE)
		card.setup(member_state)
		card.card_clicked.connect(_on_card_click)
		card.card_hovered.connect(_on_card_hover.bind(mname))
		card.card_unhovered.connect(_on_card_unhover)
		add_child(card)
		_cards[mname] = card

# ===== 排列卡片到正确位置 =====
func _layout_cards():
	var assigned_positions: Array[Vector2] = []
	
	# --- 1. 各部门：首领 + 成员散落排列 ---
	for div in GameManager.ALL_DIVISIONS:
		var cx: float = COLUMN_X[div]
		var ly: float = LEADER_Y[div]
		var bias: float = _DIV_BIAS[div]

		# 检查是否有手动摆放的专用槽位
		var division_custom_slots = _custom_slots.get(div, [])
		var use_custom = division_custom_slots.size() > 0

		# 首领位置决定
		var leader = GameManager.get_division_leader(div)
		if leader and _cards.has(leader.member_name) and not leader.is_imprisoned:
			var leader_target: Vector2
			if _leader_slots.has(div):
				# 如果单独设置了首领专属方框，强制使用该方框
				leader_target = _leader_slots[div]
			else:
				# 否则使用代码默认纵向坐标
				leader_target = Vector2(cx, ly)
				
			assigned_positions.append(leader_target)
			_animate_card_to(_cards[leader.member_name], leader_target)

		# 收集该部门非监禁成员
		var active: Array = []
		for m in GameManager.get_division_members(div):
			if not m.is_imprisoned and _cards.has(m.member_name):
				active.append(m)

		# 成员排位
		var slots: Array = _get_slot_pattern(active.size())
		for i in range(active.size()):
			var target: Vector2
			var jitter := _name_jitter(active[i].member_name)
			
			if use_custom and i < division_custom_slots.size():
				target = division_custom_slots[i]
			else:
				# 否则走传统排位算法
				var offset: Vector2 = slots[i]
				target = Vector2(cx + offset.x + bias + jitter.x, ly + offset.y + jitter.y)
			
			# --- 统一应用避让逻辑 ---
			var final_pos = target if (use_custom and i < division_custom_slots.size()) else _get_avoidance_pos(_cards[active[i].member_name], target)
			assigned_positions.append(final_pos)
			_animate_card_to(_cards[active[i].member_name], final_pos)

	# --- 2. 审讯区（底部中央，横排最多3人） ---
	var imprisoned: Array = []
	for mname in GameManager.members:
		var m = GameManager.members[mname]
		if m.is_imprisoned and m.is_on_board and _cards.has(mname):
			imprisoned.append(mname)

	var prison_total_w: float = (imprisoned.size() - 1) * PRISON_X_GAP
	var prison_start_x: float = -prison_total_w * 0.5
	for i in range(imprisoned.size()):
		var p_pos := Vector2(prison_start_x + i * PRISON_X_GAP, PRISON_Y)
		assigned_positions.append(p_pos)
		_animate_card_to(_cards[imprisoned[i]], p_pos)

	# --- 3. 自由人散落排列 ---
	var free_members: Array = []
	for m in GameManager.get_unassigned_members():
		if not m.is_imprisoned and _cards.has(m.member_name):
			free_members.append(m)

	# 检查是否有手动摆放的专用槽位
	var unassigned_slots = _custom_slots.get(GameManager.Division.NONE, [])
	
	# 过滤出没有被其他部门卡片占用的自由人位置
	var valid_unassigned_slots: Array[Vector2] = []
	for slot_pos in unassigned_slots:
		var overlapped := false
		for assigned_pos in assigned_positions:
			var dx = abs(slot_pos.x - assigned_pos.x)
			var dy = abs(slot_pos.y - assigned_pos.y)
			if dx < 130.0 and dy < 190.0: # 卡片尺寸的 90% 内认为重叠
				overlapped = true
				break
		if not overlapped:
			valid_unassigned_slots.append(slot_pos)
			
	var use_custom_unassigned = valid_unassigned_slots.size() > 0

	# 自由人备用散落模式
	var free_slots := _get_free_slots(free_members.size())
	for i in range(free_members.size()):
		var target: Vector2
		if use_custom_unassigned and i < valid_unassigned_slots.size():
			target = valid_unassigned_slots[i]
		else:
			var slot_pos: Vector2 = free_slots[i]
			var jitter: Vector2 = _name_jitter(free_members[i].member_name)
			target = Vector2(FREE_CENTER.x + slot_pos.x + jitter.x, FREE_CENTER.y + slot_pos.y + jitter.y)
			
		var final_pos = target if (use_custom_unassigned and i < valid_unassigned_slots.size()) else _get_avoidance_pos(_cards[free_members[i].member_name], target)
		assigned_positions.append(final_pos)
		_animate_card_to(_cards[free_members[i].member_name], final_pos)


	# (已移除关系连线更新)


# ===== 散落模式选择 =====
func _get_slot_pattern(count: int) -> Array:
	match count:
		1: return _SLOTS_1
		2: return _SLOTS_2
		3: return _SLOTS_3
		4: return _SLOTS_4
	# >4 的极端情况：基于4人模式扩展
	var result: Array = _SLOTS_4.duplicate()
	for i in range(4, count):
		var row := i / 2
		var side := 1 if (i % 2 == 0) else -1
		result.append(Vector2(side * 220, 350 + row * 350))
	return result


# ===== 自由人散落位置（不整齐的排列） =====
func _get_free_slots(count: int) -> Array:
	var slots: Array = []
	# 散落式排列：交错的行，每行2~3人
	var stagger_patterns := [
		Vector2(-20, 0), Vector2(290, 30), Vector2(-300, 25),
		Vector2(580, -10), Vector2(-590, 15),
		Vector2(140, 340), Vector2(-150, 360),
	]
	for i in range(count):
		if i < stagger_patterns.size():
			slots.append(stagger_patterns[i])
		else:
			slots.append(Vector2((i - stagger_patterns.size()) * FREE_X_GAP, 340))
	return slots

# ===== 基于名字的确定性抖动（同一成员永远在同一位置） =====
func _name_jitter(member_name: String) -> Vector2:
	var h: int = member_name.hash()
	var jx: float = float((h % (JITTER_X * 2 + 1)) - JITTER_X)
	var jy: float = float(((h >> 8) % (JITTER_Y * 2 + 1)) - JITTER_Y)
	return Vector2(jx, jy)

func _get_avoidance_pos(card: MemberCard, target: Vector2) -> Vector2:
	var final_pos := target
	
	# === 跨维打击：世界坐标 VS 屏幕坐标 ===
	var global_pos = to_global(final_pos)
	var canvas_trans = get_viewport().get_canvas_transform()
	
	# 1. 算出卡片在屏幕视口上的真实坐标 (受 Camera2D 缩放和平移影响)
	var card_vp_pos = canvas_trans * global_pos
	var canvas_scale = canvas_trans.get_scale()
	var vp_size = Vector2(280, 400) * canvas_scale
	var vp_offset = Vector2(-140, -190) * canvas_scale
	var card_vp_rect = Rect2(card_vp_pos + vp_offset, vp_size)
	
	var ms = card.member_data
	if ms and not ms.is_leader and not ms.is_imprisoned:
		for guard_vp in _dynamic_guards:
			# guard_vp 是屏幕视口坐标，两者都在屏幕空间，完美碰撞检测！
			if guard_vp.intersects(card_vp_rect):
				# 2. 发生碰撞：在屏幕空间向下推 (加上边缘容差)
				var new_vp_y = guard_vp.position.y + guard_vp.size.y + 10
				
				# 3. 将屏幕空间的新 Y 坐标反算回世界坐标，再转回本地坐标！
				var new_vp_pos = Vector2(card_vp_pos.x, new_vp_y - vp_offset.y)
				var new_global_pos = canvas_trans.affine_inverse() * new_vp_pos
				var new_local_y = to_local(new_global_pos).y
				
				if new_local_y > final_pos.y:
					final_pos.y = new_local_y
					return _get_avoidance_pos(card, final_pos)
	return final_pos

func _animate_card_to(card: MemberCard, target: Vector2):
	var tw := create_tween()
	tw.tween_property(card, "position", target, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

# (已移除 _update_relationship_lines)


# ===== 信号回调 =====
func _on_board_changed():
	# 刷新所有卡片显示
	for mname in _cards:
		_cards[mname].update_display()
	# 重新布局
	_layout_cards()
	# 延迟更新（原连线更新已移除）
	await get_tree().create_timer(0.5).timeout

func _on_intel_changed(_div: int, _value: float):
	# 现在进度条内置在 MemberCard 中。当情报变化时，刷新所有卡片即可同步
	for mname in _cards:
		var card = _cards[mname]
		if card.member_data and card.member_data.division == _div:
			card.update_display()

func _on_member_revealed(member_name: String):
	if _cards.has(member_name):
		var card: MemberCard = _cards[member_name]
		card.update_display()
		# 揭示动画：闪光效果
		var tw := create_tween()
		tw.tween_property(card, "modulate", Color(1.5, 1.4, 1.0, 1.0), 0.2)
		tw.tween_property(card, "modulate", Color.WHITE, 0.3)

# ===== 公共接口 =====
func get_card(member_name: String) -> MemberCard:
	return _cards.get(member_name)

func highlight_cards(member_names: Array):
	for mname in _cards:
		_cards[mname].set_highlighted(mname in member_names)

func clear_highlights():
	for mname in _cards:
		_cards[mname].set_highlighted(false)

# ===== 下拉中转信号 =====
func _on_card_click(mname: String):
	card_clicked.emit(mname)

func _on_card_hover(_hovering_name: String, mname: String):
	if _cards.has(mname):
		var card = _cards[mname]
		var screen_pos: Vector2 = card.get_global_transform_with_canvas().origin
		card_hovered.emit(mname, screen_pos)

func _on_card_unhover(mname: String):
	card_unhovered.emit(mname)
