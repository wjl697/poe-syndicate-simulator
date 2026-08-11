class_name ModeSelectionPanel
extends Control

## 统一模式选择界面控制器
## 提供经典模式、沙盒模式、教学模式的统一入口

signal mode_selected(mode_id: String)

var _tex_bg := preload("res://辛迪加素材/界面UI/开局背景.png")
var _tex_btn := preload("res://辛迪加素材/界面UI/按钮.png")
var _tex_btn2 := preload("res://辛迪加素材/界面UI/按钮2.png")

var _center_container: CenterContainer
var _lobby_vbox: VBoxContainer
var _main_menu: Control
var _overlay_root: Control
var _back_btn: Button

var _tex_logo := preload("res://辛迪加素材/界面UI/加载图标.png")
var _font_noto := preload("res://辛迪加素材/字体/NotoSansSC-VariableFont_wght.ttf")
var _tex_subtitle := preload("res://辛迪加素材/界面UI/界面副标题.png")

static var has_shown_logo_splash: bool = false

# 若为 true，则 _ready 直接显示模式选择大厅（从游戏中返回），不进入主菜单
var start_direct_lobby: bool = false

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_panel_layout()
	get_viewport().size_changed.connect(_update_panel_layout)
	_build_ui()

	# 品牌 Logo 仅在游戏启动时展示一次；动画结束后进入主菜单
	if start_direct_lobby:
		_show_mode_lobby()
	elif not ModeSelectionPanel.has_shown_logo_splash:
		ModeSelectionPanel.has_shown_logo_splash = true
		_play_logo_splash_animation()
	else:
		_show_main_menu()

func _play_logo_splash_animation():
	var splash_layer := Control.new()
	splash_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	splash_layer.custom_minimum_size = get_viewport_rect().size
	splash_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(splash_layer)

	var bg_black := ColorRect.new()
	bg_black.color = Color(0, 0, 0, 1.0) # 绝对纯黑，与启动黑屏 100% 保持一致无色差
	bg_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	splash_layer.add_child(bg_black)

	var center_container := CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_container.custom_minimum_size = get_viewport_rect().size
	splash_layer.add_child(center_container)

	var center_box := VBoxContainer.new()
	center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center_box.add_theme_constant_override("separation", 16)
	center_container.add_child(center_box)

	# 1. LOGO 品牌图片（加载图标.png）
	var logo_rect := TextureRect.new()
	logo_rect.texture = _tex_logo
	logo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo_rect.custom_minimum_size = Vector2(80, 80)
	logo_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center_box.add_child(logo_rect)

	# 2. 界面副标题图片
	var subtitle_rect := TextureRect.new()
	subtitle_rect.texture = _tex_subtitle
	subtitle_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	subtitle_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	subtitle_rect.custom_minimum_size = Vector2(251, 63)
	subtitle_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center_box.add_child(subtitle_rect)

	# 纯黑背景 (#000000) 100% 保持无色差；Logo 内容从纯黑背景中淡入与淡出
	splash_layer.modulate.a = 1.0
	center_box.modulate.a = 0.0 # Logo 品牌图文初始完全透明

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	# 阶段 1：Logo 品牌图文从纯黑背景中平滑淡入 (0.6 秒)
	tween.tween_property(center_box, "modulate:a", 1.0, 0.6)
	# 阶段 2：品牌 Logo 停顿展示 (2.0 秒)
	tween.tween_interval(2.0)
	# 阶段 3：Logo 品牌图文平滑淡出回纯黑背景 (0.6 秒)
	tween.tween_property(center_box, "modulate:a", 0.0, 0.6)
	# 阶段 4：纯黑背景层平滑淡出 (0.4 秒) 揭开主菜单
	tween.tween_property(splash_layer, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func():
		splash_layer.queue_free()
		_show_main_menu()
	)

	# 点击跳过
	splash_layer.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			tween.kill()
			splash_layer.queue_free()
			_show_main_menu()
	)

func _update_panel_layout():
	if not is_inside_tree() or not visible:
		return
	var vp_size := get_viewport_rect().size
	custom_minimum_size = vp_size
	if _center_container != null and is_instance_valid(_center_container):
		_center_container.custom_minimum_size = vp_size

func _build_ui():
	var vp_size := get_viewport_rect().size

	# 1. 开局背景图 (与游戏内背景.png 的 TextureRect 完全一致：COVERED 全屏铺满)
	var bg := TextureRect.new()
	bg.texture = _tex_bg
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	_lobby_vbox = main_vbox
	# 初始隐藏大厅：加载动画结束后先进入主菜单
	_center_container.visible = false

	# --- 标题区域 ---
	var title_box := VBoxContainer.new()
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", 6)
	main_vbox.add_child(title_box)

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
			"title": "经典模式",
			"sub": "标准遭遇战",
			"desc": "标准黑帮解密遭遇流程\n搜集组织情报，捕获部门首领"
		},
		{
			"id": "sandbox",
			"title": "沙盒模式",
			"sub": "自由盘面布阵",
			"desc": "自由创建与修改自定义局势\n手调成员在押状态、星级与部门"
		},
		{
			"id": "tutorial",
			"title": "画板模式",
			"sub": "电子画板推演",
			"desc": "电子画板教学与逻辑推演\n自由连线、抽象卡牌与模拟遭遇"
		}
	]

	for mdata in modes_data:
		var card := _create_mode_card(mdata)
		cards_hbox.add_child(card)

# ===== 主菜单 / 覆盖层导航 =====

func _show_main_menu():
	if _lobby_vbox != null and is_instance_valid(_lobby_vbox):
		_center_container.visible = false
	if _back_btn != null and is_instance_valid(_back_btn):
		_back_btn.visible = false
	if _overlay_root != null and is_instance_valid(_overlay_root):
		_overlay_root.queue_free()
		_overlay_root = null
	if _main_menu == null or not is_instance_valid(_main_menu):
		var menu_script := preload("res://scripts/ui/main_menu_panel.gd")
		_main_menu = menu_script.new()
		_main_menu.mode_selection_requested.connect(_show_mode_lobby)
		_main_menu.encyclopedia_requested.connect(_show_encyclopedia)
		_main_menu.contact_requested.connect(_show_contact)
		_main_menu.exit_requested.connect(_on_main_menu_exit)
		add_child(_main_menu)
	_main_menu.visible = true

func _show_mode_lobby():
	if _main_menu != null and is_instance_valid(_main_menu):
		_main_menu.visible = false
	if _center_container != null and is_instance_valid(_center_container):
		_center_container.visible = true
	_ensure_back_btn()
	if _back_btn != null and is_instance_valid(_back_btn):
		_back_btn.visible = true

# 供外部调用：直接从游戏返回时显示模式选择大厅
func show_lobby():
	_show_mode_lobby()

# 独立定位的「返回主菜单」按钮（锚点定位，不影响大厅其他元素布局）
func _ensure_back_btn():
	if _back_btn != null and is_instance_valid(_back_btn):
		return
	_back_btn = Button.new()
	_back_btn.text = "返回菜单"
	_back_btn.add_theme_font_size_override("font_size", 18)
	var back_font := FontVariation.new()
	back_font.base_font = _font_noto
	back_font.variation_embolden = 0.5   # ← 矢量加粗：0 常规 / 0.5 中粗 / 1.0 更粗
	_back_btn.add_theme_font_override("font", back_font)
	_back_btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	_back_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	_back_btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_back_btn.add_theme_constant_override("shadow_offset_x", 2)
	_back_btn.add_theme_constant_override("shadow_offset_y", 2)

	var back_normal := StyleBoxTexture.new()
	back_normal.texture = _tex_btn2
	back_normal.texture_margin_left = 28
	back_normal.texture_margin_top = 10
	back_normal.texture_margin_right = 28
	back_normal.texture_margin_bottom = 10

	var back_hover := back_normal.duplicate()
	back_hover.modulate_color = Color(1.2, 1.15, 0.95, 1.0)

	var back_pressed := back_normal.duplicate()
	back_pressed.modulate_color = Color(0.8, 0.75, 0.7, 1.0)

	_back_btn.add_theme_stylebox_override("normal", back_normal)
	_back_btn.add_theme_stylebox_override("hover", back_hover)
	_back_btn.add_theme_stylebox_override("pressed", back_pressed)
	_back_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_back_btn.pressed.connect(_show_main_menu)

	# 直接定位：水平居中，垂直固定在屏幕中下区域
	# 调整 position 可单独移动按钮，不影响大厅其他元素布局
	var vp_size := get_viewport_rect().size
	_back_btn.custom_minimum_size = Vector2(260, 0)
	_back_btn.position = Vector2((vp_size.x - 260) * 0.5, vp_size.y * 0.9)
	add_child(_back_btn)

func _create_overlay() -> Control:
	if _main_menu != null and is_instance_valid(_main_menu):
		_main_menu.visible = false
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.custom_minimum_size = get_viewport_rect().size
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	_overlay_root = overlay
	return overlay

func _on_main_menu_exit():
	get_tree().quit()

## 百科大全：目前为游戏规则说明占位页面
func _show_encyclopedia():
	var overlay := _create_overlay()

	var bg_black := ColorRect.new()
	bg_black.color = Color(0.05, 0.05, 0.08, 0.96)
	bg_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg_black)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.98)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.7, 0.58, 0.28, 0.9)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_color = Color(0, 0, 0, 0.7)
	style.shadow_size = 18
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)

	var panel_size := Vector2(760, 620)
	panel.size = panel_size
	var vp := get_viewport_rect().size
	panel.position = Vector2((vp.x - panel_size.x) * 0.5, (vp.y - panel_size.y) * 0.5)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "📖  百科大全 — 游戏规则"
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", Color(0.98, 0.88, 0.55))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 2)
	divider.color = Color(0.7, 0.58, 0.28, 0.4)
	vbox.add_child(divider)

	var rules_text := Label.new()
	rules_text.text = "《辛迪加》游戏规则（整理中）\n\n" + \
		"1. 组织由四大部门构成：运输部、防卫部、科研部、调停部，另有自由人与在押人员。\n\n" + \
		"2. 点击「开始遭遇」随机生成一场遭遇，根据线索锁定目标部门成员。\n\n" + \
		"3. 处理遭遇时，可选择审讯、调查、营救、释放等行动，行动结果会改变成员状态与情报值。\n\n" + \
		"4. 当部门情报值达到满值时，藏身处坐标暴露，可发动「突袭」捕获首领。\n\n" + \
		"5. 捕获全部部门首领即可获胜；成员被押时间过长可能引发严重后果。\n\n" + \
		"6. 支持经典模式、沙盒模式与教学模式三种游玩方式。\n\n" + \
		"— 更多内容正在完善中，敬请期待 —"
	rules_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules_text.add_theme_font_size_override("font_size", 16)
	rules_text.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	rules_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	rules_text.add_theme_constant_override("shadow_offset_x", 1)
	rules_text.add_theme_constant_override("shadow_offset_y", 1)
	rules_text.custom_minimum_size = Vector2(680, 420)
	vbox.add_child(rules_text)

	var back_btn := Button.new()
	back_btn.text = "◀  返回主菜单"
	back_btn.custom_minimum_size = Vector2(220, 46)
	back_btn.add_theme_font_size_override("font_size", 16)
	back_btn.pressed.connect(_show_main_menu)
	back_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(back_btn)

## 联系作者：B站主页 + 赞赏码占位
func _show_contact():
	var overlay := _create_overlay()

	var bg_black := ColorRect.new()
	bg_black.color = Color(0, 0, 0, 0.6)
	bg_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg_black)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.98)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.7, 0.58, 0.28, 0.9)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_color = Color(0, 0, 0, 0.7)
	style.shadow_size = 18
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)

	var panel_size := Vector2(480, 380)
	panel.size = panel_size
	var vp := get_viewport_rect().size
	panel.position = Vector2((vp.x - panel_size.x) * 0.5, (vp.y - panel_size.y) * 0.5)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "💬  联系作者"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(0.98, 0.88, 0.55))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	var bili_btn := Button.new()
	bili_btn.text = "B站主页：https://space.bilibili.com/XXXXXXX"
	bili_btn.custom_minimum_size = Vector2(400, 46)
	bili_btn.add_theme_font_size_override("font_size", 15)
	bili_btn.pressed.connect(func():
		OS.shell_open("https://space.bilibili.com/XXXXXXX")
	)
	vbox.add_child(bili_btn)

	var tip_lbl := Label.new()
	tip_lbl.text = "如果喜欢这个游戏，欢迎扫码支持一下："
	tip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip_lbl.add_theme_font_size_override("font_size", 14)
	tip_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	vbox.add_child(tip_lbl)

	# 赞赏码占位：待替换为真实赞赏码图片
	var qr_placeholder := ColorRect.new()
	qr_placeholder.color = Color(0.2, 0.22, 0.28, 1.0)
	qr_placeholder.custom_minimum_size = Vector2(180, 180)
	var qr_frame := PanelContainer.new()
	qr_frame.add_theme_stylebox_override("panel", _make_panel_style())
	vbox.add_child(qr_frame)
	qr_frame.add_child(qr_placeholder)

	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(160, 42)
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.pressed.connect(_show_main_menu)
	vbox.add_child(close_btn)

func _make_panel_style() -> StyleBox:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.7, 0.58, 0.28, 0.9)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style

## 创建单个模式卡片（符合底板木框的精美居中比例）
func _create_mode_card(data: Dictionary) -> Control:
	var container := PanelContainer.new()
	container.custom_minimum_size = Vector2(245, 315)
	container.pivot_offset = Vector2(122.5, 157.5)

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
	desc_lbl.custom_minimum_size = Vector2(205, 110)
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
	btn.custom_minimum_size = Vector2(130, 36)
	btn.add_theme_font_size_override("font_size", 15)
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

	# 让按钮不拦截鼠标事件，避免鼠标移到按钮上时卡片容器触发 mouse_exited
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
