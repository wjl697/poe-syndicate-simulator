class_name TutorialModePanel
extends Control

signal closed()

# ===== 界面节点与变量 =====
var _backdrop: Control
var _panel: PanelContainer
var _tab_hbox: HBoxContainer
var _canvas: Control
var _explanation_label: Label
var _action_btn: Button
var _reset_unit_btn: Button

# 当前选中的演示单元索引 (0 ~ 3)
var _current_unit_idx: int = 0

# 动态创建的演示卡牌字典 (id -> PanelContainer)
var _demo_cards: Dictionary = {}
# 动态关系的连线 Array[Dictionary]: {a_id: String, b_id: String, color: Color}
var _demo_lines: Array = []

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_load_unit(_current_unit_idx)

func _build_ui():
	# 1. 半透明黑色遮罩
	var color_rect := ColorRect.new()
	color_rect.color = Color(0.04, 0.05, 0.08, 0.92)
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(color_rect)
	
	# 2. 中央主容器 Panel
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.08, 0.09, 0.13, 0.98)
	p_style.border_width_left = 2
	p_style.border_width_top = 2
	p_style.border_width_right = 2
	p_style.border_width_bottom = 2
	p_style.border_color = Color(0.8, 0.65, 0.25, 0.8) # 华丽金色边框
	p_style.content_margin_left = 24
	p_style.content_margin_right = 24
	p_style.content_margin_top = 20
	p_style.content_margin_bottom = 20
	_panel.add_theme_stylebox_override("panel", p_style)
	add_child(_panel)
	
	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 16)
	_panel.add_child(main_vbox)
	
	# --- 顶栏 Header ---
	var header_hbox := HBoxContainer.new()
	main_vbox.add_child(header_hbox)
	
	var title_vbox := VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_vbox)
	
	var title_lbl := Label.new()
	title_lbl.text = "🎓 辛迪加核心机制 — 抽象教学演示 (V1)"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	title_vbox.add_child(title_lbl)
	
	var subtitle_lbl := Label.new()
	subtitle_lbl.text = "脱离具体人物属性，纯粹展示底层规则（提拔、篡位、暗卡补位、结盟）的抽象演变过程"
	subtitle_lbl.add_theme_font_size_override("font_size", 13)
	subtitle_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	title_vbox.add_child(subtitle_lbl)
	
	var close_btn := Button.new()
	close_btn.text = "✕ 退出教学"
	close_btn.custom_minimum_size = Vector2(120, 36)
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.45, 0.15, 0.15, 0.9)
	close_style.corner_radius_top_left = 4
	close_style.corner_radius_top_right = 4
	close_style.corner_radius_bottom_left = 4
	close_style.corner_radius_bottom_right = 4
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.pressed.connect(func():
		closed.emit()
		queue_free()
	)
	header_hbox.add_child(close_btn)
	
	# --- 演示单元切换 Tabs ---
	_tab_hbox = HBoxContainer.new()
	_tab_hbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(_tab_hbox)
	
	var unit_names = [
		"👑 1. 首领下台与提拔",
		"⚔️ 2. 篡位与位置互换",
		"❓ 3. 除名与暗卡补位",
		"🤝 4. 招募自由人结盟"
	]
	
	for i in range(unit_names.size()):
		var tab_btn := Button.new()
		tab_btn.text = unit_names[i]
		tab_btn.custom_minimum_size = Vector2(170, 38)
		var idx_copy := i
		tab_btn.pressed.connect(func(): _load_unit(idx_copy))
		_tab_hbox.add_child(tab_btn)
		
	# --- 中央画布 Area (绘制抽象卡牌与关系连线) ---
	var canvas_panel := PanelContainer.new()
	canvas_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_panel.custom_minimum_size = Vector2(0, 420)
	var c_style := StyleBoxFlat.new()
	c_style.bg_color = Color(0.05, 0.06, 0.09, 0.9)
	c_style.border_width_left = 1
	c_style.border_width_top = 1
	c_style.border_width_right = 1
	c_style.border_width_bottom = 1
	c_style.border_color = Color(0.2, 0.25, 0.35, 0.6)
	c_style.corner_radius_top_left = 6
	c_style.corner_radius_top_right = 6
	c_style.corner_radius_bottom_left = 6
	c_style.corner_radius_bottom_right = 6
	canvas_panel.add_theme_stylebox_override("panel", c_style)
	main_vbox.add_child(canvas_panel)
	
	# 自定义 Canvas Control 专门处理连线绘制
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_on_canvas_draw)
	canvas_panel.add_child(_canvas)
	
	# --- 底栏 说明与操作按钮 ---
	var bottom_vbox := VBoxContainer.new()
	bottom_vbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(bottom_vbox)
	
	_explanation_label = Label.new()
	_explanation_label.text = "说明信息"
	_explanation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_explanation_label.add_theme_font_size_override("font_size", 15)
	_explanation_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	bottom_vbox.add_child(_explanation_label)
	
	var action_hbox := HBoxContainer.new()
	action_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	action_hbox.add_theme_constant_override("separation", 20)
	bottom_vbox.add_child(action_hbox)
	
	_action_btn = Button.new()
	_action_btn.text = "▶ 演示动作"
	_action_btn.custom_minimum_size = Vector2(220, 44)
	var a_style := StyleBoxFlat.new()
	a_style.bg_color = Color(0.2, 0.45, 0.25, 0.95)
	a_style.corner_radius_top_left = 4
	a_style.corner_radius_top_right = 4
	a_style.corner_radius_bottom_left = 4
	a_style.corner_radius_bottom_right = 4
	_action_btn.add_theme_stylebox_override("normal", a_style)
	_action_btn.pressed.connect(_on_action_btn_pressed)
	action_hbox.add_child(_action_btn)
	
	_reset_unit_btn = Button.new()
	_reset_unit_btn.text = "↺ 重置本示例"
	_reset_unit_btn.custom_minimum_size = Vector2(140, 44)
	var r_style := StyleBoxFlat.new()
	r_style.bg_color = Color(0.25, 0.25, 0.3, 0.9)
	r_style.corner_radius_top_left = 4
	r_style.corner_radius_top_right = 4
	r_style.corner_radius_bottom_left = 4
	r_style.corner_radius_bottom_right = 4
	_reset_unit_btn.add_theme_stylebox_override("normal", r_style)
	_reset_unit_btn.pressed.connect(func(): _load_unit(_current_unit_idx))
	action_hbox.add_child(_reset_unit_btn)

# ===== Tab 按钮高亮更新 =====
func _update_tab_styles():
	for i in range(_tab_hbox.get_child_count()):
		var btn = _tab_hbox.get_child(i) as Button
		var style := StyleBoxFlat.new()
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		if i == _current_unit_idx:
			style.bg_color = Color(0.7, 0.55, 0.15, 0.95)
			btn.add_theme_color_override("font_color", Color(1, 1, 1))
		else:
			style.bg_color = Color(0.15, 0.18, 0.25, 0.8)
			btn.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		btn.add_theme_stylebox_override("normal", style)

# ===== 抽象卡牌节点创建工厂 =====
# card_type: "LEADER" | "SUBORDINATE" | "UNREVEALED" | "FREE"
func _create_abstract_card(card_id: String, card_type: String, rank: int, title: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = card_id
	card.custom_minimum_size = Vector2(150, 180)
	
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_size = 8
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	
	match card_type:
		"LEADER":
			style.bg_color = Color(0.2, 0.16, 0.08, 0.95)
			style.border_width_left = 3
			style.border_width_top = 3
			style.border_width_right = 3
			style.border_width_bottom = 3
			style.border_color = Color(0.95, 0.75, 0.2, 1.0) # 金色首领框
		"SUBORDINATE":
			style.bg_color = Color(0.1, 0.15, 0.22, 0.95)
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
			style.border_color = Color(0.3, 0.55, 0.85, 0.9) # 蓝色部下框
		"UNREVEALED":
			style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
			style.border_color = Color(0.4, 0.4, 0.45, 0.8) # 深灰暗卡框
		"FREE":
			style.bg_color = Color(0.14, 0.14, 0.16, 0.95)
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
			style.border_color = Color(0.5, 0.5, 0.55, 0.8) # 游民自由人框
			
	card.add_theme_stylebox_override("panel", style)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)
	
	# 头部图标/标识
	var icon_lbl := Label.new()
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 24)
	match card_type:
		"LEADER": icon_lbl.text = "👑"
		"SUBORDINATE": icon_lbl.text = "⚔️"
		"UNREVEALED": icon_lbl.text = "❓"
		"FREE": icon_lbl.text = "🏕️"
	vbox.add_child(icon_lbl)
	
	# 标题
	var title_lbl := Label.new()
	title_lbl.name = "TitleLabel"
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	vbox.add_child(title_lbl)
	
	# 星级显示
	var rank_lbl := Label.new()
	rank_lbl.name = "RankLabel"
	rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_lbl.add_theme_font_size_override("font_size", 13)
	rank_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_update_rank_label_text(rank_lbl, rank, card_type)
	vbox.add_child(rank_lbl)
	
	return card

func _update_rank_label_text(lbl: Label, rank: int, card_type: String):
	if card_type == "UNREVEALED":
		lbl.text = "【未翻牌暗卡】"
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	elif rank <= 0:
		lbl.text = "0 星 (游民)"
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	else:
		var stars := ""
		for i in range(rank): stars += "★"
		lbl.text = stars + " (" + str(rank) + "星)"
		lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))

# ===== 加载演示单元 =====
func _load_unit(unit_idx: int):
	_current_unit_idx = unit_idx
	_update_tab_styles()
	
	# 清理旧卡牌节点
	for cid in _demo_cards:
		if is_instance_valid(_demo_cards[cid]):
			_demo_cards[cid].queue_free()
	_demo_cards.clear()
	_demo_lines.clear()
	_canvas.queue_redraw()
	
	match unit_idx:
		0: _setup_unit_0_leader_stepdown()
		1: _setup_unit_1_usurpation()
		2: _setup_unit_2_removal_unrevealed_fill()
		3: _setup_unit_3_free_agent_trust()

# ===== 单元 0：首领下台与提拔 =====
func _setup_unit_0_leader_stepdown():
	_explanation_label.text = "法则 1：当首领因为审讯或降级下台时，部门内星级最高的部下将自动晋升为新首领！"
	_action_btn.text = "▶ 审讯首领 (演示下台与提拔)"
	_action_btn.disabled = false
	
	# 绘制 3 张卡：3星首领, 2星部下A, 1星部下B
	var c_leader = _create_abstract_card("leader", "LEADER", 3, "运输部首领")
	c_leader.position = Vector2(300, 80)
	_canvas.add_child(c_leader)
	_demo_cards["leader"] = c_leader
	
	var c_sub1 = _create_abstract_card("sub1", "SUBORDINATE", 2, "运输部部下 A")
	c_sub1.position = Vector2(180, 240)
	_canvas.add_child(c_sub1)
	_demo_cards["sub1"] = c_sub1
	
	var c_sub2 = _create_abstract_card("sub2", "SUBORDINATE", 1, "运输部部下 B")
	c_sub2.position = Vector2(420, 240)
	_canvas.add_child(c_sub2)
	_demo_cards["sub2"] = c_sub2

func _run_unit_0_anim():
	_action_btn.disabled = true
	var c_leader = _demo_cards["leader"] as PanelContainer
	var c_sub1 = _demo_cards["sub1"] as PanelContainer
	
	var tween := create_tween()
	# 1. 3星首领离开部门（向左上方滑出）
	tween.tween_property(c_leader, "position", Vector2(40, 40), 0.5)
	tween.tween_property(c_leader, "modulate:a", 0.3, 0.3)
	
	# 2. 2星部下 A 向上滑动占据首领位置，并升级为首领样式
	tween.tween_property(c_sub1, "position", Vector2(300, 80), 0.6).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(func():
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.16, 0.08, 0.95)
		style.border_width_left = 3
		style.border_width_top = 3
		style.border_width_right = 3
		style.border_width_bottom = 3
		style.border_color = Color(0.95, 0.75, 0.2, 1.0)
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		c_sub1.add_theme_stylebox_override("panel", style)
		
		var t_lbl = c_sub1.find_child("TitleLabel", true, false) as Label
		if t_lbl: t_lbl.text = "运输部新首领"
		_explanation_label.text = "✨ 演示完成：原首领下台入狱，2星部下 A 成功自动晋升为运输部新首领！"
	)

# ===== 单元 1：篡位与位置互换 =====
func _setup_unit_1_usurpation():
	_explanation_label.text = "法则 2：部下触发【篡位】时，将与首领调换身份与位置，并产生红线（敌对关系）！"
	_action_btn.text = "▶ 执行篡位 (演示调换与建立宿敌)"
	_action_btn.disabled = false
	
	var c_leader = _create_abstract_card("leader", "LEADER", 2, "防卫部首领")
	c_leader.position = Vector2(240, 140)
	_canvas.add_child(c_leader)
	_demo_cards["leader"] = c_leader
	
	var c_sub = _create_abstract_card("sub", "SUBORDINATE", 3, "防卫部部下")
	c_sub.position = Vector2(480, 140)
	_canvas.add_child(c_sub)
	_demo_cards["sub"] = c_sub

func _run_unit_1_anim():
	_action_btn.disabled = true
	var c_leader = _demo_cards["leader"] as PanelContainer
	var c_sub = _demo_cards["sub"] as PanelContainer
	
	var pos_l: Vector2 = c_leader.position
	var pos_s: Vector2 = c_sub.position
	
	var tween := create_tween().set_parallel(true)
	# 交叉滑动互换位置
	tween.tween_property(c_leader, "position", pos_s, 0.6).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(c_sub, "position", pos_l, 0.6).set_trans(Tween.TRANS_CUBIC)
	
	tween.chain().tween_callback(func():
		# 样式互换
		var leader_style := StyleBoxFlat.new()
		leader_style.bg_color = Color(0.2, 0.16, 0.08, 0.95)
		leader_style.border_width_left = 3
		leader_style.border_width_top = 3
		leader_style.border_width_right = 3
		leader_style.border_width_bottom = 3
		leader_style.border_color = Color(0.95, 0.75, 0.2, 1.0)
		leader_style.corner_radius_top_left = 8
		leader_style.corner_radius_top_right = 8
		leader_style.corner_radius_bottom_left = 8
		leader_style.corner_radius_bottom_right = 8
		c_sub.add_theme_stylebox_override("panel", leader_style)
		
		var sub_style := StyleBoxFlat.new()
		sub_style.bg_color = Color(0.1, 0.15, 0.22, 0.95)
		sub_style.border_width_left = 2
		sub_style.border_width_top = 2
		sub_style.border_width_right = 2
		sub_style.border_width_bottom = 2
		sub_style.border_color = Color(0.3, 0.55, 0.85, 0.9)
		sub_style.corner_radius_top_left = 8
		sub_style.corner_radius_top_right = 8
		sub_style.corner_radius_bottom_left = 8
		sub_style.corner_radius_bottom_right = 8
		c_leader.add_theme_stylebox_override("panel", sub_style)
		
		# 建立红线 (敌对)
		_demo_lines.append({"a_id": "leader", "b_id": "sub", "color": Color(0.95, 0.25, 0.25, 0.9)})
		_canvas.queue_redraw()
		
		_explanation_label.text = "✨ 演示完成：部下篡位成为新首领，原首领降为部下，两者建立敌对（红线）关系！"
	)

# ===== 单元 2：除名与暗卡补位 =====
func _setup_unit_2_removal_unrevealed_fill():
	_explanation_label.text = "法则 3：成员被【逐出组织】除名后，替补池中的新成员会作为【0星未翻牌暗卡自由人】补位上场！"
	_action_btn.text = "▶ 逐出组织 (演示除名与暗卡补位)"
	_action_btn.disabled = false
	
	var c_sub = _create_abstract_card("sub", "SUBORDINATE", 2, "科研部部下")
	c_sub.position = Vector2(240, 140)
	_canvas.add_child(c_sub)
	_demo_cards["sub"] = c_sub
	
	var c_bench = _create_abstract_card("bench", "UNREVEALED", 0, "替补池新成员")
	c_bench.position = Vector2(560, 140)
	_canvas.add_child(c_bench)
	_demo_cards["bench"] = c_bench

func _run_unit_2_anim():
	_action_btn.disabled = true
	var c_sub = _demo_cards["sub"] as PanelContainer
	var c_bench = _demo_cards["bench"] as PanelContainer
	
	var tween := create_tween()
	# 1. 2星部下被除名（向上淡出离场）
	tween.tween_property(c_sub, "position:y", c_sub.position.y - 80, 0.4)
	tween.parallel().tween_property(c_sub, "modulate:a", 0.0, 0.4)
	
	# 2. 替补池暗卡平滑补位到左侧自由人/场上坑位
	tween.tween_property(c_bench, "position", Vector2(240, 140), 0.6).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(func():
		var t_lbl = c_bench.find_child("TitleLabel", true, false) as Label
		if t_lbl: t_lbl.text = "新自由人 (未翻牌)"
		_explanation_label.text = "✨ 演示完成：原部下被除名离场，替补池新成员作为【0星未翻牌暗卡自由人】自动补位上场！"
	)

# ===== 单元 3：招募自由人结盟 =====
func _setup_unit_3_free_agent_trust():
	_explanation_label.text = "法则 4：当与【未翻牌自由人】达成【结盟】时，自由人会被拉拢进入该部门（设为1星），并建立信任绿线！"
	_action_btn.text = "▶ 达成结盟 (演示拉拢与建立信任)"
	_action_btn.disabled = false
	
	var c_sub = _create_abstract_card("sub", "SUBORDINATE", 1, "调停部部下")
	c_sub.position = Vector2(200, 140)
	_canvas.add_child(c_sub)
	_demo_cards["sub"] = c_sub
	
	var c_free = _create_abstract_card("free", "UNREVEALED", 0, "未翻牌自由人")
	c_free.position = Vector2(520, 140)
	_canvas.add_child(c_free)
	_demo_cards["free"] = c_free

func _run_unit_3_anim():
	_action_btn.disabled = true
	var c_sub = _demo_cards["sub"] as PanelContainer
	var c_free = _demo_cards["free"] as PanelContainer
	
	var tween := create_tween()
	# 未翻牌自由人向调停部靠拢，并升为 1星部下
	tween.tween_property(c_free, "position", Vector2(400, 140), 0.6).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(func():
		var t_lbl = c_free.find_child("TitleLabel", true, false) as Label
		if t_lbl: t_lbl.text = "调停部新部下"
		var r_lbl = c_free.find_child("RankLabel", true, false) as Label
		if r_lbl: _update_rank_label_text(r_lbl, 1, "SUBORDINATE")
		
		# 变更为部下蓝色框样式
		var sub_style := StyleBoxFlat.new()
		sub_style.bg_color = Color(0.1, 0.15, 0.22, 0.95)
		sub_style.border_width_left = 2
		sub_style.border_width_top = 2
		sub_style.border_width_right = 2
		sub_style.border_width_bottom = 2
		sub_style.border_color = Color(0.3, 0.55, 0.85, 0.9)
		sub_style.corner_radius_top_left = 8
		sub_style.corner_radius_top_right = 8
		sub_style.corner_radius_bottom_left = 8
		sub_style.corner_radius_bottom_right = 8
		c_free.add_theme_stylebox_override("panel", sub_style)
		
		# 建立绿线 (信任)
		_demo_lines.append({"a_id": "sub", "b_id": "free", "color": Color(0.25, 0.95, 0.4, 0.9)})
		_canvas.queue_redraw()
		
		_explanation_label.text = "✨ 演示完成：未翻牌自由人被拉拢进入调停部成为 1星部下，并与当事人建立信任（绿线）关系！"
	)

# ===== 动作按钮触发器 =====
func _on_action_btn_pressed():
	match _current_unit_idx:
		0: _run_unit_0_anim()
		1: _run_unit_1_anim()
		2: _run_unit_2_anim()
		3: _run_unit_3_anim()

# ===== 连线绘制回调 =====
func _on_canvas_draw():
	for line_data in _demo_lines:
		var a_id: String = line_data["a_id"]
		var b_id: String = line_data["b_id"]
		var color: Color = line_data["color"]
		
		if _demo_cards.has(a_id) and _demo_cards.has(b_id):
			var node_a = _demo_cards[a_id] as PanelContainer
			var node_b = _demo_cards[b_id] as PanelContainer
			if is_instance_valid(node_a) and is_instance_valid(node_b):
				var pos_a = node_a.position + node_a.size * 0.5
				var pos_b = node_b.position + node_b.size * 0.5
				_canvas.draw_line(pos_a, pos_b, color, 4.0, true)
