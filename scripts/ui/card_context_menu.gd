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
		get_viewport().set_input_as_handled()
		queue_free()

func _add_menu_btn(parent: Control, text: String, color: Color, callback: Callable):
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 12)
	_style_btn(btn, color)
	btn.pressed.connect(callback)
	parent.add_child(btn)

func _add_grid_btn(parent: Control, text: String, color: Color, callback: Callable):
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 11)
	_style_btn(btn, color)
	btn.pressed.connect(callback)
	parent.add_child(btn)

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
