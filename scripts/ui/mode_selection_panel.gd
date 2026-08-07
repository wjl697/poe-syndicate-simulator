class_name ModeSelectionPanel
extends Control

## 统一模式选择界面控制器
## 提供经典模式、沙盒模式、教学模式的统一入口

signal mode_selected(mode_id: String)

var _tex_bg := preload("res://辛迪加素材/界面UI/开局背景.png")
var _tex_btn := preload("res://辛迪加素材/界面UI/按钮.png")

var _center_container: CenterContainer

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_panel_layout()
	get_viewport().size_changed.connect(_update_panel_layout)
	_build_ui()

func _update_panel_layout():
	var vp_size := get_viewport_rect().size
	custom_minimum_size = vp_size
	if _center_container != null and is_instance_valid(_center_container):
		_center_container.custom_minimum_size = vp_size

func _build_ui():
	var vp_size := get_viewport_rect().size

	# 1. 全屏开局背景图
	var bg := TextureRect.new()
	bg.texture = _tex_bg
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.custom_minimum_size = vp_size
	add_child(bg)

	# 2. 居中主容器 (确保整体在 1920x1080 视口中精确水平/垂直居中)
	_center_container = CenterContainer.new()
	_center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center_container.custom_minimum_size = vp_size
	add_child(_center_container)

	var main_vbox := VBoxContainer.new()
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_theme_constant_override("separation", 24)
	_center_container.add_child(main_vbox)

	# --- 标题区域 ---
	var title_box := VBoxContainer.new()
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", 6)
	main_vbox.add_child(title_box)

	var title_lbl := Label.new()
	title_lbl.text = "辛 迪 加"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 52)
	title_lbl.add_theme_color_override("font_color", Color(0.98, 0.88, 0.55))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	title_lbl.add_theme_constant_override("shadow_offset_x", 3)
	title_lbl.add_theme_constant_override("shadow_offset_y", 3)
	title_box.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "— 请 选择 游 戏 模 式 —"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 18)
	sub_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	sub_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	sub_lbl.add_theme_constant_override("shadow_offset_x", 2)
	sub_lbl.add_theme_constant_override("shadow_offset_y", 2)
	title_box.add_child(sub_lbl)

	# --- 三大模式卡片容器 ---
	var cards_hbox := HBoxContainer.new()
	cards_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_hbox.add_theme_constant_override("separation", 28)
	main_vbox.add_child(cards_hbox)

	var modes_data := [
		{
			"id": "classic",
			"title": "⚔  经典模式",
			"sub": "标准遭遇战",
			"desc": "标准黑帮解密遭遇流程\n搜集组织情报，捕获部门首领"
		},
		{
			"id": "sandbox",
			"title": "🛠  沙盒模式",
			"sub": "自由盘面布阵",
			"desc": "自由创建与修改自定义局势\n手调成员在押状态、星级与部门"
		},
		{
			"id": "tutorial",
			"title": "🎓  教学模式",
			"sub": "电子画板推演",
			"desc": "电子画板教学与逻辑推演\n自由连线、抽象卡牌与模拟遭遇"
		}
	]

	for mdata in modes_data:
		var card := _create_mode_card(mdata)
		cards_hbox.add_child(card)

## 创建单个模式卡片（符合底板木框的精美居中比例）
func _create_mode_card(data: Dictionary) -> Control:
	var container := PanelContainer.new()
	container.custom_minimum_size = Vector2(290, 370)
	container.pivot_offset = Vector2(145, 185)

	# 黑色半透明质感 StyleBox
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color(0.05, 0.07, 0.11, 0.88)
	box_style.border_width_left = 2
	box_style.border_width_top = 2
	box_style.border_width_right = 2
	box_style.border_width_bottom = 2
	box_style.border_color = Color(0.7, 0.58, 0.28, 0.6)
	box_style.corner_radius_top_left = 10
	box_style.corner_radius_top_right = 10
	box_style.corner_radius_bottom_left = 10
	box_style.corner_radius_bottom_right = 10
	box_style.content_margin_left = 20
	box_style.content_margin_right = 20
	box_style.content_margin_top = 22
	box_style.content_margin_bottom = 22
	box_style.shadow_color = Color(0, 0, 0, 0.7)
	box_style.shadow_size = 16
	container.add_theme_stylebox_override("panel", box_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	container.add_child(vbox)

	# 模式副标题
	var sub_lbl := Label.new()
	sub_lbl.text = data["sub"]
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 18)
	sub_lbl.add_theme_color_override("font_color", Color(0.9, 0.78, 0.45))
	vbox.add_child(sub_lbl)

	# 模式专属存档状态提示
	var mode_id_str: String = data["id"]
	var save_lbl := Label.new()
	if GameManager.has_mode_save(mode_id_str):
		save_lbl.text = "💾 已保存进度"
		save_lbl.add_theme_color_override("font_color", Color(0.45, 0.92, 0.55))
	else:
		save_lbl.text = "✨ 未开始"
		save_lbl.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	save_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	save_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(save_lbl)

	# 金色分割线
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 2)
	line.color = Color(0.7, 0.58, 0.28, 0.4)
	vbox.add_child(line)

	# 简介描述
	var desc_lbl := Label.new()
	desc_lbl.text = data["desc"]
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(250, 140)
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_lbl.add_theme_font_size_override("font_size", 15)
	desc_lbl.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	desc_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	desc_lbl.add_theme_constant_override("shadow_offset_x", 1)
	desc_lbl.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(desc_lbl)

	# 模式选择按钮 (使用 按钮.png 纹理)
	var btn := Button.new()
	btn.text = data["title"]
	btn.custom_minimum_size = Vector2(250, 56)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	btn.add_theme_constant_override("shadow_offset_x", 2)
	btn.add_theme_constant_override("shadow_offset_y", 2)

	# 九宫格 StyleBox (按钮.png)
	var btn_normal := StyleBoxTexture.new()
	btn_normal.texture = _tex_btn
	btn_normal.texture_margin_left = 16
	btn_normal.texture_margin_top = 16
	btn_normal.texture_margin_right = 16
	btn_normal.texture_margin_bottom = 16

	var btn_hover := btn_normal.duplicate()
	btn_hover.modulate_color = Color(1.2, 1.15, 0.95, 1.0)

	var btn_pressed := btn_normal.duplicate()
	btn_pressed.modulate_color = Color(0.8, 0.75, 0.7, 1.0)

	btn.add_theme_stylebox_override("normal", btn_normal)
	btn.add_theme_stylebox_override("hover", btn_hover)
	btn.add_theme_stylebox_override("pressed", btn_pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	vbox.add_child(btn)

	var mode_id: String = data["id"]
	btn.pressed.connect(func():
		mode_selected.emit(mode_id)
	)

	# 悬停卡片微放大动画
	container.mouse_entered.connect(func():
		var tw = create_tween().set_parallel(true)
		tw.tween_property(box_style, "border_color", Color(1.0, 0.85, 0.35, 1.0), 0.15)
		tw.tween_property(container, "scale", Vector2(1.03, 1.03), 0.15)
	)
	container.mouse_exited.connect(func():
		var tw = create_tween().set_parallel(true)
		tw.tween_property(box_style, "border_color", Color(0.7, 0.58, 0.28, 0.6), 0.15)
		tw.tween_property(container, "scale", Vector2(1.0, 1.0), 0.15)
	)

	return container
