class_name SandboxSetupWizard
extends Control

## 沙盒布阵向导 UI 控制器
## 引导用户完成：
## 1. 从17名成员中选出14人（排他性排除3人）
## 2. 布阵：将14人依次拖放或点击放到棋盘插槽中（支持首领/部下/游荡自由人）
## 3. 关系：通过选择绿线(信任)、红线(宿敌)、中立(清除)，点击两张卡片进行连线定义

signal completed()
signal closed()

# 状态
var _current_step: int = 1 # 1, 2, 3
var _selected_members: Array[String] = [] # 步骤1中确定的14名上场成员
var _benched_members: Array[String] = []  # 被排除的3名替补席成员
var _animating_members: Array[String] = [] # 正在播放飞行过渡动画的成员名
var _benched_card_nodes: Dictionary = {}   # 保存底部被排除（替补）卡牌节点的字典 (mname -> PanelContainer)
var _active_placement_member: String = "" # 步骤2中选中的、待放置的成员名
var _step3_relation_mode: int = -1 # -1=无, 0=信任(绿), 1=仇敌(红), 2=清除(中立)
var _step3_first_selected_member: String = ""
var _pulse_time: float = 0.0              # 呼吸灯时间计数

# 常量
const SLOT_GROUPS = [
	"leader_transport_slot", "leader_fortification_slot", "leader_research_slot", "leader_intervention_slot",
	"transport_slot", "fortification_slot", "research_slot", "intervention_slot"
]

# UI 组件
var _top_panel: PanelContainer
var _title_label: Label
var _step_label: Label
var _back_btn: Button
var _next_btn: Button
var _reset_btn: Button
var _close_btn: Button

# 步骤3关系控制栏
var _relation_hbox: HBoxContainer
var _btn_trust: Button
var _btn_rival: Button
var _btn_clear: Button

# 步骤1的中间选择区域
var _step1_panel: PanelContainer
var _step1_grid: GridContainer
var _step1_prison_row: HBoxContainer

# 步骤2的底部卡片坞
var _step2_panel: PanelContainer
var _step2_hbox: HBoxContainer

# 连线提示 label
var _relation_tip_label: Label

# 缓存所有插槽引用
var _portrait_cache: Dictionary = {}       # 缓存所有成员的头像纹理，避免动画播放中发生磁盘 I/O
var _all_slots: Array[ColorRect] = []

func _ready():
	# 允许鼠标穿透根节点，因为我们要点击背后的棋盘卡片
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 预加载所有成员头像纹理到内存中，避免在动画播放时产生磁盘 I/O 导致的首次卡顿
	for mname in GameManager.MEMBER_DEFS:
		var portrait_path := "res://辛迪加素材/人员/" + mname + ".png"
		_portrait_cache[mname] = load(portrait_path)
	
	# 取消依赖 CanvasLayer 下的锚点，改用监听视口变化手动控制尺寸
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	# 在初始化时，清空所有人的在场状态，从而清除背景中的卡片（主脑卡片除外）
	for mname in GameManager.MEMBER_DEFS:
		var m = GameManager.members.get(mname)
		if m:
			m.is_on_board = false
			m.division = GameManager.Division.NONE
			m.is_leader = false
			m.rank = 0
	GameManager.board_changed.emit()
	
	_cache_board_slots()
	_build_ui()
	_on_viewport_size_changed()
	_update_step_ui()
	
	# 延迟一帧强制修正面板坐标，绕过 Godot 布局引擎在当帧对 Container 的覆盖
	call_deferred("_fix_step1_panel_rect")
# ===== 手动响应视口大小变化 =====
func _on_viewport_size_changed():
	var vp := get_viewport_rect().size
	size = vp
	# 手动强制刷新顶部和底部面板
	if is_instance_valid(_top_panel):
		_top_panel.size = Vector2(vp.x, 70)
		_top_panel.position = Vector2(0, 0)
	if is_instance_valid(_step2_panel):
		var panel_w = min(1660.0, vp.x - 40.0)
		var panel_h = 205.0
		_step2_panel.size = Vector2(panel_w, panel_h)
		_step2_panel.position = Vector2((vp.x - panel_w) * 0.5, vp.y - panel_h - 40.0)
	# 刷新中间步骤1的面板
	call_deferred("_fix_step1_panel_rect")
	# 替补区固定在审讯区屏幕坐标（水平居中，Y≈942 → 顶部=862）
	if is_instance_valid(_step1_prison_row):
		_step1_prison_row.position = Vector2(-2.0, 862.0)
		_step1_prison_row.size = Vector2(vp.x, 160.0)


# ===== 延迟修正步骤1面板坐标（跨过布局引擎运行后）=====
func _fix_step1_panel_rect():
	if not is_instance_valid(_step1_panel):
		return
	var panel_w := 1100.0
	var panel_h := 720.0
	var vp := get_viewport_rect().size
	_step1_panel.position = Vector2((vp.x - panel_w) * 0.5, (vp.y - panel_h) * 0.5 - 40.0)
	_step1_panel.size = Vector2(panel_w, panel_h)

# ===== 缓存棋盘插槽 =====
func _cache_board_slots():
	_all_slots.clear()
	for group in SLOT_GROUPS:
		var nodes = get_tree().get_nodes_in_group(group)
		for node in nodes:
			if node is ColorRect:
				_all_slots.append(node)

# ===== 监听棋盘插槽的点击事件 =====
func _connect_slot_inputs(connect_signals: bool):
	for slot in _all_slots:
		if connect_signals:
			# 确保插槽可见并且可以接受鼠标点击
			slot.visible = true
			slot.mouse_filter = Control.MOUSE_FILTER_STOP
			# 高亮插槽显示
			var color = slot.color
			color.a = 0.4
			slot.color = color
			
			if not slot.gui_input.is_connected(_on_slot_gui_input):
				slot.gui_input.connect(_on_slot_gui_input.bind(slot))
		else:
			slot.visible = false
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if slot.gui_input.is_connected(_on_slot_gui_input):
				slot.gui_input.disconnect(_on_slot_gui_input)

# ===== 插槽点击事件回调 =====
func _on_slot_gui_input(event: InputEvent, slot_node: ColorRect):
	if _current_step != 2 or _active_placement_member == "":
		return
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_assign_member_to_slot(_active_placement_member, slot_node)

func _assign_member_to_slot(mname: String, slot_node: ColorRect):
	# 解析插槽类型
	var div = GameManager.Division.NONE
	var is_leader = false
	
	for group in slot_node.get_groups():
		match group:
			"leader_transport_slot":
				div = GameManager.Division.TRANSPORT
				is_leader = true
			"leader_fortification_slot":
				div = GameManager.Division.FORTIFICATION
				is_leader = true
			"leader_research_slot":
				div = GameManager.Division.RESEARCH
				is_leader = true
			"leader_intervention_slot":
				div = GameManager.Division.INTERVENTION
				is_leader = true
			"transport_slot":
				div = GameManager.Division.TRANSPORT
				is_leader = false
			"fortification_slot":
				div = GameManager.Division.FORTIFICATION
				is_leader = false
			"research_slot":
				div = GameManager.Division.RESEARCH
				is_leader = false
			"intervention_slot":
				div = GameManager.Division.INTERVENTION
				is_leader = false
			"unassigned_slot":
				div = GameManager.Division.NONE
				is_leader = false

	# 检查是否有冲突 (首领排他，部下上限)
	if is_leader:
		# 同一部门只能有一个首领，把旧首领踢回自由人/未放置状态
		var old_leader = GameManager.get_division_leader(div)
		if old_leader and old_leader.member_name != mname:
			old_leader.is_on_board = false
			old_leader.division = GameManager.Division.NONE
			old_leader.is_leader = false
	else:
		if div != GameManager.Division.NONE:
			var subs = GameManager.get_division_members(div)
			if subs.size() >= GameManager.MAX_SUBORDINATES_PER_DIVISION:
				# 满了，把其中一个部下踢出
				var displaced = subs[0]
				displaced.is_on_board = false
				displaced.division = GameManager.Division.NONE
				displaced.is_leader = false

	# 如果该成员以前已经放在了别的地方，先清除旧的
	var member = GameManager.members.get(mname)
	if member:
		member.division = div
		member.is_leader = is_leader
		member.is_on_board = true
		member.is_revealed = true
		if is_leader:
			member.rank = 1
		elif div != GameManager.Division.NONE:
			member.rank = 1
		else:
			member.rank = 0
			
	_active_placement_member = ""
	GameManager.board_changed.emit()
	_update_step_ui()

# ===== 响应主棋盘卡片被点击的事件 =====
func handle_board_card_clicked(mname: String):
	if _current_step == 2:
		# 步骤2点击棋盘卡片：选中它，以便于重新放置或召回
		if mname in _selected_members:
			_active_placement_member = mname
			_update_step_ui()
	elif _current_step == 3:
		# 步骤3点击棋盘卡片：处理关系连线
		if _step3_relation_mode == -1:
			return
			
		if _step3_first_selected_member == "":
			_step3_first_selected_member = mname
			_relation_tip_label.text = "已选择 " + mname + "，请点击第二张卡片建立关系"
			# 高亮第一张卡片
			var card = get_tree().get_first_node_in_group("board") # 实际上是 board 场景
			if card and card.has_method("highlight_cards"):
				card.highlight_cards([mname])
		else:
			var first = _step3_first_selected_member
			_step3_first_selected_member = ""
			_relation_tip_label.text = "点击卡片来绘制关系连线"
			
			# 取消高亮
			var card = get_tree().get_first_node_in_group("board")
			if card and card.has_method("clear_highlights"):
				card.clear_highlights()
				
			if first == mname:
				return # 点击同一张卡片，取消选择
				
			# 建立/清除关系
			match _step3_relation_mode:
				0: # 信任
					GameManager._set_relationship_type(first, mname, GameManager.RelationType.TRUST)
				1: # 仇敌
					GameManager._set_relationship_type(first, mname, GameManager.RelationType.RIVALRY)
				2: # 清除
					GameManager._remove_relationship(first, mname)
			GameManager.board_changed.emit()

# ===== 构建 UI 界面 =====
func _build_ui():
	_top_panel = PanelContainer.new()
	_top_panel.custom_minimum_size = Vector2(0, 70)
	_top_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_top_panel)
	# _top_panel 的尺寸和坐标已交由 _on_viewport_size_changed 手动接管
	
	var style_top := StyleBoxFlat.new()
	style_top.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style_top.border_width_bottom = 2
	style_top.border_color = Color(0.7, 0.55, 0.2, 0.6)
	style_top.content_margin_left = 20
	style_top.content_margin_right = 20
	_top_panel.add_theme_stylebox_override("panel", style_top)
	
	var top_hbox := HBoxContainer.new()
	top_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_top_panel.add_child(top_hbox)
	
	_title_label = Label.new()
	_title_label.text = "🛠 沙盒布阵向导"
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	top_hbox.add_child(_title_label)
	
	var separator1 := VSeparator.new()
	separator1.add_theme_constant_override("separation", 20)
	top_hbox.add_child(separator1)
	
	_step_label = Label.new()
	_step_label.text = "步骤 1 / 3"
	_step_label.add_theme_font_size_override("font_size", 16)
	top_hbox.add_child(_step_label)
	
	var separator2 := VSeparator.new()
	separator2.add_theme_constant_override("separation", 30)
	top_hbox.add_child(separator2)
	
	# 关系定义控制栏 (仅在步骤3可见)
	_relation_hbox = HBoxContainer.new()
	_relation_hbox.visible = false
	_relation_hbox.add_theme_constant_override("separation", 10)
	top_hbox.add_child(_relation_hbox)
	
	_btn_trust = Button.new()
	_btn_trust.text = "🟢 信任关系"
	_btn_trust.toggle_mode = true
	_btn_trust.pressed.connect(func(): _select_relation_mode(0))
	_relation_hbox.add_child(_btn_trust)
	
	_btn_rival = Button.new()
	_btn_rival.text = "🔴 仇敌关系"
	_btn_rival.toggle_mode = true
	_btn_rival.pressed.connect(func(): _select_relation_mode(1))
	_relation_hbox.add_child(_btn_rival)
	
	_btn_clear = Button.new()
	_btn_clear.text = "⚪ 清除关系"
	_btn_clear.toggle_mode = true
	_btn_clear.pressed.connect(func(): _select_relation_mode(2))
	_relation_hbox.add_child(_btn_clear)
	
	var separator3 := VSeparator.new()
	separator3.add_theme_constant_override("separation", 20)
	top_hbox.add_child(separator3)
	
	# 右侧导航按钮
	var btn_hbox := HBoxContainer.new()
	btn_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 15)
	top_hbox.add_child(btn_hbox)
	
	_back_btn = Button.new()
	_back_btn.text = "上一步"
	_back_btn.pressed.connect(_on_back_pressed)
	btn_hbox.add_child(_back_btn)
	
	_next_btn = Button.new()
	_next_btn.text = "下一步"
	_next_btn.pressed.connect(_on_next_pressed)
	btn_hbox.add_child(_next_btn)
	
	_reset_btn = Button.new()
	_reset_btn.text = "清空重置"
	_reset_btn.pressed.connect(_on_reset_pressed)
	btn_hbox.add_child(_reset_btn)
	
	_close_btn = Button.new()
	_close_btn.text = "退出沙盒"
	_close_btn.pressed.connect(_on_close_pressed)
	btn_hbox.add_child(_close_btn)

	# --- 2. 步骤1：中央选择区域 ---
	# 使用绝对坐标定位，绕过 _ready() 中布局引擎未运行的问题
	var panel_w := 1100.0
	var panel_h := 720.0
	var vp := get_viewport_rect().size
	_step1_panel = PanelContainer.new()
	_step1_panel.position = Vector2((vp.x - panel_w) * 0.5, (vp.y - panel_h) * 0.5 - 40.0)
	_step1_panel.size = Vector2(panel_w, panel_h)
	_step1_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_step1_panel)
	
	_step1_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	
	var step1_vbox := VBoxContainer.new()
	step1_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	step1_vbox.add_theme_constant_override("separation", 14)
	_step1_panel.add_child(step1_vbox)
	
	var info_lbl := Label.new()
	info_lbl.text = "步骤 1: 请选择 3 名成员放入替补席（绿色 = 上场 / 红色 = 替补席）"
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.add_theme_font_size_override("font_size", 15)
	info_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	step1_vbox.add_child(info_lbl)
	
	_step1_grid = GridContainer.new()
	_step1_grid.columns = 6  # 6列×3行排列17人
	_step1_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_step1_grid.add_theme_constant_override("h_separation", 14)
	_step1_grid.add_theme_constant_override("v_separation", 14)
	step1_vbox.add_child(_step1_grid)
	
	# 替补区 — 固定在审讯区坐标（与正常模式 PRISON_Y=940 对应的屏幕位置 Y≈942）
	# 正常模式 PRISON_X_GAP=350, 卡片宽154.2 → 间距=350-154.2≈196
	_step1_prison_row = HBoxContainer.new()
	_step1_prison_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_step1_prison_row.add_theme_constant_override("separation", -7)
	_step1_prison_row.position = Vector2(-2.0, 942 - 80)  # 屏幕 Y≈942，卡片高160 → 顶部=862
	_step1_prison_row.size = Vector2(1920, 160)
	_step1_prison_row.visible = false
	add_child(_step1_prison_row)
	
	# --- 3. 步骤2：底部卡片坞 ---
	_step2_panel = PanelContainer.new()
	_step2_panel.custom_minimum_size = Vector2(0, 205)
	_step2_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_step2_panel)
	# _step2_panel 的尺寸和坐标已交由 _on_viewport_size_changed 手动接管
	
	var style_bot := StyleBoxFlat.new()
	style_bot.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style_bot.border_width_left = 2
	style_bot.border_width_right = 2
	style_bot.border_width_top = 2
	style_bot.border_width_bottom = 2
	style_bot.border_color = Color(0.7, 0.55, 0.2, 0.8)
	style_bot.corner_radius_top_left = 12
	style_bot.corner_radius_top_right = 12
	style_bot.corner_radius_bottom_left = 12
	style_bot.corner_radius_bottom_right = 12
	style_bot.content_margin_left = 16
	style_bot.content_margin_right = 16
	style_bot.content_margin_top = 10
	style_bot.content_margin_bottom = 10
	_step2_panel.add_theme_stylebox_override("panel", style_bot)
	
	var step2_vbox := VBoxContainer.new()
	step2_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_step2_panel.add_child(step2_vbox)
	
	var placement_tip := Label.new()
	placement_tip.text = "操作提示：在下方选择一张卡片，然后点击棋盘上的高亮插槽将其放置在对应位置"
	placement_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placement_tip.add_theme_font_size_override("font_size", 14)
	placement_tip.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	step2_vbox.add_child(placement_tip)
	
	var scroll2 := ScrollContainer.new()
	scroll2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	step2_vbox.add_child(scroll2)
	
	_step2_hbox = HBoxContainer.new()
	_step2_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_step2_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step2_hbox.add_theme_constant_override("separation", 8)
	scroll2.add_child(_step2_hbox)

	# --- 4. 步骤3：关系提示文字 ---
	_relation_tip_label = Label.new()
	_relation_tip_label.text = "点击卡片来绘制关系连线"
	_relation_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_relation_tip_label.add_theme_font_size_override("font_size", 18)
	_relation_tip_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	_relation_tip_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_relation_tip_label.position = Vector2(960 - 200, 800)
	_relation_tip_label.size = Vector2(400, 40)
	_relation_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_relation_tip_label.visible = false
	add_child(_relation_tip_label)

# ===== 步骤3：选择连线类型 =====
func _select_relation_mode(mode: int):
	_step3_relation_mode = mode
	_step3_first_selected_member = ""
	
	_btn_trust.button_pressed = (mode == 0)
	_btn_rival.button_pressed = (mode == 1)
	_btn_clear.button_pressed = (mode == 2)
	
	_relation_tip_label.text = "选择要连接的第一张卡片..."

# ===== 状态改变 & UI 刷新 =====
func _update_step_ui():
	# 显式控制手动管理的替补卡牌节点的可见性，防止在步骤 2/3 依然遗留在屏幕上
	for mname in _benched_card_nodes:
		var node = _benched_card_nodes[mname]
		if is_instance_valid(node):
			node.visible = (_current_step == 1)

	# 刷新步骤文字
	match _current_step:
		1:
			_step_label.text = "步骤 1 / 3: 选择3名成员作为替补 (" + str(_benched_members.size()) + " / 3)"
			_step1_panel.visible = true
			_step2_panel.visible = false
			_relation_hbox.visible = false
			_relation_tip_label.visible = false
			
			_back_btn.disabled = true
			_next_btn.text = "确定替补"
			_next_btn.disabled = (_benched_members.size() != 3)
			_reset_btn.visible = true
			
			_connect_slot_inputs(false)
			_rebuild_step1_grid()
		2:
			_step_label.text = "步骤 2 / 3: 摆放卡片位置 (" + str(_get_placed_count()) + " / 14)"
			_step1_panel.visible = false
			_step1_prison_row.visible = false
			_step2_panel.visible = true
			_relation_hbox.visible = false
			_relation_tip_label.visible = false
			
			_back_btn.disabled = false
			_next_btn.text = "下一步"
			_next_btn.disabled = (_get_placed_count() != 14)
			_reset_btn.visible = true
			
			_connect_slot_inputs(true)
			_rebuild_step2_dock()
		3:
			_step_label.text = "步骤 3 / 3: 编辑成员关系"
			_step1_panel.visible = false
			_step1_prison_row.visible = false
			_step2_panel.visible = false
			_relation_hbox.visible = true
			_relation_tip_label.visible = true
			
			_back_btn.disabled = false
			_next_btn.text = "完成布阵"
			_next_btn.disabled = false
			_reset_btn.visible = false
			
			_connect_slot_inputs(false)
			if _step3_relation_mode == -1:
				_select_relation_mode(0) # 默认选中绿线
func _create_card_node(mname: String, is_benched: bool) -> PanelContainer:
	var card_scale := 0.9 * 0.42
	var bg_w := 408.0 * card_scale
	var bg_h := 422.0 * card_scale
	var container := PanelContainer.new()
	container.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var card_area := Control.new()
	card_area.custom_minimum_size = Vector2(bg_w, bg_h)
	card_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(card_area)

	var bg_tex := TextureRect.new()
	bg_tex.texture = preload("res://辛迪加素材/人物背景.png")
	bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
	bg_tex.size = Vector2(bg_w, bg_h)
	bg_tex.position = Vector2.ZERO
	card_area.add_child(bg_tex)

	var p_tex := TextureRect.new()
	p_tex.texture = _portrait_cache.get(mname)
	p_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	p_tex.size = Vector2(bg_w, bg_h)
	p_tex.position = Vector2.ZERO
	card_area.add_child(p_tex)

	var lbl := Label.new()
	lbl.text = mname
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var name_display := roundi(48.0 * card_scale)
	var scale_factor := name_display / 48.0
	lbl.add_theme_font_size_override("font_size", 48)
	lbl.add_theme_color_override("font_color", Color(0, 0, 0))
	lbl.remove_theme_color_override("font_shadow_color")
	lbl.size = Vector2(ceil(bg_w / scale_factor), 48)
	lbl.scale = Vector2(scale_factor, scale_factor)
	
	var lbl_y := bg_h - name_display - 18
	lbl.position = Vector2(0, lbl_y)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_area.add_child(lbl)

	var btn := Button.new()
	btn.flat = true
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(func(): _toggle_member_selection(mname, container))
	container.add_child(btn)
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)

	return container

# ===== 重新构建步骤1的成员网格 =====
func _rebuild_step1_grid():
	for child in _step1_grid.get_children():
		child.queue_free()

	for mname in GameManager.MEMBER_DEFS:
		var is_benched := mname in _benched_members
		var is_animating := mname in _animating_members
		
		# 在 Grid 容器中始终生成并保留该卡牌，以保持固定排版（在 Grid 中不显示“替补”字样牌子，仅作半透明占位）
		var grid_card := _create_card_node(mname, false)
		
		# 如果是替补或正在播放替补动画的卡片，在 Grid 中半透明化展示占位
		if is_benched or is_animating:
			grid_card.modulate.a = 0.25
		else:
			grid_card.modulate.a = 1.0
			
		_step1_grid.add_child(grid_card)

	_step1_prison_row.visible = false # 手动管理替补卡牌节点在 self 下，不再使用 _step1_prison_row 装载子节点

func _toggle_member_selection(mname: String, container: PanelContainer):
	if mname in _animating_members:
		return

	if mname in _benched_members:
		# unbench: 从替补席返回 Grid
		var bench_idx = _benched_members.find(mname)
		var grid_idx = GameManager.MEMBER_DEFS.find(mname)
		var grid_container = _step1_grid.get_child(grid_idx) as PanelContainer
		var target_pos = grid_container.global_position
		
		_benched_members.erase(mname)
		_animating_members.append(mname)
		
		# 取得对应的替补卡牌节点并取消其字典关联，开始向 grid 飞回
		var card_node = _benched_card_nodes.get(mname)
		if card_node:
			_benched_card_nodes.erase(mname)
			
			# 平滑地让剩下的替补卡牌补位对齐，这会使用 Tween 动画移动它们，非常流畅！
			_layout_benched_cards()
			
			var tween := create_tween()
			tween.tween_property(card_node, "position", target_pos, 0.35)\
				.set_ease(Tween.EASE_OUT)\
				.set_trans(Tween.TRANS_CUBIC)
			tween.tween_callback(func():
				_animating_members.erase(mname)
				card_node.queue_free()
				_update_step_ui()
			)
		
		_update_step_ui()
	else:
		# bench: 从 Grid 进入替补席
		if _benched_members.size() < 3:
			_benched_members.append(mname)
			
			# 创建并在 SandboxSetupWizard 根部直接添加该替补卡片（用作飞行和定位）
			var card_node = _create_card_node(mname, true)
			add_child(card_node)
			
			# 设置起点为 grid 中卡片的全局坐标
			card_node.position = container.global_position
			_benched_card_nodes[mname] = card_node
			
			# 立即刷新 grid 中被选中卡片的半透明状态
			_update_step_ui()
			
			# 重新布局所有的替补卡牌（这会让新卡牌和现有的卡牌都使用 Tween 动画顺滑地移动到重新排布后的位置）
			_layout_benched_cards()

# ===== 平滑重新规划（对齐）替补区域卡片位置 =====
func _layout_benched_cards():
	var M := _benched_members.size()
	if M == 0:
		return
		
	var card_scale := 0.9 * 0.42
	var bg_w := 408.0 * card_scale
	var bg_h := 422.0 * card_scale
	
	# 计算让 M 张卡片在屏幕底部居中（中心为 958 像素，Y 在 862 像素处）的 target_pos
	var gap := bg_w - 7.0
	var total_w := M * gap + 7.0
	var start_x := 958.0 - total_w * 0.5
	
	for i in range(M):
		var mname = _benched_members[i]
		var card_node = _benched_card_nodes.get(mname)
		if card_node:
			var target_pos := Vector2(start_x + i * gap, 862.0)
			
			# 使用 Tween 进行平滑动效移动，彻底告别原 HBoxContainer 重排时的卡顿跳跃！
			var tween := create_tween()
			tween.tween_property(card_node, "position", target_pos, 0.35)\
				.set_ease(Tween.EASE_OUT)\
				.set_trans(Tween.TRANS_CUBIC)



# ===== 获取已放置的成员数量 =====
func _get_placed_count() -> int:
	var count = 0
	for mname in _selected_members:
		var m = GameManager.members.get(mname)
		if m and m.is_on_board:
			count += 1
	return count

# ===== 重新构建步骤2的底部坞 =====
func _rebuild_step2_dock():
	for child in _step2_hbox.get_children():
		child.queue_free()
		
	for mname in _selected_members:
		var member = GameManager.members.get(mname)
		if member == null:
			continue
			
		var container := PanelContainer.new()
		container.custom_minimum_size = Vector2(110, 140)
		
		var style := StyleBoxFlat.new()
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		
		if member.is_on_board:
			# 已放置：半透明且加上勾选框
			style.bg_color = Color(0.1, 0.1, 0.15, 0.4)
			style.border_color = Color(0.2, 0.6, 0.8, 0.3)
		else:
			if mname == _active_placement_member:
				style.bg_color = Color(0.2, 0.25, 0.4, 0.95) # 选中待放置
				style.border_color = Color(0.4, 0.6, 1.0, 1.0)
			else:
				style.bg_color = Color(0.15, 0.15, 0.2, 0.9)
				style.border_color = Color(0.5, 0.5, 0.5, 0.6)
				
		container.add_theme_stylebox_override("panel", style)
		
		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		container.add_child(vbox)
		
		# 头像
		var p_tex = TextureRect.new()
		p_tex.texture = load(member.portrait_path)
		p_tex.custom_minimum_size = Vector2(85, 85)
		p_tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		p_tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		p_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # 不随原始图片尺寸膨胀
		p_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vbox.add_child(p_tex)
		
		# 名字
		var lbl := Label.new()
		lbl.text = mname
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		vbox.add_child(lbl)
		
		# 放置说明
		var state_lbl := Label.new()
		state_lbl.add_theme_font_size_override("font_size", 10)
		state_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		
		if member.is_on_board:
			if member.division == GameManager.Division.NONE:
				state_lbl.text = "🟢 自由人"
				state_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
			else:
				var div_name = GameManager.DIVISION_NAMES.get(member.division, "")
				var role_name = "首领" if member.is_leader else "部下"
				state_lbl.text = "🟢 " + div_name + role_name
				state_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
		else:
			state_lbl.text = "❌ 未摆放"
			state_lbl.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
		vbox.add_child(state_lbl)
		
		# 交互按钮
		var btn := Button.new()
		btn.flat = true
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		
		# 如果已摆放，点击则可以召回；如果未摆放，点击则选中准备摆放
		btn.pressed.connect(func():
			if member.is_on_board:
				# 召回该成员
				member.is_on_board = false
				member.division = GameManager.Division.NONE
				member.is_leader = false
				member.rank = 0
				_active_placement_member = ""
				GameManager.board_changed.emit()
			else:
				_active_placement_member = mname
			_update_step_ui()
		)
		container.add_child(btn)
		
		_step2_hbox.add_child(container)

# ===== 按钮事件 =====
func _on_back_pressed():
	if _current_step > 1:
		_current_step -= 1
		_update_step_ui()

func _on_next_pressed():
	if _current_step == 1:
		if _benched_members.size() == 3:
			# 根据排除逻辑，剩余14个成员进入上场名单
			_selected_members.clear()
			for mname in GameManager.MEMBER_DEFS:
				if mname not in _benched_members:
					_selected_members.append(mname)
			
			# 初始化游戏数据为沙盒模式并确定 active 人员
			GameManager.initialize_sandbox_mode(_selected_members)
			_current_step = 2
			_update_step_ui()
	elif _current_step == 2:
		if _get_placed_count() == 14:
			_current_step = 3
			_update_step_ui()
	elif _current_step == 3:
		# 完成布阵，隐藏所有插槽，通知外面
		_connect_slot_inputs(false)
		completed.emit()
		queue_free()

func _on_reset_pressed():
	if _current_step == 1:
		# 清空重置时也需要清理所有生成的替补卡牌节点并释放内存
		for mname in _benched_card_nodes:
			var node = _benched_card_nodes[mname]
			if is_instance_valid(node):
				node.queue_free()
		_benched_card_nodes.clear()
		_benched_members.clear()
		_update_step_ui()
	elif _current_step == 2:
		# 重置所有的放置状态
		for mname in _selected_members:
			var m = GameManager.members.get(mname)
			if m:
				m.is_on_board = false
				m.division = GameManager.Division.NONE
				m.is_leader = false
				m.rank = 0
		_active_placement_member = ""
		GameManager.board_changed.emit()
		_update_step_ui()

func _on_close_pressed():
	_connect_slot_inputs(false)
	
	# 退出沙盒模式，重置游戏数据为正常随机模式
	GameManager.is_sandbox_mode = false
	GameManager.initialize_game()
	
	closed.emit()
	queue_free()
