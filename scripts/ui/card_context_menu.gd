class_name CardContextMenu
extends Control

signal action_selected(action_type: String, target_member: String, extra_data: Variant)

var _target_member: String = ""
var _panel: PanelContainer

func get_target_member() -> String:
	return _target_member

func setup(member_name: String, global_pos: Vector2) -> void:
	_target_member = member_name
	add_to_group("card_context_menu")
	
	# 设置全屏透明背景遮罩，便于点击菜单外部自动关闭
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_backdrop_gui_input)
	
	_panel = PanelContainer.new()
	add_child(_panel)
	
	# 设置深色精致悬浮菜单样式
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.35, 0.45, 0.55, 0.7)
	sb.set_corner_radius_all(6)
	sb.shadow_size = 8
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.content_margin_left = 8
	sb.content_margin_top = 8
	sb.content_margin_right = 8
	sb.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", sb)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)
	
	# 顶部功能按钮：移除卡片
	_add_menu_btn(vbox, "🗑️ 移除卡片", Color(0.5, 0.2, 0.2), func():
		action_selected.emit("REMOVE", _target_member, null)
		queue_free()
	)

	# 新增按钮：指定特定成员 ▶
	var btn_spec := _add_menu_btn(vbox, "👤 指定特定成员 ▶", Color(0.2, 0.4, 0.5), func():
		_toggle_side_member_panel(global_pos)
	)
	btn_spec.mouse_entered.connect(func():
		_open_side_member_panel(global_pos)
	)

	vbox.add_child(_make_h_line())
	
	# 部门/区域快速分配
	var sub_title := Label.new()
	sub_title.text = "🏢 移至部门 / 区域:"
	sub_title.add_theme_font_size_override("font_size", 11)
	sub_title.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	vbox.add_child(sub_title)
	
	var grid_divs := GridContainer.new()
	grid_divs.columns = 2
	grid_divs.add_theme_constant_override("h_separation", 4)
	grid_divs.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid_divs)
	
	_add_grid_btn(grid_divs, "🚚 运输部", Color(0.15, 0.35, 0.45), func():
		action_selected.emit("SET_DIV", _target_member, GameManager.Division.TRANSPORT)
		queue_free()
	)
	
	_add_grid_btn(grid_divs, "🛡️ 防卫部", Color(0.15, 0.35, 0.45), func():
		action_selected.emit("SET_DIV", _target_member, GameManager.Division.FORTIFICATION)
		queue_free()
	)
	
	_add_grid_btn(grid_divs, "🔬 科研部", Color(0.15, 0.35, 0.45), func():
		action_selected.emit("SET_DIV", _target_member, GameManager.Division.RESEARCH)
		queue_free()
	)
	
	_add_grid_btn(grid_divs, "⚖️ 调停部", Color(0.15, 0.35, 0.45), func():
		action_selected.emit("SET_DIV", _target_member, GameManager.Division.INTERVENTION)
		queue_free()
	)
	
	_add_grid_btn(grid_divs, "🏕️ 自由人", Color(0.25, 0.35, 0.25), func():
		action_selected.emit("SET_FREE", _target_member, null)
		queue_free()
	)
	
	_add_grid_btn(grid_divs, "⛓️ 审讯区", Color(0.4, 0.2, 0.45), func():
		action_selected.emit("SET_PRISON", _target_member, null)
		queue_free()
	)
	
	# 保证面板 100% 垂直居中、死死贴在卡片右侧 (+12px) 弹出，超出右屏时平滑翻转至左侧
	await get_tree().process_frame
	var vp_size = get_viewport_rect().size
	var panel_size = _panel.size
	
	var card_half_w := 63.0
	var card_right_x = global_pos.x + card_half_w + 12.0
	var card_left_x = global_pos.x - card_half_w - 12.0 - panel_size.x
	
	# Y 轴对齐：面板垂直中心与卡片垂直中心 100% 精确对齐
	var target_pos := Vector2(card_right_x, global_pos.y - (panel_size.y * 0.5))
	
	if target_pos.x + panel_size.x > vp_size.x - 10:
		target_pos.x = card_left_x
		
	if target_pos.y + panel_size.y > vp_size.y - 10:
		target_pos.y = vp_size.y - panel_size.y - 10
	if target_pos.y < 10:
		target_pos.y = 10
		
	_panel.global_position = target_pos

func _on_backdrop_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		var click_pos = event.global_position
		if is_instance_valid(_panel) and _panel.get_global_rect().has_point(click_pos):
			return
		if is_instance_valid(_side_panel) and _side_panel.visible and _side_panel.get_global_rect().has_point(click_pos):
			return

		get_viewport().set_input_as_handled()
		queue_free()

var _side_panel: PanelContainer = null

func _toggle_side_member_panel(card_pos: Vector2):
	if is_instance_valid(_side_panel) and _side_panel.visible:
		_side_panel.visible = false
	else:
		_open_side_member_panel(card_pos)

func _open_side_member_panel(card_pos: Vector2):
	if is_instance_valid(_side_panel):
		_side_panel.visible = true
		return

	_side_panel = PanelContainer.new()
	add_child(_side_panel)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.14, 0.96)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.35, 0.45, 0.55, 0.8)
	sb.set_corner_radius_all(6)
	sb.shadow_size = 10
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.content_margin_left = 8
	sb.content_margin_top = 8
	sb.content_margin_right = 8
	sb.content_margin_bottom = 8
	_side_panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_side_panel.add_child(vbox)

	# 1. 顶层按钮：↺ 还原为默认卡片
	_add_menu_btn(vbox, "↺ 还原为默认卡片", Color(0.55, 0.2, 0.2), func():
		action_selected.emit("RESET_TO_BLANK", _target_member, null)
		queue_free()
	)

	vbox.add_child(_make_h_line())

	# 小标题
	var lbl_title := Label.new()
	lbl_title.text = "👤 指定为以下特定成员:"
	lbl_title.add_theme_font_size_override("font_size", 11)
	lbl_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(lbl_title)

	# 2. 17名成员头像+名字网格 (6列 x 3行)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)

	for mname in GameManager.MEMBER_DEFS:
		_add_member_grid_item(grid, mname)

	await get_tree().process_frame
	_position_side_panel()

func _position_side_panel():
	if not is_instance_valid(_side_panel) or not is_instance_valid(_panel):
		return
	var vp_size = get_viewport_rect().size
	var side_size = _side_panel.size
	var target_x = _panel.global_position.x + _panel.size.x + 6.0
	var target_y = _panel.global_position.y

	if target_x + side_size.x > vp_size.x - 10:
		target_x = _panel.global_position.x - side_size.x - 6.0

	if target_y + side_size.y > vp_size.y - 10:
		target_y = vp_size.y - side_size.y - 10
	if target_y < 10:
		target_y = 10

	_side_panel.global_position = Vector2(target_x, target_y)

func _add_member_grid_item(parent: Control, mname: String):
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(58, 68)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(func():
		action_selected.emit("SET_SPECIFIC_MEMBER", _target_member, mname)
		queue_free()
	)

	var normal_box := StyleBoxFlat.new()
	normal_box.bg_color = Color(0.16, 0.18, 0.22, 0.9)
	normal_box.set_corner_radius_all(4)
	normal_box.set_border_width_all(1)
	normal_box.border_color = Color(0.3, 0.35, 0.4, 0.5)
	normal_box.set_content_margin_all(0)

	var hover_box := StyleBoxFlat.new()
	hover_box.bg_color = Color(0.25, 0.35, 0.45, 0.95)
	hover_box.set_corner_radius_all(4)
	hover_box.set_border_width_all(1)
	hover_box.border_color = Color(0.9, 0.75, 0.3, 0.9)
	hover_box.set_content_margin_all(0)

	btn.add_theme_stylebox_override("normal", normal_box)
	btn.add_theme_stylebox_override("hover", hover_box)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", -18)
	btn.add_child(vbox)

	# 头像
	var portrait_box := Control.new()
	portrait_box.custom_minimum_size = Vector2(70, 70)
	portrait_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tex_rect := TextureRect.new()
	var img_path = "res://辛迪加素材/人员/" + mname + ".png"
	if ResourceLoader.exists(img_path):
		tex_rect.texture = load(img_path)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.size = Vector2(70, 70)
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 👈 头像位置偏移微调（负数往左/往上，正数往右/往下）
	var portrait_offset := Vector2(-5, -5)
	tex_rect.position = portrait_offset

	portrait_box.add_child(tex_rect)
	vbox.add_child(portrait_box)

	# 名字
	var name_box := Control.new()
	name_box.custom_minimum_size = Vector2(62, 16)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lbl := Label.new()
	lbl.text = mname
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size = Vector2(62, 16)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	
	# 👈 名字位置水平/垂直微调（负数往左/往上，正数往右/往下）
	var name_offset := Vector2(-2, -5)
	lbl.position = name_offset

	name_box.add_child(lbl)
	vbox.add_child(name_box)

	parent.add_child(btn)

func _add_menu_btn(parent: Control, text: String, color: Color, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 12)
	_style_btn(btn, color)
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn

func _add_grid_btn(parent: Control, text: String, color: Color, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 11)
	_style_btn(btn, color)
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn

func _style_btn(btn: Button, base_color: Color):
	var normal_box := StyleBoxFlat.new()
	normal_box.bg_color = base_color
	normal_box.set_corner_radius_all(4)
	normal_box.content_margin_left = 6
	normal_box.content_margin_right = 6
	normal_box.content_margin_top = 4
	normal_box.content_margin_bottom = 4
	
	var hover_box := StyleBoxFlat.new()
	hover_box.bg_color = base_color.lightened(0.2)
	hover_box.set_corner_radius_all(4)
	hover_box.content_margin_left = 6
	hover_box.content_margin_right = 6
	hover_box.content_margin_top = 4
	hover_box.content_margin_bottom = 4
	
	btn.add_theme_stylebox_override("normal", normal_box)
	btn.add_theme_stylebox_override("hover", hover_box)

func _make_h_line() -> ColorRect:
	var rect := ColorRect.new()
	rect.custom_minimum_size = Vector2(0, 1)
	rect.color = Color(0.3, 0.3, 0.35, 0.6)
	return rect
