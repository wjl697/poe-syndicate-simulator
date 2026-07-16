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

# 预设数据状态
var _presets_dict: Dictionary = {}
var _active_preset_name: String = ""

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
var _btn_clear_all: Button

# 步骤1的中间选择区域
var _step1_panel: PanelContainer
var _step1_grid: GridContainer
var _step1_prison_row: HBoxContainer

# 步骤2的底部卡片坞
var _step2_panel: PanelContainer
var _step2_hbox: HBoxContainer

# 连线提示 label
var _relation_tip_label: Label

# 预设与控制按钮组件
var _preset_selector: OptionButton
var _btn_manage_presets: Button
var _btn_auto_fill: Button
var _btn_recall_all: Button

# 缓存所有插槽引用
var _portrait_cache: Dictionary = {}       # 缓存所有成员的头像纹理，避免动画播放中发生磁盘 I/O
var _all_slots: Array[ColorRect] = []

# 属性设置与悬停预览面板状态
var _active_editor_overlay: Control = null
var _pending_hover_member: String = ""
var _hover_timer: SceneTreeTimer = null

func _ready():
	add_to_group("sandbox_wizard")
	# 允许鼠标穿透根节点，因为我们要点击背后的棋盘卡片
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_init_presets_system()
	
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
		var panel_h = 220.0
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
			var card = _get_board_node()
			if card and card.has_method("highlight_cards"):
				card.highlight_cards([mname])
		else:
			var first = _step3_first_selected_member
			_step3_first_selected_member = ""
			_relation_tip_label.text = "点击卡片来绘制关系连线"
			
			# 取消高亮
			var card = _get_board_node()
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

# ===== 响应主棋盘卡片被悬停的事件 =====
func handle_board_card_hovered(mname: String, screen_pos: Vector2):
	if _current_step != 4:
		return
	var m = GameManager.members.get(mname)
	if m == null or m.division == GameManager.Division.NONE:
		return
		
	_pending_hover_member = mname
	var timer = get_tree().create_timer(0.12)
	_hover_timer = timer
	await timer.timeout
	
	if _hover_timer == timer and _pending_hover_member == mname:
		_show_card_editor_overlay(mname, screen_pos)

func handle_board_card_unhovered(mname: String):
	if _pending_hover_member == mname:
		_pending_hover_member = ""

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
	
	_btn_manage_presets = Button.new()
	_btn_manage_presets.text = "📂 预设管理"
	_btn_manage_presets.pressed.connect(_show_presets_management_popup)
	top_hbox.add_child(_btn_manage_presets)
	
	var separator_pre := VSeparator.new()
	separator_pre.add_theme_constant_override("separation", 20)
	top_hbox.add_child(separator_pre)
	
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
	
	var relation_sep := VSeparator.new()
	relation_sep.add_theme_constant_override("separation", 10)
	_relation_hbox.add_child(relation_sep)
	
	_btn_clear_all = Button.new()
	_btn_clear_all.text = "❌ 清除所有关系"
	_btn_clear_all.pressed.connect(func():
		GameManager.relationships.clear()
		_step3_first_selected_member = ""
		_relation_tip_label.text = "点击卡片来绘制关系连线"
		var board = _get_board_node()
		if board and board.has_method("clear_highlights"):
			board.clear_highlights()
	)
	_relation_hbox.add_child(_btn_clear_all)
	
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
	
	_btn_auto_fill = Button.new()
	_btn_auto_fill.text = "🤖 自动排兵"
	_btn_auto_fill.pressed.connect(_on_auto_fill_pressed)
	btn_hbox.add_child(_btn_auto_fill)
	
	_btn_recall_all = Button.new()
	_btn_recall_all.text = "❌ 全部收回"
	_btn_recall_all.pressed.connect(_on_recall_all_pressed)
	btn_hbox.add_child(_btn_recall_all)
	
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
	_step2_panel.custom_minimum_size = Vector2(0, 220)
	_step2_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_step2_panel)
	# _step2_panel 的尺寸和坐标已交由 _on_viewport_size_changed 手动接管
	
	var style_bot := StyleBoxEmpty.new()
	style_bot.content_margin_left = 16
	style_bot.content_margin_right = 16
	style_bot.content_margin_top = 0
	style_bot.content_margin_bottom = 0
	_step2_panel.add_theme_stylebox_override("panel", style_bot)
	
	var step2_vbox := VBoxContainer.new()
	step2_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	step2_vbox.add_theme_constant_override("separation", 14)
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
	# 显式控制手动管理的替补卡牌节点的可见性，防止在步骤 2/3/4 依然遗留在屏幕上
	for mname in _benched_card_nodes:
		var node = _benched_card_nodes[mname]
		if is_instance_valid(node):
			node.visible = (_current_step == 1)

	# 显式控制预设管理按钮的显示（仅步骤1和步骤4可用）
	if is_instance_valid(_btn_manage_presets):
		_btn_manage_presets.visible = (_current_step == 1 or _current_step == 4)

	# 刷新步骤文字
	match _current_step:
		1:
			_step_label.text = "步骤 1 / 4: 选择3名成员作为替补 (" + str(_benched_members.size()) + " / 3)"
			_step1_panel.visible = true
			_step2_panel.visible = false
			_relation_hbox.visible = false
			_relation_tip_label.visible = false
			
			_back_btn.disabled = true
			_next_btn.text = "确定替补"
			_next_btn.disabled = (_benched_members.size() != 3)
			_reset_btn.visible = true
			
			if is_instance_valid(_btn_auto_fill): _btn_auto_fill.visible = false
			if is_instance_valid(_btn_recall_all): _btn_recall_all.visible = false
			
			_connect_slot_inputs(false)
			_rebuild_step1_grid()
			_sync_benched_card_nodes()
		2:
			_step_label.text = "步骤 2 / 4: 部署部门成员 (" + str(_get_placed_count()) + " / 14)"
			_step1_panel.visible = false
			_step1_prison_row.visible = false
			_step2_panel.visible = true
			_relation_hbox.visible = false
			_relation_tip_label.visible = false
			
			_back_btn.disabled = false
			_next_btn.text = "下一步"
			_next_btn.disabled = false # 取消14张必须强行手动拉出的强制性，未分配的自动变为游民
			_reset_btn.visible = true
			
			# 二步不再显示自动排兵按钮，改由玩家手动分配或通过一步预设初始化
			if is_instance_valid(_btn_auto_fill): _btn_auto_fill.visible = false
			if is_instance_valid(_btn_recall_all): _btn_recall_all.visible = true
			
			_connect_slot_inputs(true)
			_rebuild_step2_dock()
		3:
			_step_label.text = "步骤 3 / 4: 绘制成员关系线"
			_step1_panel.visible = false
			_step1_prison_row.visible = false
			_step2_panel.visible = false
			_relation_hbox.visible = true
			_relation_tip_label.visible = true
			_relation_tip_label.text = "点击卡片来绘制关系连线"
			
			_back_btn.disabled = false
			_next_btn.text = "下一步"
			_next_btn.disabled = false
			_reset_btn.visible = false
			
			if is_instance_valid(_btn_auto_fill): _btn_auto_fill.visible = false
			if is_instance_valid(_btn_recall_all): _btn_recall_all.visible = false
			
			_connect_slot_inputs(false)
			if _step3_relation_mode == -1:
				_select_relation_mode(0) # 默认选中绿线
		4:
			_step_label.text = "步骤 4 / 4: 调整成员星级与监禁状态"
			_step1_panel.visible = false
			_step1_prison_row.visible = false
			_step2_panel.visible = false
			_relation_hbox.visible = false
			_relation_tip_label.visible = true
			_relation_tip_label.text = "点击棋盘卡牌打开状态面板，调整其星级和被关押回合数"
			
			_back_btn.disabled = false
			_next_btn.text = "完成布阵"
			_next_btn.disabled = false
			_reset_btn.visible = false
			
			if is_instance_valid(_btn_auto_fill): _btn_auto_fill.visible = false
			if is_instance_valid(_btn_recall_all): _btn_recall_all.visible = false
			
			_connect_slot_inputs(false)
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
	bg_tex.texture = preload("res://辛迪加素材/界面UI/人物背景.png")
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
		
	var card_scale := 0.9 * 0.42
	var bg_w := 408.0 * card_scale
	var bg_h := 422.0 * card_scale

	for mname in _selected_members:
		var member = GameManager.members.get(mname)
		if member == null:
			continue
			
		var container := PanelContainer.new()
		container.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		
		var card_area := Control.new()
		card_area.custom_minimum_size = Vector2(bg_w, bg_h)
		card_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(card_area)

		# 1. 纸张背景
		var bg_tex := TextureRect.new()
		bg_tex.texture = preload("res://辛迪加素材/界面UI/人物背景.png")
		bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
		bg_tex.size = Vector2(bg_w, bg_h)
		bg_tex.position = Vector2.ZERO
		card_area.add_child(bg_tex)

		# 2. 角色头像
		var p_tex := TextureRect.new()
		p_tex.texture = _portrait_cache.get(mname)
		p_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		p_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		p_tex.size = Vector2(bg_w, bg_h)
		p_tex.position = Vector2.ZERO
		card_area.add_child(p_tex)

		# 3. 名字文本
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

		# 4. 如果是选中状态，在外部加一层发光蓝框
		if mname == _active_placement_member:
			var highlight := Panel.new()
			var style_hl := StyleBoxFlat.new()
			style_hl.draw_center = false
			style_hl.border_width_left = 3
			style_hl.border_width_top = 3
			style_hl.border_width_right = 3
			style_hl.border_width_bottom = 3
			style_hl.border_color = Color(0.15, 0.55, 0.95, 1.0)
			style_hl.shadow_color = Color(0.15, 0.55, 0.95, 0.5)
			style_hl.shadow_size = 5
			highlight.add_theme_stylebox_override("panel", style_hl)
			highlight.size = Vector2(bg_w, bg_h)
			highlight.position = Vector2.ZERO
			highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card_area.add_child(highlight)

		# 5. 如果已经上阵摆放，在底部坞做半透明置灰
		if member.is_on_board:
			container.modulate.a = 0.25
		else:
			container.modulate.a = 1.0

		# 6. 点击事件交互按钮
		var btn := Button.new()
		btn.flat = true
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		
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
				if _active_placement_member == mname:
					# 再次点击取消选中
					_active_placement_member = ""
				else:
					_active_placement_member = mname
			_update_step_ui()
		)
		container.add_child(btn)
		
		_step2_hbox.add_child(container)

# ===== 按钮事件 =====
func _on_back_pressed():
	if is_instance_valid(_active_editor_overlay):
		_active_editor_overlay.queue_free()
		_active_editor_overlay = null

	if _current_step > 1:
		# 如果从步骤3退回步骤2，清除建立关系的选择状态和卡牌高亮，防止效果残留
		if _current_step == 3:
			_step3_first_selected_member = ""
			var card = _get_board_node()
			if card:
				if card.has_method("clear_highlights"):
					card.clear_highlights()
			
			# 同时，将所有没有分配部门的成员（自由人）重新退回为未放置状态（回到下方坞中）
			for mname in _selected_members:
				var m = GameManager.members.get(mname)
				if m and m.division == GameManager.Division.NONE:
					m.is_on_board = false
					m.is_leader = false
					m.rank = 0
			GameManager.board_changed.emit()

		_current_step -= 1
		
		# 如果返回到了步骤1，清空所有已放置的卡片状态并同步棋盘，防止卡片遗留在背景中
		if _current_step == 1:
			for mname in GameManager.MEMBER_DEFS:
				var m = GameManager.members.get(mname)
				if m:
					m.is_on_board = false
					m.division = GameManager.Division.NONE
					m.is_leader = false
					m.rank = 0
			_active_placement_member = ""
			GameManager.board_changed.emit()
			
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
			
			# 显式初始化这 14 个人为未放置状态（待在底部 dock 里，is_on_board = false）
			for mname in _selected_members:
				var m = GameManager.members.get(mname)
				if m:
					m.is_on_board = false
					m.division = GameManager.Division.NONE
					m.is_leader = false
					m.rank = 0
			
			_current_step = 2
			_update_step_ui()
	elif _current_step == 2:
		# 验证当前已被拖放到具体部门的卡片合理性
		var validation_error = _validate_step2_layout()
		if validation_error != "":
			_show_validation_error_popup(validation_error)
			return
		
		# 校验通过：将剩余未摆放的卡片（仍在 dock 里的）自动设为游民上阵并放置到自由人槽位
		for mname in _selected_members:
			var m = GameManager.members.get(mname)
			if m and not m.is_on_board:
				m.is_on_board = true
				m.division = GameManager.Division.NONE
				m.is_leader = false
				m.rank = 0
		
		# 成功后，同步板子状态并推进到步骤3
		GameManager.board_changed.emit()
		_current_step = 3
		_update_step_ui()
	elif _current_step == 3:
		# 关系连线绘制完毕，推进到第四步星级与监禁属性设置
		_current_step = 4
		_update_step_ui()
	elif _current_step == 4:
		# 完成布阵前，最后进行一次合规校验，防止属性调整阶段违背了人数限制
		var validation_error = _validate_board_layout()
		if validation_error != "":
			_show_validation_error_popup(validation_error)
			return

		# 完成布阵，隐藏所有插槽，通知外面
		_connect_slot_inputs(false)
		completed.emit()
		queue_free()

func _validate_board_layout() -> String:
	# 1. 验证总数
	var count = 0
	for mname in _selected_members:
		var m = GameManager.members.get(mname)
		if m and m.is_on_board:
			count += 1
	if count != 14:
		return "场上必须有且仅有 14 名成员（当前已放置了 " + str(count) + " 名）"
	
	# 2. 验证每个部门的首领和人数 (最少2人，最多5人，且必须有首领)
	var div_counts := {}
	var div_leaders := {}
	for div in [GameManager.Division.TRANSPORT, GameManager.Division.FORTIFICATION, GameManager.Division.RESEARCH, GameManager.Division.INTERVENTION]:
		div_counts[div] = 0
		div_leaders[div] = 0
		
	for mname in _selected_members:
		var m = GameManager.members.get(mname)
		if m and m.is_on_board and m.division != GameManager.Division.NONE:
			div_counts[m.division] = div_counts.get(m.division, 0) + 1
			if m.is_leader:
				div_leaders[m.division] = div_leaders.get(m.division, 0) + 1
				
	for div in div_counts:
		var c = div_counts[div]
		var l = div_leaders[div]
		var div_name = GameManager.DIVISION_NAMES.get(div, "未知")
		
		# 必须有且仅有1名首领
		if l != 1:
			return div_name + " 部门必须有且仅有 1 名首领（当前有 " + str(l) + " 名）"
			
		# 总人数最少2人，最多5人
		if c < 2:
			return div_name + " 部门总人数不足（最少 2 人，当前仅有 " + str(c) + " 人）"
		if c > 5:
			return div_name + " 部门总人数过多（最多 5 人，当前已有 " + str(c) + " 人）"
			
	return ""

func _validate_step2_layout() -> String:
	# 仅验证被放置到具体部门的卡牌是否符合首领及人数法则（游民和仍待在 dock 中的卡片不算在内）
	var div_counts := {}
	var div_leaders := {}
	for div in [GameManager.Division.TRANSPORT, GameManager.Division.FORTIFICATION, GameManager.Division.RESEARCH, GameManager.Division.INTERVENTION]:
		div_counts[div] = 0
		div_leaders[div] = 0
		
	for mname in _selected_members:
		var m = GameManager.members.get(mname)
		if m and m.is_on_board and m.division != GameManager.Division.NONE:
			div_counts[m.division] = div_counts.get(m.division, 0) + 1
			if m.is_leader:
				div_leaders[m.division] = div_leaders.get(m.division, 0) + 1
				
	for div in div_counts:
		var c = div_counts[div]
		var l = div_leaders[div]
		var div_name = GameManager.DIVISION_NAMES.get(div, "未知")
		
		# 每个部门必须有且仅有1名首领
		if l != 1:
			return div_name + " 部门必须有且仅有 1 名首领（当前有 " + str(l) + " 名）"
			
		# 每个部门总人数必须在 2 至 5 人之间
		if c < 2:
			return div_name + " 部门总人数不足（最少 2 人，当前仅有 " + str(c) + " 人）"
		if c > 5:
			return div_name + " 部门总人数过多（最多 5 人，当前已有 " + str(c) + " 人）"
			
	return ""

func _show_validation_error_popup(message: String) -> void:
	var backdrop := Control.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	
	var color_rect := ColorRect.new()
	color_rect.color = Color(0, 0, 0, 0.45)
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(color_rect)
	
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.16, 0.99)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.8, 0.3, 0.3, 0.8) # 红色边框表示错误
	style.shadow_color = Color(0, 0, 0, 0.8)
	style.shadow_size = 10
	style.content_margin_left = 25
	style.content_margin_right = 25
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	
	var panel_size := Vector2(400, 180)
	panel.size = panel_size
	var vp := get_viewport_rect().size
	panel.position = Vector2((vp.x - panel_size.x) * 0.5, (vp.y - panel_size.y) * 0.5)
	backdrop.add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	
	var title_lbl := Label.new()
	title_lbl.text = "布局验证未通过"
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)
	
	var msg_lbl := Label.new()
	msg_lbl.text = message
	msg_lbl.add_theme_font_size_override("font_size", 14)
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(msg_lbl)
	
	var btn := Button.new()
	btn.text = "确定"
	btn.custom_minimum_size = Vector2(100, 30)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func(): backdrop.queue_free())
	vbox.add_child(btn)

func _show_card_editor_overlay(mname: String, screen_pos: Vector2) -> void:
	if is_instance_valid(_active_editor_overlay):
		# 如果已经有打开的编辑器面板，且就是该成员，直接返回
		if _active_editor_overlay.name == "editor_" + mname:
			return
		# 否则，先销毁旧面板以展示新面板
		_active_editor_overlay.queue_free()
		_active_editor_overlay = null
		
	var m = GameManager.members.get(mname)
	if m == null or m.division == GameManager.Division.NONE:
		return
		
	# 1. 创建黑色半透明背景遮罩容器 (无需暗色背景，保持游戏界面明亮)
	var backdrop := Control.new()
	backdrop.name = "editor_" + mname
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_active_editor_overlay = backdrop
	
	# 计算自适应对齐定位参数 (与普通模式的中心点对齐算法一致)
	var center := screen_pos
	var slot_w := 194.0
	var slot_h := 236.0
	var vp_size := get_viewport_rect().size
	
	# --- Y轴边界限制 ---
	var min_y: float = slot_h * 0.5 + 20.0
	var max_y: float = vp_size.y - slot_h * 0.5 - 20.0
	center.y = clampf(center.y, min_y, max_y)
	
	# --- X轴边界限制 ---
	var min_x: float = slot_w * 1.5 + 20.0
	var max_x: float = vp_size.x - slot_w * 1.5 - 20.0
	center.x = clampf(center.x, min_x, max_x)
	
	# 2. 第一层：透明黑色背板 (三连板) 并命名为 Panel 用于划出判定
	var base_bg := ColorRect.new()
	base_bg.name = "Panel"
	base_bg.color = Color(0, 0, 0, 0.88)
	base_bg.size = Vector2(slot_w * 3, slot_h)
	base_bg.position = center - Vector2(slot_w * 1.5, slot_h * 0.5)
	base_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.add_child(base_bg)
	
	# 3. 第二层：加载并渲染“选项背板.png”艺术图
	var tex_btn_bg := preload("res://辛迪加素材/界面UI/选项背板.png")
	var frame_size := tex_btn_bg.get_size() * 0.75
	var middle_frame := TextureRect.new()
	middle_frame.texture = tex_btn_bg
	middle_frame.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	middle_frame.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	middle_frame.size = frame_size
	middle_frame.scale = Vector2(0.75, 0.75)
	# 完美的 Y 轴对齐偏移量 (-11)
	middle_frame.position = center - frame_size * 0.5 + Vector2(0, -11)
	middle_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(middle_frame)
	
	# 4. 第三层：卡片与按钮的内容容器
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	hbox.size = Vector2(slot_w * 3, slot_h)
	hbox.position = base_bg.position
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(hbox)
	
	var left_section := Control.new()
	left_section.custom_minimum_size = Vector2(194, 236)
	hbox.add_child(left_section)
	
	var center_section := Control.new()
	center_section.custom_minimum_size = Vector2(194, 236)
	hbox.add_child(center_section)
	
	var right_section := Control.new()
	right_section.custom_minimum_size = Vector2(194, 236)
	hbox.add_child(right_section)
	
	# --- 中间栏：一比一复刻普通模式下的卡牌与释放按钮渲染 ---
	# 加载卡牌渲染所需的各种美术材质
	var tex_card_bg := preload("res://辛迪加素材/界面UI/人物背景.png")
	var tex_halo_mem := preload("res://辛迪加素材/界面UI/成员光晕.png")
	var tex_halo_lead := preload("res://辛迪加素材/界面UI/首领光晕.png")
	
	var sync_offset := Vector2(0, -11)
	var card_native_size := tex_card_bg.get_size()
	var auto_scale_f := 188.0 / card_native_size.y
	var card_scale := Vector2(auto_scale_f, auto_scale_f)
	
	# 1. 卡片背景 (单独下移 11 像素)
	var card_bg_sprite := Sprite2D.new()
	card_bg_sprite.texture = tex_card_bg
	card_bg_sprite.position = center + Vector2(0, 11) + sync_offset
	card_bg_sprite.scale = card_scale
	backdrop.add_child(card_bg_sprite)
	
	# 2. 卡牌光晕 (与 member_card.gd 保持一致的缩放与 Y 轴偏移比例)
	var card_halo_sprite := Sprite2D.new()
	card_halo_sprite.texture = tex_halo_lead if m.is_leader else tex_halo_mem
	card_halo_sprite.position = card_bg_sprite.position + Vector2(0, tex_card_bg.get_size().y * auto_scale_f * MemberCard.HALO_Y_OFFSET_RATIO)
	card_halo_sprite.scale = card_scale * MemberCard.HALO_SCALE_MULT
	backdrop.add_child(card_halo_sprite)
	
	# 3. 头像 (与 member_card.gd 保持一致的缩放与 Y 轴偏移比例)
	var portrait_sprite := Sprite2D.new()
	var ptex: Texture2D = load(m.portrait_path)
	if ptex:
		portrait_sprite.texture = ptex
		var bg_size := tex_card_bg.get_size() * auto_scale_f
		var p_size: Vector2 = ptex.get_size()
		var fit: float = minf(bg_size.x * MemberCard.PORTRAIT_FIT_SCALE / p_size.x, bg_size.y * MemberCard.PORTRAIT_FIT_SCALE / p_size.y)
		portrait_sprite.scale = Vector2(fit, fit)
	portrait_sprite.position = card_bg_sprite.position + Vector2(0, tex_card_bg.get_size().y * auto_scale_f * MemberCard.PORTRAIT_Y_OFFSET_RATIO)
	backdrop.add_child(portrait_sprite)
	
	# 4. 部门标志 (左上角角标)
	var div_icon_path := ""
	match m.division:
		GameManager.Division.TRANSPORT: div_icon_path = "res://辛迪加素材/界面UI/运输部角标.png"
		GameManager.Division.FORTIFICATION: div_icon_path = "res://辛迪加素材/界面UI/防卫部角标.png"
		GameManager.Division.RESEARCH: div_icon_path = "res://辛迪加素材/界面UI/科研部角标.png"
		GameManager.Division.INTERVENTION: div_icon_path = "res://辛迪加素材/界面UI/调停部角标.png"
		
	if div_icon_path != "" and FileAccess.file_exists(div_icon_path):
		var div_sprite := Sprite2D.new()
		div_sprite.texture = load(div_icon_path)
		div_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		div_sprite.position = card_bg_sprite.position + MemberCard.BADGE_BASE_POS * auto_scale_f
		div_sprite.scale = Vector2(MemberCard.BADGE_BASE_SCALE, MemberCard.BADGE_BASE_SCALE) * auto_scale_f
		div_sprite.modulate.a = 0.8
		backdrop.add_child(div_sprite)
		
	# 5. 星级等级标志 (右上角角标)
	var rank_icon_path := ""
	match m.rank:
		1: rank_icon_path = "res://辛迪加素材/界面UI/一星等级.png"
		2: rank_icon_path = "res://辛迪加素材/界面UI/二星等级.png"
		3: rank_icon_path = "res://辛迪加素材/界面UI/三星等级.png"
		
	if rank_icon_path != "" and FileAccess.file_exists(rank_icon_path):
		var rank_sprite := Sprite2D.new()
		rank_sprite.texture = load(rank_icon_path)
		rank_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		rank_sprite.position = card_bg_sprite.position + MemberCard.STAR_BASE_POS * auto_scale_f
		rank_sprite.scale = Vector2(MemberCard.STAR_BASE_SCALE, MemberCard.STAR_BASE_SCALE) * auto_scale_f
		if m.rank == 3:
			rank_sprite.position += Vector2(-22, -18) * auto_scale_f
		rank_sprite.modulate.a = 0.8
		backdrop.add_child(rank_sprite)
		
	# 6. 文字信息 Label (完全参考 member_card.gd 比例对齐，字号 20 的黑色名字)
	var bg_size_scaled := tex_card_bg.get_size() * auto_scale_f
	var name_lbl := Label.new()
	name_lbl.text = m.member_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color(0, 0, 0))
	name_lbl.size = Vector2(bg_size_scaled.x * 0.8, 30)
	name_lbl.position = card_bg_sprite.position + Vector2(-bg_size_scaled.x * 0.4, bg_size_scaled.y * 0.2)
	backdrop.add_child(name_lbl)
	
	var info_lbl := Label.new()
	info_lbl.text = "首领" if m.is_leader else ""
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.add_theme_font_size_override("font_size", 12)
	info_lbl.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
	info_lbl.size = Vector2(bg_size_scaled.x * 0.8, 22)
	info_lbl.position = card_bg_sprite.position + Vector2(-bg_size_scaled.x * 0.4, bg_size_scaled.y * 0.2 + 30)
	backdrop.add_child(info_lbl)
	
	# 7. 释放按钮：X轴居中，Y轴对齐到背板边缘低处 (一比一复制正常模式)
	var release_btn := Button.new()
	release_btn.text = "释放"
	release_btn.custom_minimum_size = Vector2(110, 30)
	release_btn.position = center + Vector2(-55, 95)
	_style_action_button(release_btn)
	backdrop.add_child(release_btn)
	
	release_btn.pressed.connect(func():
		m.is_imprisoned = false
		m.prison_turns_left = 0
		if mname in GameManager.prison_queue:
			GameManager.prison_queue.erase(mname)
		GameManager.board_changed.emit()
		_active_editor_overlay = null
		backdrop.queue_free()
	)
	
	# --- 临时选择状态 ---
	var selection = {
		"turns": m.prison_turns_left if m.prison_turns_left > 0 else 3,
		"rank": m.rank if m.rank > 0 else 1
	}
	
	var left_opt_btns := []
	var right_opt_btns := []
	
	var update_opt_visuals = func():
		# 刷新左侧刑期选项外观
		for idx in range(3):
			var turns_val = 3 - idx
			var btn = left_opt_btns[idx]
			if selection["turns"] == turns_val:
				btn.text = "▶ 剩余 " + str(turns_val) + " 回合 ◀"
				btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
			else:
				btn.text = "   剩余 " + str(turns_val) + " 回合   "
				btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
				
		# 刷新右侧星级选项外观
		for idx in range(3):
			var rank_val = 3 - idx
			var btn = right_opt_btns[idx]
			var stars = ""
			for s in range(rank_val):
				stars += "★"
			if selection["rank"] == rank_val:
				btn.text = "▶ " + stars + " " + str(rank_val) + "星 ◀"
				btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
			else:
				btn.text = "   " + stars + " " + str(rank_val) + "星   "
				btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
				
	# --- 左侧栏：关押回合数选项 & 审讯按钮 ---
	for idx in range(3):
		var turns_val = 3 - idx
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(160, 30)
		btn.position = Vector2((194.0 - 160) * 0.5, 20.0 + idx * 45.0)
		
		# 使用全透明 StyleBox，仅靠文字和颜色标识选中状态
		var empty_style := StyleBoxEmpty.new()
		btn.add_theme_stylebox_override("normal", empty_style)
		btn.add_theme_stylebox_override("hover", empty_style)
		btn.add_theme_stylebox_override("pressed", empty_style)
		btn.add_theme_font_size_override("font_size", 13)
		
		var val_copy = turns_val
		btn.pressed.connect(func():
			selection["turns"] = val_copy
			update_opt_visuals.call()
		)
		left_section.add_child(btn)
		left_opt_btns.append(btn)
		
	var interrogate_btn := Button.new()
	interrogate_btn.text = "审讯"
	interrogate_btn.custom_minimum_size = Vector2(110, 30)
	interrogate_btn.position = Vector2((194.0 - 110) * 0.5, 236.0 - 38.0)
	_style_action_button(interrogate_btn)
	left_section.add_child(interrogate_btn)
	
	interrogate_btn.pressed.connect(func():
		# 1. 验证牢房是否已满
		var active_prisons_count = GameManager.prison_queue.size()
		if mname in GameManager.prison_queue:
			active_prisons_count -= 1
		if active_prisons_count >= 3:
			_show_validation_error_popup("牢房已满（上限 3 人），请先释放其他在押成员。")
			return
			
		# 2. 如果他是首领，关押将导致卸任并提拔新首领
		if m.is_leader:
			m.is_leader = false
			m.is_imprisoned = true
			m.prison_turns_left = selection["turns"]
			m.prison_intel_division = m.division
			if mname not in GameManager.prison_queue:
				GameManager.prison_queue.append(mname)
			GameManager._promote_new_leader(m.division)
		else:
			m.is_imprisoned = true
			m.prison_turns_left = selection["turns"]
			m.prison_intel_division = m.division
			if mname not in GameManager.prison_queue:
				GameManager.prison_queue.append(mname)
				
		GameManager.board_changed.emit()
		_active_editor_overlay = null
		backdrop.queue_free()
	)
	
	# --- 右侧栏：星级选项 & 处决按钮 ---
	for idx in range(3):
		var rank_val = 3 - idx
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(160, 30)
		btn.position = Vector2((194.0 - 160) * 0.5, 20.0 + idx * 45.0)
		
		var empty_style := StyleBoxEmpty.new()
		btn.add_theme_stylebox_override("normal", empty_style)
		btn.add_theme_stylebox_override("hover", empty_style)
		btn.add_theme_stylebox_override("pressed", empty_style)
		btn.add_theme_font_size_override("font_size", 13)
		
		var val_copy = rank_val
		btn.pressed.connect(func():
			selection["rank"] = val_copy
			update_opt_visuals.call()
		)
		right_section.add_child(btn)
		right_opt_btns.append(btn)
		
	var execute_btn := Button.new()
	execute_btn.text = "处决"
	execute_btn.custom_minimum_size = Vector2(110, 30)
	execute_btn.position = Vector2((194.0 - 110) * 0.5, 236.0 - 38.0)
	_style_action_button(execute_btn)
	right_section.add_child(execute_btn)
	
	execute_btn.pressed.connect(func():
		m.rank = selection["rank"]
		GameManager.board_changed.emit()
		_active_editor_overlay = null
		backdrop.queue_free()
	)
	
	# 初始化高亮渲染
	update_opt_visuals.call()

func _style_action_button(btn: Button) -> void:
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.8))
	
	var style := StyleBoxTexture.new()
	style.texture = preload("res://辛迪加素材/界面UI/按钮.png")
	style.texture_margin_left = 6
	style.texture_margin_right = 6
	style.texture_margin_top = 6
	style.texture_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", style)
	
	var hover := style.duplicate()
	hover.modulate_color = Color(1.2, 1.2, 1.2)
	btn.add_theme_stylebox_override("hover", hover)
	
	var pressed := style.duplicate()
	pressed.modulate_color = Color(0.8, 0.8, 0.8)
	btn.add_theme_stylebox_override("pressed", pressed)

func _process(_delta: float) -> void:
	if is_instance_valid(_active_editor_overlay):
		var panel = _active_editor_overlay.get_node_or_null("Panel")
		if panel:
			var mpos = get_global_mouse_position()
			# 使用与 CardActionOverlay 一致的无边框透明黑色面板包围判定
			if not panel.get_global_rect().has_point(mpos):
				_active_editor_overlay.queue_free()
				_active_editor_overlay = null

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

func _on_auto_fill_pressed():
	var preset = _presets_dict["presets"].get(_active_preset_name, {})
	_auto_fill_placements(preset)
	GameManager.board_changed.emit()
	_rebuild_step2_dock()

func _on_recall_all_pressed():
	for mname in GameManager.MEMBER_DEFS:
		var m = GameManager.members.get(mname)
		if m:
			m.is_on_board = false
			m.division = GameManager.Division.NONE
			m.is_leader = false
			m.rank = 0
	_active_placement_member = ""
	GameManager.board_changed.emit()
	_rebuild_step2_dock()

func _on_close_pressed():
	_connect_slot_inputs(false)
	
	# 退出沙盒模式，重置游戏数据为正常随机模式
	GameManager.is_sandbox_mode = false
	GameManager.initialize_game()
	GameManager.delete_save_file()
	
	closed.emit()
	queue_free()

# ===== 获取某个成员在步骤2底部坞中的全局屏幕坐标 =====
func get_member_dock_screen_position(mname: String) -> Vector2:
	if _current_step != 2 or not is_instance_valid(_step2_hbox):
		return Vector2.ZERO
		
	var idx = _selected_members.find(mname)
	if idx != -1 and idx < _step2_hbox.get_child_count():
		var child = _step2_hbox.get_child(idx) as Control
		if is_instance_valid(child):
			# 获取该卡牌中心的全局屏幕坐标
			var size_half = child.size * 0.5
			return child.global_position + size_half
			
	return Vector2.ZERO

func _get_board_node() -> SyndicateBoard:
	var nodes = get_tree().get_nodes_in_group("board")
	for node in nodes:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			return node as SyndicateBoard
	return null

# ===== 预设配置系统核心方法 =====
const PRESETS_FILE_PATH = "user://sandbox_presets.json"

func _init_presets_system():
	# 1. 尝试读取本地预设文件
	if FileAccess.file_exists(PRESETS_FILE_PATH):
		var file = FileAccess.open(PRESETS_FILE_PATH, FileAccess.READ)
		var text = file.get_as_text()
		var json = JSON.new()
		if json.parse(text) == OK:
			if json.data is Dictionary:
				_presets_dict = json.data
	
	# 2. 如果文件不存在或解析失败，初始化出厂默认模板
	if _presets_dict.is_empty() or not _presets_dict.has("presets"):
		_presets_dict = {
			"active_preset": "2-5-5-2 经典特定布局",
			"presets": {
				"2-5-5-2 经典特定布局": {
					"benched": [],
					"divisions": {
						"transport": {
							"leader": "格拉维奇",
							"subordinates": ["瓦里西"]
						},
						"intervention": {
							"leader": "哈库",
							"subordinates": ["里奥"]
						},
						"fortification": {
							"leader": "",
							"subordinates": []
						},
						"research": {
							"leader": "",
							"subordinates": []
						}
					},
					"relationships": []
				}
			}
		}
		_save_presets_to_file()
		
	# 3. 取得当前活跃的预设名称
	_active_preset_name = _presets_dict.get("active_preset", "")
	var keys = _presets_dict["presets"].keys()
	if _active_preset_name == "" or not _presets_dict["presets"].has(_active_preset_name):
		if not keys.is_empty():
			_active_preset_name = keys[0]
		else:
			_active_preset_name = ""
		_presets_dict["active_preset"] = _active_preset_name

func _save_presets_to_file():
	var file = FileAccess.open(PRESETS_FILE_PATH, FileAccess.WRITE)
	if file:
		_presets_dict["active_preset"] = _active_preset_name
		file.store_string(JSON.stringify(_presets_dict, "\t"))

func _refresh_preset_selector():
	if not is_instance_valid(_preset_selector):
		return
	_preset_selector.clear()
	var keys = _presets_dict["presets"].keys()
	if keys.is_empty():
		_preset_selector.add_item("无预设")
		_preset_selector.select(0)
		return
		
	for i in range(keys.size()):
		_preset_selector.add_item(keys[i])
		if keys[i] == _active_preset_name:
			_preset_selector.select(i)

func _on_preset_selected(idx: int):
	var keys = _presets_dict["presets"].keys()
	if keys.is_empty():
		return
	var key = _preset_selector.get_item_text(idx)
	_active_preset_name = key
	_presets_dict["active_preset"] = key
	_save_presets_to_file()
	if _current_step > 1:
		_load_preset(_active_preset_name)

func _on_save_preset_pressed():
	if _active_preset_name != "":
		_save_current_layout_to_preset(_active_preset_name)

func _show_presets_management_popup():
	# 1. 创建黑色半透明背景遮罩
	var backdrop := Control.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	
	var color_rect := ColorRect.new()
	color_rect.color = Color(0, 0, 0, 0.4)
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(color_rect)
	
	# 2. 居中的 PanelContainer 控制面板
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.98)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.7, 0.55, 0.2, 0.8) # 金色边框
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 15
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	panel.add_theme_stylebox_override("panel", style)
	
	var panel_size := Vector2(460, 290) if _current_step == 1 else Vector2(460, 230)
	panel.size = panel_size
	var vp := get_viewport_rect().size
	panel.position = Vector2((vp.x - panel_size.x) * 0.5, (vp.y - panel_size.y) * 0.5)
	backdrop.add_child(panel)
	
	# 3. 内部纵向布局
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)
	
	# --- 头部 ---
	var header_hbox := HBoxContainer.new()
	vbox.add_child(header_hbox)
	
	var title_lbl := Label.new()
	title_lbl.text = "📂 预设方案管理"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	header_hbox.add_child(title_lbl)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)
	
	var close_btn := Button.new()
	close_btn.text = " 关闭 "
	close_btn.pressed.connect(func(): backdrop.queue_free())
	header_hbox.add_child(close_btn)
	
	# 分割线
	var hsep := HSeparator.new()
	vbox.add_child(hsep)
	
	# --- 下拉框切换区 ---
	var select_hbox := HBoxContainer.new()
	select_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	select_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(select_hbox)
	
	var select_lbl := Label.new()
	select_lbl.text = "当前选定预设："
	select_lbl.add_theme_font_size_override("font_size", 14)
	select_hbox.add_child(select_lbl)
	
	_preset_selector = OptionButton.new()
	_preset_selector.custom_minimum_size = Vector2(240, 0)
	select_hbox.add_child(_preset_selector)
	
	_refresh_preset_selector()
	
	# --- 操作按钮区 ---
	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 15)
	vbox.add_child(btn_hbox)
	
	var save_btn := Button.new()
	save_btn.text = "💾 保存当前"
	save_btn.visible = (_current_step == 4)
	btn_hbox.add_child(save_btn)
	
	var new_btn := Button.new()
	new_btn.text = "➕ 另存为"
	new_btn.visible = (_current_step == 4)
	btn_hbox.add_child(new_btn)
	
	var delete_btn := Button.new()
	delete_btn.text = "🗑 删除方案"
	btn_hbox.add_child(delete_btn)
	
	var quick_btn: Button = null
	if _current_step == 1:
		var quick_hbox := HBoxContainer.new()
		quick_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(quick_hbox)
		
		quick_btn = Button.new()
		quick_btn.text = "⚡ 快捷布阵 (直达连线)"
		quick_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		quick_btn.pressed.connect(func():
			_load_preset(_active_preset_name)
			_current_step = 3
			_update_step_ui()
			backdrop.queue_free()
		)
		quick_hbox.add_child(quick_btn)
		
	# 定义用于更新按钮禁用状态的闭包
	var update_popup_buttons = func():
		var keys = _presets_dict["presets"].keys()
		var has_presets = not keys.is_empty()
		
		_preset_selector.disabled = not has_presets
		save_btn.disabled = not has_presets
		delete_btn.disabled = not has_presets
		if is_instance_valid(quick_btn):
			quick_btn.disabled = not has_presets
			
	# 执行一次状态更新
	update_popup_buttons.call()
	
	# 绑定事件
	_preset_selector.item_selected.connect(func(idx: int):
		_on_preset_selected(idx)
		update_popup_buttons.call()
	)
	
	save_btn.pressed.connect(func():
		_on_save_preset_pressed()
		var tip := Label.new()
		tip.text = "✓ 已成功覆盖保存当前预设！"
		tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tip.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3))
		vbox.add_child(tip)
		await get_tree().create_timer(1.2).timeout
		if is_instance_valid(tip): tip.queue_free()
	)
	
	new_btn.pressed.connect(func():
		_show_new_preset_naming_popup(backdrop, update_popup_buttons)
	)
	
	delete_btn.pressed.connect(func():
		if _presets_dict["presets"].has(_active_preset_name):
			_presets_dict["presets"].erase(_active_preset_name)
			
			var keys = _presets_dict["presets"].keys()
			if keys.is_empty():
				_active_preset_name = ""
				_presets_dict["active_preset"] = ""
				# 彻底清空棋盘状态
				for mname in GameManager.MEMBER_DEFS:
					var m = GameManager.members.get(mname)
					if m:
						m.is_on_board = false
						m.division = GameManager.Division.NONE
						m.is_leader = false
						m.rank = 0
				GameManager.relationships.clear()
				GameManager.board_changed.emit()
				_rebuild_step1_grid()
				_layout_benched_cards()
				_rebuild_step2_dock()
			else:
				_active_preset_name = keys[0]
				_presets_dict["active_preset"] = _active_preset_name
				_load_preset(_active_preset_name)
				
			_save_presets_to_file()
			_refresh_preset_selector()
			update_popup_buttons.call()
	)

func _show_new_preset_naming_popup(parent_node: Node, on_confirmed_callback: Callable):
	var sub_backdrop := Control.new()
	sub_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	sub_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	parent_node.add_child(sub_backdrop)
	
	var color_rect := ColorRect.new()
	color_rect.color = Color(0, 0, 0, 0.35)
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	sub_backdrop.add_child(color_rect)
	
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.16, 0.99)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.7, 0.55, 0.2, 0.8)
	style.shadow_color = Color(0, 0, 0, 0.8)
	style.shadow_size = 10
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	panel.add_theme_stylebox_override("panel", style)
	
	var panel_size := Vector2(380, 180)
	panel.size = panel_size
	var vp := get_viewport_rect().size
	panel.position = Vector2((vp.x - panel_size.x) * 0.5, (vp.y - panel_size.y) * 0.5)
	sub_backdrop.add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)
	
	var lbl := Label.new()
	lbl.text = "请输入新预设的名称："
	lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(lbl)
	
	var line_edit := LineEdit.new()
	var default_name = "自定义布局 " + str(_presets_dict["presets"].size() + 1)
	line_edit.placeholder_text = default_name
	line_edit.text = default_name
	line_edit.custom_minimum_size = Vector2(250, 0)
	vbox.add_child(line_edit)
	
	var save_preset_func = func():
		var name_text = line_edit.text.strip_edges()
		if name_text == "":
			name_text = default_name
		_save_current_layout_to_preset(name_text)
		_active_preset_name = name_text
		_save_presets_to_file()
		_refresh_preset_selector()
		if on_confirmed_callback.is_valid():
			on_confirmed_callback.call()
		sub_backdrop.queue_free()
		
	line_edit.text_submitted.connect(func(_new_text):
		save_preset_func.call()
	)
	
	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_hbox)
	
	var cancel_btn := Button.new()
	cancel_btn.text = " 取消 "
	cancel_btn.pressed.connect(func(): sub_backdrop.queue_free())
	btn_hbox.add_child(cancel_btn)
	
	var ok_btn := Button.new()
	ok_btn.text = " 确定 "
	ok_btn.pressed.connect(func():
		save_preset_func.call()
	)
	btn_hbox.add_child(ok_btn)
	
	line_edit.grab_focus()

func _save_current_layout_to_preset(preset_name: String):
	# 收集当前摆场数据
	var benched_list = []
	for mname in _benched_members:
		benched_list.append(mname)
		
	var div_data = {
		"transport": { "leader": "", "subordinates": [] },
		"fortification": { "leader": "", "subordinates": [] },
		"research": { "leader": "", "subordinates": [] },
		"intervention": { "leader": "", "subordinates": [] }
	}
	
	for div_name in div_data.keys():
		var div_enum = GameManager.Division.NONE
		match div_name:
			"transport": div_enum = GameManager.Division.TRANSPORT
			"fortification": div_enum = GameManager.Division.FORTIFICATION
			"research": div_enum = GameManager.Division.RESEARCH
			"intervention": div_enum = GameManager.Division.INTERVENTION
			
		var leader = GameManager.get_division_leader(div_enum)
		if leader and leader.is_on_board:
			div_data[div_name]["leader"] = leader.member_name
			
		var subs = GameManager.get_division_members(div_enum)
		for sub in subs:
			if sub.is_on_board:
				div_data[div_name]["subordinates"].append(sub.member_name)
				
	var rel_list = []
	for rel in GameManager.relationships:
		rel_list.append({
			"a": rel.member_a,
			"b": rel.member_b,
			"type": rel.type
		})
		
	var states_data = {}
	for mname in _selected_members:
		var m = GameManager.members.get(mname)
		if m:
			states_data[mname] = {
				"rank": m.rank,
				"is_imprisoned": m.is_imprisoned,
				"prison_turns_left": m.prison_turns_left,
				"prison_intel_division": m.prison_intel_division
			}
		
	_presets_dict["presets"][preset_name] = {
		"benched": benched_list,
		"divisions": div_data,
		"relationships": rel_list,
		"member_states": states_data
	}
	
	_save_presets_to_file()
	print("【预设】成功将当前布局保存至预设：" + preset_name)

func _load_preset(preset_name: String):
	if not _presets_dict["presets"].has(preset_name):
		return
	var preset = _presets_dict["presets"][preset_name]
	
	# 重置所有成员的状态（包括死刑/监禁/情报/历史记录）避免从正常模式继承脏数据
	for mname in GameManager.MEMBER_DEFS:
		var m = GameManager.members.get(mname)
		if m:
			m.is_imprisoned = false
			m.equipment_count = 0
			m.cached_betray_effect = -1
			m.cached_bargain_effect = -1
			m.cached_bargain_target = ""
			
	GameManager.turn_count = 0
	GameManager.current_encounter.clear()
	GameManager.encounter_queue.clear()
	GameManager.prison_queue.clear()
	GameManager.history_stack.clear()
	GameManager.safehouse_100_turns.clear()
	for div in GameManager.ALL_DIVISIONS:
		GameManager.intelligence[div] = 0.0
		GameManager.intelligence_changed.emit(div, 0.0)
	
	# 1. 还原替补席人员名单
	_benched_members.clear()
	var benched_preset = preset.get("benched", [])
	if benched_preset.size() == 3:
		for mname in benched_preset:
			_benched_members.append(mname)
	else:
		var reserved = []
		var div_data = preset.get("divisions", {})
		for div_key in div_data.keys():
			var p = div_data[div_key]
			var l = p.get("leader", "")
			if l != "": reserved.append(l)
			for s in p.get("subordinates", []):
				if s != "": reserved.append(s)
		
		# 运输部/调停部默认核心特定人物保护
		for core in ["格拉维奇", "瓦里西", "哈库", "里奥"]:
			if core not in reserved:
				reserved.append(core)
				
		var candidates = []
		for mname in GameManager.MEMBER_DEFS:
			if mname not in reserved:
				candidates.append(mname)
		candidates.shuffle()
		
		for i in range(min(3, candidates.size())):
			_benched_members.append(candidates[i])
			
	# 2. 根据替补名单计算出上场的14名成员
	_selected_members.clear()
	for mname in GameManager.MEMBER_DEFS:
		if mname not in _benched_members:
			_selected_members.append(mname)
			
	# 3. 初始化并自动分配卡牌槽位
	_auto_fill_placements(preset)
	
	# 加载各个成员的具体星级和监禁状态（如果存在）
	var states_data = preset.get("member_states", {})
	for mname in _selected_members:
		var m = GameManager.members.get(mname)
		if m and states_data.has(mname):
			var s = states_data[mname]
			m.rank = int(s.get("rank", 1))
			m.is_imprisoned = bool(s.get("is_imprisoned", false))
			m.prison_turns_left = int(s.get("prison_turns_left", 0))
			m.prison_intel_division = int(s.get("prison_intel_division", 0))
			if m.is_imprisoned:
				if mname not in GameManager.prison_queue:
					GameManager.prison_queue.append(mname)

	# 4. 加载关系线连线
	GameManager.relationships.clear()
	for rel_data in preset.get("relationships", []):
		var a = rel_data.get("a", "")
		var b = rel_data.get("b", "")
		var type = int(rel_data.get("type", 0))
		GameManager._set_relationship_type(a, b, type)
		
	# 5. 更新游戏数据为沙盒模式
	GameManager.is_sandbox_mode = true
	GameManager.bench_pool.clear()
	for mname in _benched_members:
		GameManager.bench_pool.append(mname)
		
	# 6. 同步更新场景并重新渲染
	GameManager.board_changed.emit()
	GameManager.save_game_to_disk()
	
	# 重建UI状态
	_rebuild_step1_grid()
	_layout_benched_cards()
	_rebuild_step2_dock()

func _auto_fill_placements(preset: Dictionary):
	# 重置所有成员的在场及卡位状态
	for mname in GameManager.MEMBER_DEFS:
		var m = GameManager.members.get(mname)
		if m:
			m.is_on_board = false
			m.division = GameManager.Division.NONE
			m.is_leader = false
			m.rank = 0
			
	# 设置上阵状态
	for mname in _selected_members:
		var m = GameManager.members.get(mname)
		if m:
			m.is_on_board = true
			m.is_revealed = true
			
	# 1. 优先按预设加载特定槽位 (如果预设成员存在于上阵名单中)
	var div_data = preset.get("divisions", {})
	var placed_members = []
	
	for div_name in div_data.keys():
		var div_enum = GameManager.Division.NONE
		match div_name:
			"transport": div_enum = GameManager.Division.TRANSPORT
			"fortification": div_enum = GameManager.Division.FORTIFICATION
			"research": div_enum = GameManager.Division.RESEARCH
			"intervention": div_enum = GameManager.Division.INTERVENTION
			
		var p = div_data[div_name]
		
		# 摆放首领
		var l = p.get("leader", "")
		if l != "" and l in _selected_members:
			var m = GameManager.members.get(l)
			m.division = div_enum
			m.is_leader = true
			m.rank = 1
			placed_members.append(l)
			
		# 摆放手下
		for s in p.get("subordinates", []):
			if s != "" and s in _selected_members and s not in placed_members:
				var m = GameManager.members.get(s)
				m.division = div_enum
				m.is_leader = false
				m.rank = 1
				placed_members.append(s)
				
	# 2. 搜集尚未被分配具体位置的上阵成员池
	var pool = []
	for mname in _selected_members:
		if mname not in placed_members:
			pool.append(mname)
	pool.shuffle()
	
	# 3. 补位空缺的插槽，严格满足 2-5-5-2 人数限制
	var target_counts = {
		GameManager.Division.TRANSPORT: 2,
		GameManager.Division.FORTIFICATION: 5,
		GameManager.Division.RESEARCH: 5,
		GameManager.Division.INTERVENTION: 2
	}
	
	for div_enum in target_counts.keys():
		var target_num = target_counts[div_enum]
		
		# 计算当前已分派的实际人数
		var current_members = []
		var leader = GameManager.get_division_leader(div_enum)
		if leader and leader.is_on_board:
			current_members.append(leader)
		for sub in GameManager.get_division_members(div_enum):
			if sub.is_on_board:
				current_members.append(sub)
				
		var needed = target_num - current_members.size()
		for _i in range(needed):
			if pool.is_empty():
				break
			var next_mname = pool.pop_back()
			var m = GameManager.members.get(next_mname)
			
			var has_leader = false
			var test_leader = GameManager.get_division_leader(div_enum)
			if test_leader and test_leader.is_on_board:
				has_leader = true
				
			m.division = div_enum
			if not has_leader:
				m.is_leader = true
				m.rank = 1
			else:
				m.is_leader = false
				m.rank = 1

func _sync_benched_card_nodes():
	# 确保 _benched_card_nodes 中有且仅有 _benched_members 中的成员卡牌节点
	# 1. 移除多余的节点
	var keys_to_remove = []
	for mname in _benched_card_nodes.keys():
		if mname not in _benched_members:
			keys_to_remove.append(mname)
			
	for mname in keys_to_remove:
		var node = _benched_card_nodes[mname]
		if is_instance_valid(node):
			node.queue_free()
		_benched_card_nodes.erase(mname)
			
	# 2. 创建缺少的节点
	for mname in _benched_members:
		if not _benched_card_nodes.has(mname):
			var card_node = _create_card_node(mname, true)
			add_child(card_node)
			
			# 如果该成员在 _step1_grid 中有对应的 GridContainer，我们将位置先设在其上
			var grid_idx = GameManager.MEMBER_DEFS.find(mname)
			if grid_idx != -1 and is_instance_valid(_step1_grid) and grid_idx < _step1_grid.get_child_count():
				var grid_container = _step1_grid.get_child(grid_idx) as Control
				if is_instance_valid(grid_container):
					card_node.position = grid_container.global_position
			else:
				card_node.position = Vector2(958.0, 862.0)
				
			card_node.visible = (_current_step == 1)
			_benched_card_nodes[mname] = card_node
			
	# 3. 重新对齐布局
	_layout_benched_cards()
