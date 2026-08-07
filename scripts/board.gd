class_name SyndicateBoard
extends Node2D

## 辛迪加面板 — 管理4个部门列、主脑区、未分配区以及关系连线

signal card_clicked(member_name: String)
signal card_hovered(member_name: String, screen_pos: Vector2)
signal card_unhovered(member_name: String)

# ===== 布局常量（世界坐标） =====
const COLUMN_X := {
	GameManager.Division.TRANSPORT:     -1050,
	GameManager.Division.FORTIFICATION:  -350,
	GameManager.Division.RESEARCH:        350,
	GameManager.Division.INTERVENTION:   1050,
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
const PRISON_Y     := 940
const PRISON_X_GAP := 350   # 审讯区横向间距（适配底部边框）

# 自由人散落区域
const FREE_CENTER  := Vector2(0, 420)
const FREE_X_GAP   := 300

const MASTERMIND_Y := -950
const CARD_SCALE   := 0.9

# ---- 成员散落排列模式 ----
# 根据部门成员数量(1~4)动态选择排列模式
# 每个 Vector2 是相对于首领位置的偏移 (dx, dy)
# 参考原版：上一下二，卡片不叠加（4人除外）

# 部下采用「纵向链式」排列：每人依次向下，不横向展开
# 列间距 700px（新 COLUMN_X 对称布局），卡片有效宽 252px，无跨部门冲突
# 垂直步长 420px > 卡片有效高 342px，无纵向重叠

# 1人：首领正下方
const _SLOTS_1 := [Vector2(0, 420)]
# 2人：纵向链式
const _SLOTS_2 := [Vector2(0, 420), Vector2(0, 840)]
# 3人：纵向链式
const _SLOTS_3 := [Vector2(0, 420), Vector2(0, 840), Vector2(0, 1260)]
# 4人：两排两列（横向偏移克制，不超出列宽）
const _SLOTS_4 := [Vector2(-140, 420), Vector2(140, 420), Vector2(-140, 840), Vector2(140, 840)]

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
var step2_temp_return_prison_members: bool = false


signal slot_clicked(slot_info: Dictionary)

# ===== 子节点 =====
var _cards: Dictionary = {}           # member_name -> MemberCard
var is_teaching_whiteboard_mode: bool = false # 电子画板模式标志
var _rel_lines = null                 # RelationshipLines
var _badges: Dictionary = {}          # Division -> Sprite2D
var _mastermind_card: Sprite2D
var _mastermind_container: Node2D

var _tex_mastermind_badge := preload("res://辛迪加素材/界面UI/主脑标志.png")
var _tex_bg := preload("res://辛迪加素材/界面UI/人物背景.png")
var _tex_mastermind_halo := preload("res://辛迪加素材/界面UI/主脑光晕.png")

func _ready():
	add_to_group("board")
	# 将所有依赖全局坐标系初始化的调用包裹在一个延迟函数中，避免顺序错乱
	call_deferred("_late_init")
	
	_build_divisions()
	_build_mastermind()
	_build_relationship_layer()
	_create_cards()
	_layout_cards()

	# 连接信号
	GameManager.board_changed.connect(_on_board_changed)
	GameManager.intelligence_changed.connect(_on_intel_changed)
	GameManager.member_revealed.connect(_on_member_revealed)

func _process(_delta: float):
	_update_relationship_lines()

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



# ===== 构建主脑区域 =====
func _build_mastermind():
	# 使用容器节点以 CARD_SCALE（0.9）统一缩放和定位，保持与其他卡牌尺寸和排版完全一致
	_mastermind_container = Node2D.new()
	_mastermind_container.position = Vector2(0, MASTERMIND_Y)
	_mastermind_container.scale = Vector2(CARD_SCALE, CARD_SCALE)
	add_child(_mastermind_container)

	# 1. 人物背景底板 (z_index = 0)
	var bg_sprite := Sprite2D.new()
	bg_sprite.texture = _tex_bg
	bg_sprite.z_index = 0
	_mastermind_container.add_child(bg_sprite)

	# 2. 主脑光晕 (z_index = 1)
	var halo_sprite := Sprite2D.new()
	halo_sprite.texture = _tex_mastermind_halo
	halo_sprite.z_index = 1
	halo_sprite.scale = Vector2(1.1, 1.1)
	_mastermind_container.add_child(halo_sprite)

	# 3. 主脑标志 (作为卡牌的中心主体，z_index = 2)
	_mastermind_card = Sprite2D.new()
	_mastermind_card.texture = _tex_mastermind_badge
	_mastermind_card.z_index = 2
	_mastermind_card.scale = Vector2(1.1, 1.1)
	_mastermind_card.position = Vector2.ZERO
	_mastermind_container.add_child(_mastermind_card)

func _build_relationship_layer():
	if _rel_lines != null:
		return
	_rel_lines = RelationshipLines.new()
	_rel_lines.name = "RelationshipLines"
	_rel_lines.z_as_relative = true
	_rel_lines.z_index = -20
	add_child(_rel_lines)


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
	
	# 确保所有区域 ColorRect 节点不遮挡/阻塞鼠标点击事件
	var unassigned_nodes = get_tree().get_nodes_in_group("unassigned_slot")
	for u_node in unassigned_nodes:
		if u_node is Control:
			u_node.mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	# --- 0. 主脑位置更新（从全局主脑槽位组 leader_mastermind_slot 读取坐标，适配 Board 节点非 BackgroundCanvas 直系子节点的情况） ---
	if _mastermind_container:
		var mm_pos = Vector2(0, MASTERMIND_Y) # 默认备份坐标
		var mm_nodes = get_tree().get_nodes_in_group("leader_mastermind_slot")
		var mm_slot: Control = null
		if not mm_nodes.is_empty():
			mm_slot = mm_nodes[0] as Control
		
		if mm_slot:
			var canvas_trans = get_viewport().get_canvas_transform()
			var vp_rect = mm_slot.get_global_rect()
			var global_pos = canvas_trans.affine_inverse() * vp_rect.get_center()
			mm_pos = to_local(global_pos)
		
		_mastermind_container.position = mm_pos

	var assigned_positions: Array[Vector2] = []
	var max_sub_y: float = -9999.0  # 追踪所有部下的最低 Y，用于计算自由人安全行

	# --- 1. 各部门：首领（固定位置不变）+ 部下（_SLOTS 数学模式，去掉手动槽位） ---
	for div in GameManager.ALL_DIVISIONS:
		# 确定首领的基础位置
		var leader_target: Vector2
		if _leader_slots.has(div):
			leader_target = _leader_slots[div]
		else:
			leader_target = Vector2(COLUMN_X[div], LEADER_Y[div])
		
		# 使用首领的坐标作为部下排版的基准原点，保证整个部门垂直对齐
		var cx: float = leader_target.x
		var ly: float = leader_target.y

		# 首领动画
		var leader = GameManager.get_division_leader(div)
		if leader and _cards.has(leader.member_name) and (step2_temp_return_prison_members or not leader.is_imprisoned):
			assigned_positions.append(leader_target)
			_animate_card_to(_cards[leader.member_name], leader_target)

		# 收集该部门非监禁部下（步骤2避让模式下包含监禁部下）
		var active: Array = []
		for m in GameManager.get_division_members(div):
			if (step2_temp_return_prison_members or not m.is_imprisoned) and _cards.has(m.member_name):
				active.append(m)

		# 部下：优先使用场景中指定的自定义坑位，不足时回退数学模式
		var sub_slots_world: Array = []
		if _custom_slots.has(div) and _custom_slots[div].size() > 0:
			# 使用场景坑位（本地坐标，已在 _parse_custom_slots 中转换）
			sub_slots_world = _custom_slots[div]

		for i in range(active.size()):
			var final_pos: Vector2
			if i < sub_slots_world.size():
				# ✅ 落入场景边框中心
				final_pos = sub_slots_world[i]
			else:
				# ⚠️ 坑位不足时，在最后一个坑位下方继续延伸
				var base: Vector2 = sub_slots_world[-1] if sub_slots_world.size() > 0 else leader_target
				final_pos = base + Vector2(0, 420 * (i - sub_slots_world.size() + 1))
			assigned_positions.append(final_pos)
			_animate_card_to(_cards[active[i].member_name], final_pos)
			if final_pos.y > max_sub_y:
				max_sub_y = final_pos.y

	# --- 2. 审讯区（非步骤2避让状态下，被审讯成员平滑移入底部木框审讯区域） ---
	if not step2_temp_return_prison_members:
		var imprisoned: Array = []
		for mname in GameManager.members:
			var m = GameManager.members[mname]
			if m.is_imprisoned and m.is_on_board and _cards.has(mname):
				imprisoned.append(mname)

		var prison_rect := _get_region_control_rect("审讯区域")
		var prison_center_x := 0.0
		var prison_center_y := PRISON_Y
		if prison_rect.size != Vector2.ZERO:
			prison_center_x = prison_rect.get_center().x
			prison_center_y = prison_rect.get_center().y
		else:
			var prison_nodes = get_tree().get_nodes_in_group("guard_zone")
			for node in prison_nodes:
				if node.name == "GuardZone_3" and node is Control:
					var canvas_trans = get_viewport().get_canvas_transform()
					var vp_rect = node.get_global_rect()
					var global_pos = canvas_trans.affine_inverse() * vp_rect.get_center()
					prison_center_x = to_local(global_pos).x
					break

		var prison_total_w: float = (imprisoned.size() - 1) * PRISON_X_GAP
		var prison_start_x: float = prison_center_x - prison_total_w * 0.5
		
		for i in range(imprisoned.size()):
			var p_pos := Vector2(prison_start_x + i * PRISON_X_GAP, prison_center_y)
			assigned_positions.append(p_pos)
			_animate_card_to(_cards[imprisoned[i]], p_pos)

	# --- 3. 自由人：使用场景坑位，自动跳过被部门成员占用的位置 ---
	var free_members: Array = []
	for m in GameManager.get_unassigned_members():
		if (step2_temp_return_prison_members or not m.is_imprisoned) and _cards.has(m.member_name):
			free_members.append(m)

	if free_members.size() > 0:
		# 读取场景自定义坑位（全部）
		var all_free_slots: Array = []
		if _custom_slots.has(GameManager.Division.NONE):
			all_free_slots = _custom_slots[GameManager.Division.NONE]

		# 过滤掉已被部门成员占用的坑位
		# 距离阈值：约等于卡片有效半径，两张卡片中心距小于此值视为重叠
		const OCCUPY_THRESHOLD := 300.0
		var available_slots: Array = []
		for slot_pos in all_free_slots:
			var occupied := false
			for ap in assigned_positions:
				if slot_pos.distance_to(ap) < OCCUPY_THRESHOLD:
					occupied = true
					break
			if not occupied:
				available_slots.append(slot_pos)

		# 溢出续排锚点：优先用最后一个可用坑位，否则用原坑位列表末尾
		var overflow_step_y := 440.0
		var overflow_anchor: Vector2 = (
			available_slots[-1] if available_slots.size() > 0
			else (all_free_slots[-1] if all_free_slots.size() > 0 else FREE_CENTER)
		)

		for i in range(free_members.size()):
			var target: Vector2
			if i < available_slots.size():
				# ✅ 落入未被占用的场景坑位
				target = available_slots[i]
			else:
				# ⚠️ 可用坑位耗尽：从锚点正下方续排，同时避开已分配位置
				var overflow_idx: int = i - available_slots.size()
				target = overflow_anchor + Vector2(0, overflow_step_y * (overflow_idx + 1))
				# 若溢出位置仍与已有位置冲突，继续向下推
				var extra := 0
				while true:
					var blocked := false
					for ap in assigned_positions:
						if target.distance_to(ap) < OCCUPY_THRESHOLD:
							blocked = true
							break
					if not blocked:
						break
					extra += 1
					target = overflow_anchor + Vector2(0, overflow_step_y * (overflow_idx + 1 + extra))
			assigned_positions.append(target)
			_animate_card_to(_cards[free_members[i].member_name], target)



# ===== 散落模式选择 =====
func _get_slot_pattern(count: int) -> Array:
	match count:
		1: return _SLOTS_1
		2: return _SLOTS_2
		3: return _SLOTS_3
		4: return _SLOTS_4
	# >4 的极端情况：继续纵向链式延伸
	var result: Array = _SLOTS_4.duplicate()
	for i in range(4, count):
		var row := int(i / 2)
		var side := 1 if (i % 2 == 0) else -1
		result.append(Vector2(side * 140, 420 + row * 420))
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
	tw.tween_callback(Callable(self, "_snap_card_to_pixel").bind(card))

func _snap_card_to_pixel(card):
	if is_instance_valid(card):
		card.position = Vector2(round(card.position.x), round(card.position.y))

func _update_relationship_lines():
	if _rel_lines == null:
		return
	var positions: Dictionary = {}
	for mname in _cards:
		var card: MemberCard = _cards[mname]
		if card == null:
			continue
		var ms = card.member_data
		if ms == null or not ms.is_on_board:
			continue
		positions[mname] = card.global_position
		
	# --- 注入沙盒向导的连线实时预览参数 ---
	var wizards = get_tree().get_nodes_in_group("sandbox_wizard")
	var active_wizard: SandboxSetupWizard = null
	for w in wizards:
		if is_instance_valid(w) and not w.is_queued_for_deletion():
			active_wizard = w as SandboxSetupWizard
			break
			
	if active_wizard and active_wizard._current_step == 3 and active_wizard._step3_first_selected_member != "":
		_rel_lines.preview_start_member = active_wizard._step3_first_selected_member
		_rel_lines.preview_relation_type = active_wizard._step3_relation_mode
		_rel_lines.preview_target_pos = to_local(get_global_mouse_position())
	else:
		_rel_lines.preview_start_member = ""
		
	_rel_lines.update_positions(positions)


# ===== 信号回调 =====
func _on_board_changed():
	# 1. 移除已经不在场上的卡片
	var to_remove = []
	for mname in _cards:
		var card = _cards[mname]
		# 确保在检查是否在场前，将卡牌绑定的数据指向 GameManager 中最新的实例指针
		if GameManager.members.has(mname):
			card.member_data = GameManager.members[mname]
		
		var ms = card.member_data
		if ms == null or not ms.is_on_board:
			to_remove.append(mname)
	for mname in to_remove:
		var card = _cards[mname]
		card.queue_free()
		_cards.erase(mname)

	# 2. 为新上场的成员创建卡片
	for mname in GameManager.members:
		var m = GameManager.members[mname]
		if m.is_on_board and not _cards.has(mname):
			var card := MemberCard.new()
			card.scale = Vector2(CARD_SCALE, CARD_SCALE)
			card.setup(m)
			card.card_clicked.connect(_on_card_click)
			card.card_right_clicked.connect(func(mname: String, click_pos: Vector2): card_right_clicked.emit(mname, click_pos))
			card.card_hovered.connect(_on_card_hover.bind(mname))
			card.card_unhovered.connect(_on_card_unhover)
			# 初始坐标处理：如果有沙盒向导且处于第二步骤，则把起点设为底部坞中卡片的屏幕位置
			var start_pos := FREE_CENTER
			var wizards = get_tree().get_nodes_in_group("sandbox_wizard")
			if wizards.size() > 0:
				var wizard = wizards[0]
				if is_instance_valid(wizard) and wizard.has_method("get_member_dock_screen_position"):
					var screen_pos = wizard.get_member_dock_screen_position(mname)
					if screen_pos != Vector2.ZERO:
						# 将屏幕坐标反算回 board.gd 节点空间下的本地坐标，实现完美的飞入动画！
						var global_pos = get_viewport().get_canvas_transform().affine_inverse() * screen_pos
						start_pos = to_local(global_pos)
			card.position = start_pos
			add_child(card)
			_cards[mname] = card

	# 3. 刷新所有卡片显示
	for mname in _cards:
		_cards[mname].is_abstract_mode = is_teaching_whiteboard_mode
		_cards[mname].member_data = GameManager.members[mname]
		_cards[mname].update_display()
		
	# 4. 重新解析坑位（成员状态变化后坑位占用情况会改变）
	_parse_custom_slots()
	# 5. 重新布局
	_layout_cards()

var show_teaching_frames: bool = false

func _get_region_control_rect(region_name: String) -> Rect2:
	var canvas_trans = get_viewport().get_canvas_transform()
	var nodes = get_tree().get_nodes_in_group("unassigned_slot")
	for node in nodes:
		if is_instance_valid(node) and String(node.name) == region_name and node is Control:
			var vp_rect: Rect2 = node.get_global_rect()
			var g_pos = canvas_trans.affine_inverse() * vp_rect.position
			var g_end = canvas_trans.affine_inverse() * (vp_rect.position + vp_rect.size)
			return Rect2(to_local(g_pos), g_end - g_pos)
	return Rect2()

func set_teaching_whiteboard_mode(active: bool):
	is_teaching_whiteboard_mode = active
	show_teaching_frames = false # 开启教学模式默认隐藏边框
	for mname in _cards:
		_cards[mname].is_abstract_mode = active
		_cards[mname].update_display()
	queue_redraw()

func get_screen_to_board_rect(screen_rect: Rect2) -> Rect2:
	var canvas_trans = get_viewport().get_canvas_transform()
	var g_tl = canvas_trans.affine_inverse() * screen_rect.position
	var g_br = canvas_trans.affine_inverse() * (screen_rect.position + screen_rect.size)
	var l_tl = to_local(g_tl)
	var l_br = to_local(g_br)
	return Rect2(l_tl, l_br - l_tl)

func get_region_rect_by_name(node_name: String, fallback_screen_rect: Rect2) -> Rect2:
	var unassigned_nodes = get_tree().get_nodes_in_group("unassigned_slot")
	for node in unassigned_nodes:
		if is_instance_valid(node) and String(node.name) == node_name and node is Control:
			return get_screen_to_board_rect(node.get_global_rect())
	return get_screen_to_board_rect(fallback_screen_rect)

func _draw():
	if not is_teaching_whiteboard_mode or not show_teaching_frames:
		return
		
	var default_font = ThemeDB.fallback_font
	if default_font == null:
		return

	# 100% 精准读取您在场景树里摆放的 6 大参考控件矩形，并经由 Camera2D 逆矩阵转为 2D 世界画板 Rect
	var regions := [
		{"rect": get_region_rect_by_name("审讯区域", Rect2(726, 782, 470, 60)),     "fill": Color(0.85, 0.4, 0.9, 0.08), "border": Color(0.85, 0.4, 0.9, 0.75), "text": "⛓️ 审讯关押区"},
		{"rect": get_region_rect_by_name("自由人区域", Rect2(733, 858, 452, 160)),   "fill": Color(0.7, 0.7, 0.7, 0.08),  "border": Color(0.75, 0.75, 0.75, 0.7), "text": "🏕️ 自由人区"},
		{"rect": get_region_rect_by_name("运输部成员区域", Rect2(129, 314, 419, 528)), "fill": Color(0.2, 0.6, 1.0, 0.08),  "border": Color(0.2, 0.6, 1.0, 0.75), "text": "🚚 运输部成员区"},
		{"rect": get_region_rect_by_name("防卫部成员区域", Rect2(563, 448, 365, 321)), "fill": Color(0.3, 0.8, 0.4, 0.08),  "border": Color(0.3, 0.8, 0.4, 0.75), "text": "🛡️ 防卫部成员区"},
		{"rect": get_region_rect_by_name("科研部成员区域", Rect2(943, 448, 343, 321)), "fill": Color(0.9, 0.3, 0.3, 0.08),  "border": Color(0.9, 0.3, 0.3, 0.75), "text": "🔬 科研部成员区"},
		{"rect": get_region_rect_by_name("调停部成员区域", Rect2(1302, 314, 489, 531)),"fill": Color(1.0, 0.7, 0.2, 0.08),  "border": Color(1.0, 0.7, 0.2, 0.75), "text": "⚖️ 调停部成员区"},
	]

	for data in regions:
		var r: Rect2 = data["rect"]
		draw_rect(r, data["fill"], true)
		draw_rect(r, data["border"], false, 3.0)
		draw_string(default_font, Vector2(r.position.x + 15, r.position.y + 48), data["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 38, data["border"])

func get_slot_at_position(local_pos: Vector2) -> Dictionary:
	# 1. 动态读取 6 大参考控件并进行 100% 精准点选判定
	if get_region_rect_by_name("审讯区域", Rect2(726, 782, 470, 60)).has_point(local_pos):
		return {"slot_type": "PRISON", "division": GameManager.Division.NONE}
	if get_region_rect_by_name("自由人区域", Rect2(733, 858, 452, 160)).has_point(local_pos):
		return {"slot_type": "FREE", "division": GameManager.Division.NONE}
	if get_region_rect_by_name("运输部成员区域", Rect2(129, 314, 419, 528)).has_point(local_pos):
		return {"slot_type": "SUBORDINATE", "division": GameManager.Division.TRANSPORT}
	if get_region_rect_by_name("防卫部成员区域", Rect2(563, 448, 365, 321)).has_point(local_pos):
		return {"slot_type": "SUBORDINATE", "division": GameManager.Division.FORTIFICATION}
	if get_region_rect_by_name("科研部成员区域", Rect2(943, 448, 343, 321)).has_point(local_pos):
		return {"slot_type": "SUBORDINATE", "division": GameManager.Division.RESEARCH}
	if get_region_rect_by_name("调停部成员区域", Rect2(1302, 314, 489, 531)).has_point(local_pos):
		return {"slot_type": "SUBORDINATE", "division": GameManager.Division.INTERVENTION}

	# 2. 检查首领位（对齐背景原画红框区域）
	for div in GameManager.ALL_DIVISIONS:
		var leader_target: Vector2
		if _leader_slots.has(div):
			leader_target = _leader_slots[div]
		else:
			leader_target = Vector2(COLUMN_X[div], LEADER_Y[div])
			
		if local_pos.distance_to(leader_target) < 160.0:
			return {"slot_type": "LEADER", "division": div}

	return {"slot_type": "NONE", "division": GameManager.Division.NONE}

signal cancel_tool_requested()
signal star_scroll_requested(dir: int)
signal middle_click_requested()
signal card_right_clicked(member_name: String, global_pos: Vector2)

func _unhandled_input(event: InputEvent):
	if not is_teaching_whiteboard_mode:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var local_pos = to_local(get_global_mouse_position())
			var info = get_slot_at_position(local_pos)
			slot_clicked.emit(info)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_tool_requested.emit()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			middle_click_requested.emit()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			star_scroll_requested.emit(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			star_scroll_requested.emit(-1)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_tool_requested.emit()

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
