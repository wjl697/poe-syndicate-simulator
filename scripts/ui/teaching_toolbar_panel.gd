class_name TeachingToolbarPanel
extends Control

signal closed()
signal tool_selected(tool_mode: String) # "MOVE", "TRUST", "RIVALRY", "CLEAR_LINE", "PLACE_CARD"
signal assign_division_requested(div_id: int)
signal remove_card_requested()
signal clear_all_requested()
signal add_star_requested()
signal sub_star_requested()
signal toggle_reveal_requested()
signal toggle_frames_requested()

var _selected_info_label: Label
var _active_mode_label: Label
var _tool_buttons: Dictionary = {} # tool_mode -> {btn: Button, base_color: Color}
var _current_tool: String = "MOVE"

var _tex_show := preload("res://辛迪加素材/界面UI/显示按钮.png")
var _tex_hide := preload("res://辛迪加素材/界面UI/隐藏按钮.png")
var _panel: PanelContainer
var _toggle_btn: TextureButton

func _ready():
	add_to_group("teaching_toolbar")
	
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(1228, 858)
	size = Vector2(529, 172)
	custom_minimum_size = Vector2(529, 172)
	
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_set_active_tool("MOVE")
	
	await get_tree().process_frame
	_align_to_toolbar_node()

func _align_to_toolbar_node():
	var nodes = get_tree().get_nodes_in_group("unassigned_slot")
	for node in nodes:
		if is_instance_valid(node) and (String(node.name) == "工具箱区域" or String(node.name) == "测试") and node is Control:
			position = node.global_position
			size = node.size
			custom_minimum_size = node.size
			_update_toggle_btn_position()
			break

func _update_toggle_btn_position():
	# 切换按钮位于工具箱右下角，使用绝对坐标定位
	# 修改 position 的 x/y 即可移动按钮（相对工具箱左上角）
	_toggle_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_toggle_btn.position = Vector2(540, 155)

func _build_ui():
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.08, 0.09, 0.13, 0.95)
	p_style.border_width_left = 2
	p_style.border_width_top = 2
	p_style.border_width_right = 2
	p_style.border_width_bottom = 2
	p_style.border_color = Color(0.8, 0.65, 0.25, 0.85) # 金色边框
	p_style.set_corner_radius_all(8)
	p_style.shadow_size = 8
	p_style.shadow_color = Color(0, 0, 0, 0.6)
	p_style.content_margin_left = 10
	p_style.content_margin_right = 10
	p_style.content_margin_top = 6
	p_style.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", p_style)
	add_child(_panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	_panel.add_child(vbox)
	
	# ===== 行 1：顶部标题栏与快捷手感提示 (HBox) =====
	var hbox_header := HBoxContainer.new()
	hbox_header.add_theme_constant_override("separation", 6)
	vbox.add_child(hbox_header)
	
	_selected_info_label = Label.new()
	_selected_info_label.text = "🎴 未选中卡牌"
	_selected_info_label.add_theme_font_size_override("font_size", 13)
	_selected_info_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	_selected_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_header.add_child(_selected_info_label)
	
	_active_mode_label = Label.new()
	_active_mode_label.text = "(👆 移动)"
	_active_mode_label.add_theme_font_size_override("font_size", 13)
	_active_mode_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.2))
	hbox_header.add_child(_active_mode_label)
	
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(6, 0)
	hbox_header.add_child(spacer)
	
	var tip_lbl := Label.new()
	tip_lbl.text = "💡 滚轮:星级 | 中键:揭示 | 右键:菜单"
	tip_lbl.add_theme_font_size_override("font_size", 12)
	tip_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	hbox_header.add_child(tip_lbl)
	
	vbox.add_child(_make_h_line())
	
	# ===== 行 2：核心主控区（🎴 刷卡放置 C 位高亮突出） =====
	var hbox_main_tools := HBoxContainer.new()
	hbox_main_tools.add_theme_constant_override("separation", 6)
	hbox_main_tools.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox_main_tools)
	
	# C 位突出按键：🎴 刷卡放置
	var place_btn := _register_tool_btn(hbox_main_tools, "PLACE_CARD", "🎴 放置卡片", Color(0.18, 0.4, 0.55), func(): toggle_or_set_tool("PLACE_CARD"))
	place_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place_btn.custom_minimum_size = Vector2(0, 32)
	
	var frames_btn := _add_simple_btn(hbox_main_tools, "👁️ 显隐边框", func(): toggle_frames_requested.emit())
	frames_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frames_btn.custom_minimum_size = Vector2(0, 32)
	
	var move_btn := _register_tool_btn(hbox_main_tools, "MOVE", "👆 移动", Color(0.2, 0.3, 0.4), func(): _set_active_tool("MOVE"))
	move_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_btn.custom_minimum_size = Vector2(0, 32)
	
	vbox.add_child(_make_h_line())
	
	# ===== 行 3：在押人员预设部门分配 =====
	var vbox_divs := VBoxContainer.new()
	vbox_divs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox_divs.add_theme_constant_override("separation", 2)
	vbox.add_child(vbox_divs)
	
	var div_title := Label.new()
	div_title.text = "🔒 在押人员预设部门分配:"
	div_title.add_theme_font_size_override("font_size", 12)
	div_title.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	vbox_divs.add_child(div_title)
	
	var hbox_div_btns := HBoxContainer.new()
	hbox_div_btns.add_theme_constant_override("separation", 4)
	vbox_divs.add_child(hbox_div_btns)
	
	var b1 := _add_simple_btn(hbox_div_btns, "🚚 运输", func(): assign_division_requested.emit(1))
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b2 := _add_simple_btn(hbox_div_btns, "🛡️ 防卫", func(): assign_division_requested.emit(2))
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b3 := _add_simple_btn(hbox_div_btns, "🔬 科研", func(): assign_division_requested.emit(3))
	b3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b4 := _add_simple_btn(hbox_div_btns, "⚖️ 调停", func(): assign_division_requested.emit(4))
	b4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b5 := _add_simple_btn(hbox_div_btns, "🏕️ 自由", func(): assign_division_requested.emit(0))
	b5.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	vbox.add_child(_make_h_line())
	
	# ===== 行 4：关系连线工具与系统控制 (HBox 左右分块) =====
	var hbox_bottom := HBoxContainer.new()
	hbox_bottom.add_theme_constant_override("separation", 6)
	hbox_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox_bottom)
	
	# 左侧：连线（主功能，占 70% 宽大空间）
	var hbox_lines := HBoxContainer.new()
	hbox_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_lines.size_flags_stretch_ratio = 2.0
	hbox_lines.add_theme_constant_override("separation", 4)
	hbox_bottom.add_child(hbox_lines)
	
	var btn_trust := _register_tool_btn(hbox_lines, "TRUST", "🟢 信任线", Color(0.16, 0.35, 0.2), func(): toggle_or_set_tool("TRUST"))
	btn_trust.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn_rival := _register_tool_btn(hbox_lines, "RIVALRY", "🔴 敌对线", Color(0.4, 0.16, 0.16), func(): toggle_or_set_tool("RIVALRY"))
	btn_rival.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn_clear_line := _register_tool_btn(hbox_lines, "CLEAR_LINE", "🧹 清线", Color(0.25, 0.25, 0.3), func(): toggle_or_set_tool("CLEAR_LINE"))
	btn_clear_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	hbox_bottom.add_child(_make_v_line())
	
	# 右侧：系统控制（次要功能，占 30% 紧凑空间）
	var hbox_actions := HBoxContainer.new()
	hbox_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_actions.size_flags_stretch_ratio = 1.0
	hbox_actions.add_theme_constant_override("separation", 4)
	hbox_bottom.add_child(hbox_actions)
	
	var btn_clear := _make_styled_btn("↺ 清空", Color(0.35, 0.25, 0.35))
	btn_clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_clear.pressed.connect(func(): clear_all_requested.emit())
	hbox_actions.add_child(btn_clear)
	
	var btn_exit := _make_styled_btn("✕ 退出", Color(0.45, 0.15, 0.15))
	btn_exit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_exit.pressed.connect(func():
		closed.emit()
		queue_free()
	)
	hbox_actions.add_child(btn_exit)

	# 工具箱显隐切换按钮（锚定于工具箱右下角，独立于面板，隐藏面板时仍保留）
	_toggle_btn = TextureButton.new()
	_toggle_btn.texture_normal = _tex_show
	_toggle_btn.texture_pressed = _tex_show
	_toggle_btn.texture_hover = _tex_show
	_toggle_btn.ignore_texture_size = true
	_toggle_btn.custom_minimum_size = Vector2(45, 53)
	_toggle_btn.size = Vector2(45, 53)
	_toggle_btn.scale = Vector2(0.6, 0.6)
	_toggle_btn.pressed.connect(_toggle_panel)
	add_child(_toggle_btn)
	_update_toggle_btn_position()

func _toggle_panel():
	if _panel == null:
		return
	_panel.visible = not _panel.visible
	if _panel.visible:
		_toggle_btn.texture_normal = _tex_show
		_toggle_btn.texture_pressed = _tex_show
		_toggle_btn.texture_hover = _tex_show
	else:
		_toggle_btn.texture_normal = _tex_hide
		_toggle_btn.texture_pressed = _tex_hide
		_toggle_btn.texture_hover = _tex_hide

func update_selected_card_info(card_name: String, rank: int, div_name: String):
	if card_name == "":
		_selected_info_label.text = "🎴 未选中卡牌"
	else:
		_selected_info_label.text = "🎴 选中: " + card_name + " (" + str(rank) + "星," + div_name + ")"

func toggle_or_set_tool(tool_mode: String):
	if _current_tool == tool_mode and tool_mode != "MOVE":
		_set_active_tool("MOVE")
	else:
		_set_active_tool(tool_mode)

func reset_to_move_tool():
	_set_active_tool("MOVE")

func _set_active_tool(tool_mode: String):
	_current_tool = tool_mode
	_update_tool_buttons_highlight()
	
	match tool_mode:
		"MOVE": _active_mode_label.text = "(👆 移动)"
		"PLACE_CARD": _active_mode_label.text = "(🎴 放置)"
		"TOGGLE_REVEAL": _active_mode_label.text = "(❓ 翻牌)"
		"ADD_STAR": _active_mode_label.text = "(⭐+ 加星)"
		"SUB_STAR": _active_mode_label.text = "(⭐- 减星)"
		"TRUST": _active_mode_label.text = "(🟢 信任线)"
		"RIVALRY": _active_mode_label.text = "(🔴 敌对线)"
		"CLEAR_LINE": _active_mode_label.text = "(🧹 清线)"
		
	tool_selected.emit(tool_mode)

func _update_tool_buttons_highlight():
	for tool_key in _tool_buttons:
		var data = _tool_buttons[tool_key]
		var btn: Button = data["btn"]
		var base_color: Color = data["base_color"]
		
		var style := StyleBoxFlat.new()
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		style.content_margin_left = 3
		style.content_margin_right = 3
		
		if tool_key == _current_tool:
			style.bg_color = Color(0.85, 0.65, 0.15, 0.98) # 金黄发光高亮激活态
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
			style.border_color = Color(1.0, 0.95, 0.5)
			btn.add_theme_color_override("font_color", Color(0, 0, 0))
		else:
			style.bg_color = base_color
			btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
			
		btn.add_theme_stylebox_override("normal", style)

func _register_tool_btn(container: Control, tool_key: String, text: String, base_color: Color, callback: Callable) -> Button:
	var btn := _make_styled_btn(text, base_color)
	btn.pressed.connect(callback)
	container.add_child(btn)
	_tool_buttons[tool_key] = {"btn": btn, "base_color": base_color}
	return btn

func _add_simple_btn(container: Control, text: String, callback: Callable) -> Button:
	var btn := _make_styled_btn(text, Color(0.15, 0.22, 0.35))
	btn.pressed.connect(callback)
	container.add_child(btn)
	return btn

func _make_styled_btn(text: String, bg_color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 30)
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 3
	style.content_margin_right = 3
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_font_size_override("font_size", 13.5)
	return btn

func _make_h_line() -> ColorRect:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.color = Color(0.25, 0.3, 0.4, 0.5)
	return line

func _make_v_line() -> ColorRect:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(1, 0)
	line.color = Color(0.25, 0.3, 0.4, 0.5)
	return line
