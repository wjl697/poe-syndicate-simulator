class_name ActionPanel
extends PanelContainer

## 操作面板 — 浮动弹出式，显示可选操作按钮

signal action_chosen(member_name: String, action: int)

var _current_member_name: String = ""
var _title_label: Label
var _desc_label: RichTextLabel
var _button_container: VBoxContainer
var is_mouse_inside: bool = false  # 鼠标是否在面板内

func _ready():
	_build_ui()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): is_mouse_inside = true)
	mouse_exited.connect(func(): is_mouse_inside = false)

func _build_ui():
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.14, 0.92)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.7, 0.55, 0.2, 0.6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# 标题
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 17)
	_title_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	vbox.add_child(_title_label)

	# 分隔线
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	# 说明
	_desc_label = RichTextLabel.new()
	_desc_label.bbcode_enabled = true
	_desc_label.fit_content = true
	_desc_label.custom_minimum_size = Vector2(180, 16)
	_desc_label.add_theme_font_size_override("normal_font_size", 12)
	_desc_label.add_theme_color_override("default_color", Color(0.75, 0.75, 0.75))
	vbox.add_child(_desc_label)

	# 按钮容器
	_button_container = VBoxContainer.new()
	_button_container.add_theme_constant_override("separation", 5)
	vbox.add_child(_button_container)

func show_actions(member_name: String, actions: Array):
	_current_member_name = member_name
	_title_label.text = member_name

	var remaining_count := 0
	if not GameManager.current_encounter.is_empty():
		for m in GameManager.current_encounter.get("members", []):
			if m.member_name not in GameManager.current_encounter.get("processed", []):
				remaining_count += 1
	_desc_label.text = "剩余: " + str(remaining_count) + " 人"

	# 清除旧按钮
	for child in _button_container.get_children():
		child.queue_free()

	# Preload button texture for reuse
	var btn_tex := preload("res://辛迪加素材/界面UI/按钮.png")

	# 创建操作按钮
	for action in actions:
		var btn := Button.new()
		btn.text = GameManager.get_action_name(action)
		btn.tooltip_text = GameManager.get_action_description(action)
		btn.custom_minimum_size = Vector2(150, 32)

		var btn_style := StyleBoxTexture.new()
		btn_style.texture = btn_tex
		btn_style.modulate_color = _get_action_color(action)
		btn_style.texture_margin_left = 6
		btn_style.texture_margin_right = 6
		btn_style.texture_margin_top = 6
		btn_style.texture_margin_bottom = 6
		btn.add_theme_stylebox_override("normal", btn_style)

		var hover_style := btn_style.duplicate()
		hover_style.modulate_color = btn_style.modulate_color.lightened(0.2)
		btn.add_theme_stylebox_override("hover", hover_style)

		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", Color.WHITE)

		var act_copy: int = action
		btn.pressed.connect(func(): _on_action_pressed(act_copy))

		_button_container.add_child(btn)

	visible = true

# 浮动弹出：在指定屏幕坐标附近显示
func show_actions_at(member_name: String, actions: Array, screen_pos: Vector2):
	show_actions(member_name, actions)

	# 切换为绝对定位模式
	anchor_left = 0
	anchor_top = 0
	anchor_right = 0
	anchor_bottom = 0

	var vp_size := get_viewport_rect().size
	var panel_w := 200.0
	var panel_h := 240.0

	# 默认在卡片右侧弹出
	var px: float = screen_pos.x + 130
	var py: float = screen_pos.y - panel_h * 0.5

	# 超出右边界 → 放到左侧
	if px + panel_w > vp_size.x - 10:
		px = screen_pos.x - 130 - panel_w

	# 防止超出屏幕边界
	py = clampf(py, 10, vp_size.y - panel_h - 10)

	offset_left = px
	offset_top = py
	offset_right = px + panel_w
	offset_bottom = py + panel_h

func hide_panel():
	visible = false

func show_result(effects: Array):
	for child in _button_container.get_children():
		child.queue_free()

	_title_label.text = "操作结果"
	var text := ""
	for e in effects:
		text += "• " + str(e) + "\n"
	_desc_label.text = text
	visible = true

func _get_action_color(action: int) -> Color:
	match action:
		GameManager.ActionType.INTERROGATE: return Color(0.15, 0.35, 0.65, 0.9)
		GameManager.ActionType.EXECUTE:     return Color(0.6, 0.15, 0.15, 0.9)
		GameManager.ActionType.BARGAIN:     return Color(0.2, 0.5, 0.2, 0.9)
		GameManager.ActionType.BETRAY:      return Color(0.55, 0.3, 0.1, 0.9)
		GameManager.ActionType.RELEASE:     return Color(0.35, 0.35, 0.35, 0.9)
		GameManager.ActionType.FORM_TRUST:  return Color(0.15, 0.55, 0.25, 0.9)
		GameManager.ActionType.FORM_RIVALRY:return Color(0.65, 0.12, 0.12, 0.9)
	return Color(0.3, 0.3, 0.3, 0.9)

func _on_action_pressed(action: int):
	action_chosen.emit(_current_member_name, action)
