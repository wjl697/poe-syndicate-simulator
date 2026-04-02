class_name EncounterPanel
extends PanelContainer

## 遭遇面板 — 显示当前遭遇信息、遭遇成员列表、点击成员进行操作

signal member_selected(member_name: String)
signal encounter_dismissed()

var _title_label: Label
var _division_label: Label
var _member_list: VBoxContainer
var _close_btn: Button
var _next_btn: Button
var _member_buttons: Dictionary = {}  # member_name -> Button

func _ready():
	_build_ui()
	_apply_pending_connections()
	visible = false

func _build_ui():
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.12, 0.92)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.6, 0.9, 0.6)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "⚔ 遭遇发生！"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", Color(1, 0.7, 0.3))
	vbox.add_child(_title_label)

	_division_label = Label.new()
	_division_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_division_label.add_theme_font_size_override("font_size", 16)
	_division_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox.add_child(_division_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var hint := Label.new()
	hint.text = "点击成员选择操作："
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(hint)

	_member_list = VBoxContainer.new()
	_member_list.add_theme_constant_override("separation", 6)
	vbox.add_child(_member_list)

	# 按钮容器
	var btn_container := HBoxContainer.new()
	btn_container.add_theme_constant_override("separation", 12)
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_container)

	# 关闭按钮
	_close_btn = Button.new()
	_close_btn.text = "关闭"
	_close_btn.custom_minimum_size = Vector2(120, 36)
	var close_style := StyleBoxTexture.new()
	close_style.texture = preload("res://辛迪加素材/按钮.png")
	close_style.modulate_color = Color(0.4, 0.4, 0.4)
	close_style.texture_margin_left = 6
	close_style.texture_margin_right = 6
	close_style.texture_margin_top = 6
	close_style.texture_margin_bottom = 6
	_close_btn.add_theme_stylebox_override("normal", close_style)
	_close_btn.add_theme_font_size_override("font_size", 14)
	_close_btn.pressed.connect(func(): encounter_dismissed.emit(); visible = false)
	_close_btn.visible = false
	btn_container.add_child(_close_btn)

	# 下一个遭遇按钮
	_next_btn = Button.new()
	_next_btn.text = "▶ 下一个部门遭遇"
	_next_btn.custom_minimum_size = Vector2(180, 36)
	var next_style := StyleBoxTexture.new()
	next_style.texture = preload("res://辛迪加素材/按钮.png")
	next_style.modulate_color = Color(0.15, 0.4, 0.65, 0.9)
	next_style.texture_margin_left = 6
	next_style.texture_margin_right = 6
	next_style.texture_margin_top = 6
	next_style.texture_margin_bottom = 6
	_next_btn.add_theme_stylebox_override("normal", next_style)
	var next_hover := next_style.duplicate()
	next_hover.modulate_color = next_style.modulate_color.lightened(0.2)
	_next_btn.add_theme_stylebox_override("hover", next_hover)
	_next_btn.add_theme_font_size_override("font_size", 14)
	_next_btn.add_theme_color_override("font_color", Color.WHITE)
	_next_btn.visible = false
	btn_container.add_child(_next_btn)

func show_encounter(encounter_data: Dictionary):
	_member_buttons.clear()
	for child in _member_list.get_children():
		child.queue_free()

	var div: int = encounter_data.get("division", 0)
	_title_label.text = "⚔ " + GameManager.DIVISION_NAMES.get(div, "未知") + " 遭遇！"
	_division_label.text = "参与成员: " + str(encounter_data.get("members", []).size()) + " 人"

	var enc_members: Array = encounter_data.get("members", [])
	for m in enc_members:
		var btn := Button.new()
		if m.is_revealed:
			var role_text := ""
			if m.is_leader:
				role_text = "  [首领]"
			elif m.division != GameManager.Division.NONE:
				role_text = "  [" + GameManager.DIVISION_NAMES.get(m.division, "") + "]"
			btn.text = "  " + m.member_name + "  ★" + str(m.rank) + role_text
		else:
			btn.text = "  ???  ★?"
		btn.custom_minimum_size = Vector2(280, 40)

		var btn_style := StyleBoxTexture.new()
		btn_style.texture = preload("res://辛迪加素材/按钮.png")
		btn_style.modulate_color = Color(0.65, 0.75, 1.0) # Highlight member list items
		btn_style.texture_margin_left = 6
		btn_style.texture_margin_right = 6
		btn_style.texture_margin_top = 6
		btn_style.texture_margin_bottom = 6
		btn.add_theme_stylebox_override("normal", btn_style)

		var hover_style := btn_style.duplicate()
		hover_style.modulate_color = btn_style.modulate_color.lightened(0.2)
		btn.add_theme_stylebox_override("hover", hover_style)

		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_color_override("font_color", Color.WHITE)

		var mname_copy: String = m.member_name
		btn.pressed.connect(func(): member_selected.emit(mname_copy))

		_member_list.add_child(btn)
		_member_buttons[m.member_name] = btn

	_close_btn.visible = false
	_next_btn.visible = false
	visible = true
	print("[DEBUG] EncounterPanel visible=", visible, " pos=", global_position, " size=", size, " rect=", get_global_rect())

func mark_processed(member_name: String):
	if _member_buttons.has(member_name):
		var btn: Button = _member_buttons[member_name]
		btn.disabled = true
		btn.text = btn.text + "  ✓ 已处理"

func show_close_button():
	_close_btn.visible = true
	_next_btn.visible = false
	_title_label.text = "遭遇结束"

func show_next_button():
	## 显示"下一个部门遭遇"按钮
	_next_btn.visible = true
	_close_btn.visible = false
	_title_label.text = "当前部门遭遇结束"

var _pending_next_callback: Callable

func connect_next_button(callback: Callable):
	## 由 Main 调用以连接下一个遭遇的回调
	_pending_next_callback = callback
	# 如果按钮已创建，立即连接
	if _next_btn and not _next_btn.pressed.is_connected(callback):
		_next_btn.pressed.connect(callback)

func _apply_pending_connections():
	## 在 _ready 后应用延迟连接
	if _pending_next_callback.is_valid() and _next_btn:
		if not _next_btn.pressed.is_connected(_pending_next_callback):
			_next_btn.pressed.connect(_pending_next_callback)
