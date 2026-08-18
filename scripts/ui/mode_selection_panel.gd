class_name ModeSelectionPanel
extends Control

## 统一模式选择界面控制器
## 提供经典模式、沙盒模式、教学模式的统一入口

signal mode_selected(mode_id: String)

var _tex_bg := preload("res://辛迪加素材/界面UI/开局背景.jpg")

var _tex_btn := preload("res://辛迪加素材/界面UI/按钮.png")
var _tex_btn2 := preload("res://辛迪加素材/界面UI/按钮2.png")

var _center_container: CenterContainer
var _lobby_vbox: VBoxContainer
var _main_menu: Control
var _overlay_root: Control
var _back_btn: Button

var _tex_logo := preload("res://辛迪加素材/界面UI/加载图标.png")
var _font_noto := preload("res://辛迪加素材/字体/zt.ttf")

var _tex_subtitle := preload("res://辛迪加素材/界面UI/界面副标题.png")

static func _get_qr_texture() -> Texture2D:
	var paths = [
		"res://辛迪加素材/界面UI/赞赏码.png",
		"res://辛迪加素材/界面UI/赞赏码.jpg",
		"res://辛迪加素材/界面UI/赞赏码.jpeg"
	]
	for p in paths:
		if ResourceLoader.exists(p):
			var res = load(p)
			if res is Texture2D:
				return res
	return null

static var has_shown_logo_splash: bool = false



# 若为 true，则 _ready 直接显示模式选择大厅（从游戏中返回），不进入主菜单
var start_direct_lobby: bool = false

## 开局动画各阶段时长配置 (秒)
@export var splash_fade_in_time: float = 0.5   # Logo 品牌图文淡入时间
@export var splash_stay_time: float = 1.0      # Logo 品牌展示停留时间 (建议 0.8 ~ 1.5 秒)
@export var splash_fade_out_time: float = 0.5  # Logo 品牌图文淡出时间
@export var splash_curtain_time: float = 0.4   # 黑幕揭开显示主界面时间


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
		# 预先渲染好底层的完整主菜单（包含背景、标题和按钮），避免遮罩淡出时产生“先显背景后吐按钮”的割裂感
		_show_main_menu()
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
	# 阶段 1：Logo 品牌图文平滑淡入
	tween.tween_property(center_box, "modulate:a", 1.0, splash_fade_in_time)
	# 阶段 2：品牌 Logo 停顿展示
	tween.tween_interval(splash_stay_time)
	# 阶段 3：Logo 品牌图文平滑淡出回纯黑背景
	tween.tween_property(center_box, "modulate:a", 0.0, splash_fade_out_time)
	# 阶段 4：纯黑幕布淡出，平滑同步揭开底层早已准备好的完整主菜单（背景+标题+按钮）
	tween.tween_property(splash_layer, "modulate:a", 0.0, splash_curtain_time)
	tween.tween_callback(func():
		if is_instance_valid(splash_layer):
			splash_layer.queue_free()
	)

	# 点击跳过
	splash_layer.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			tween.kill()
			if is_instance_valid(splash_layer):
				splash_layer.queue_free()
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

## 百科大全：加载 Markdown 文档展示
func _show_encyclopedia():
	var overlay := _create_overlay()

	# 背景：黑色透明遮罩
	var bg_black := ColorRect.new()
	bg_black.color = Color(0, 0, 0, 0.55)
	bg_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg_black)

	# 无边框黑色透明显示框
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.76)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)

	var panel_size := Vector2(1120, 720)
	panel.size = panel_size
	var vp := get_viewport_rect().size
	panel.position = Vector2((vp.x - panel_size.x) * 0.5, (vp.y - panel_size.y) * 0.5)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "📖  游戏百科"
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", Color(0.98, 0.88, 0.55))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 2)
	divider.color = Color(0.7, 0.58, 0.28, 0.4)
	vbox.add_child(divider)

	# 左右结构容器 (左侧固定悬浮目录侧边栏 + 右侧 Markdown 视图)
	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(content_hbox)

	# ===== 左侧：固定悬浮章节目录侧边栏 =====
	var toc_panel := PanelContainer.new()
	toc_panel.custom_minimum_size = Vector2(230, 560)
	var toc_style := StyleBoxFlat.new()
	toc_style.bg_color = Color(0.06, 0.06, 0.1, 0.6)
	toc_style.corner_radius_top_left = 6
	toc_style.corner_radius_top_right = 6
	toc_style.corner_radius_bottom_left = 6
	toc_style.corner_radius_bottom_right = 6
	toc_style.border_width_left = 1
	toc_style.border_width_right = 1
	toc_style.border_width_top = 1
	toc_style.border_width_bottom = 1
	toc_style.border_color = Color(0.7, 0.58, 0.28, 0.35)
	toc_style.content_margin_left = 8
	toc_style.content_margin_right = 8
	toc_style.content_margin_top = 10
	toc_style.content_margin_bottom = 10
	toc_panel.add_theme_stylebox_override("panel", toc_style)
	content_hbox.add_child(toc_panel)

	var toc_vbox := VBoxContainer.new()
	toc_vbox.add_theme_constant_override("separation", 8)
	toc_panel.add_child(toc_vbox)

	var toc_title := Label.new()
	toc_title.text = "📌 章节速查目录"
	toc_title.add_theme_font_size_override("font_size", 14)
	toc_title.add_theme_color_override("font_color", Color(0.98, 0.88, 0.55))
	toc_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toc_vbox.add_child(toc_title)

	var toc_div := ColorRect.new()
	toc_div.custom_minimum_size = Vector2(0, 1)
	toc_div.color = Color(0.7, 0.58, 0.28, 0.3)
	toc_vbox.add_child(toc_div)

	var toc_scroll := ScrollContainer.new()
	toc_scroll.custom_minimum_size = Vector2(214, 500)
	toc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	toc_vbox.add_child(toc_scroll)

	var toc_list := VBoxContainer.new()
	toc_list.add_theme_constant_override("separation", 4)
	toc_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toc_scroll.add_child(toc_list)

	# ===== 右侧：Markdown 内容区 =====
	var md_label := MarkdownLabel.new()
	md_label.custom_minimum_size = Vector2(810, 560)
	md_label.size = Vector2(810, 560)
	md_label.scroll_active = true
	md_label.scroll_following = false
	md_label.automatic_links = true
	md_label.add_theme_font_size_override("normal_font_size", 14)
	md_label.add_theme_color_override("default_color", Color(0.82, 0.82, 0.85))
	var bold_c := Color8(255, 120, 116)
	md_label.add_theme_color_override("bold_color", bold_c)
	md_label.bold_color = bold_c
	md_label.add_theme_constant_override("line_separation", 6)

	md_label.add_theme_constant_override("table_h_separation", 18)
	md_label.add_theme_constant_override("table_v_separation", 6)
	md_label.table_border_color = Color(1.0, 1.0, 1.0, 0.15)
	md_label.table_background_color = Color(0.08, 0.08, 0.12, 0.72)
	md_label.display_file("res://docs/辛迪加新手入门指南.md")
	if md_label.markdown_text.strip_edges().is_empty():
		md_label.markdown_text = EMBEDDED_BEGINNER_GUIDE

	content_hbox.add_child(md_label)


	# 目录项与对应 Markdown 锚点映射 (新手入门指南)
	var chapters: Array = [
		{"name": "一、游戏核心目标", "anchor": "#一游戏核心目标"},
		{"name": "二、组织架构与部门", "anchor": "#二组织架构与部门"},
		{"name": "三、遭遇刷新与安全屋", "anchor": "#三遭遇刷新与安全屋"},
		{"name": "四、遭遇战四大决策", "anchor": "#四遭遇战四大决策"},
		{"name": "五、遭遇战 2人动作规则", "anchor": "#五遭遇战2人动作规则"},
		{"name": "六、人际关系与红绿线", "anchor": "#六人际关系与红绿线"},
		{"name": "七、审讯室与情报收集", "anchor": "#七审讯室与情报收集"},
		{"name": "💡 新手通关小贴士", "anchor": "#新手通关小贴士"}
	]






	# 填充左侧目录按钮
	for item in chapters:
		var btn := Button.new()
		btn.text = " " + item["name"]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(200, 32)
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88))
		
		# 自定义侧边栏按钮 hover 样式
		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color(0.12, 0.12, 0.18, 0.5)
		btn_style.corner_radius_top_left = 4
		btn_style.corner_radius_top_right = 4
		btn_style.corner_radius_bottom_left = 4
		btn_style.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override("normal", btn_style)

		var hover_style := btn_style.duplicate()
		hover_style.bg_color = Color(0.3, 0.25, 0.12, 0.7)
		hover_style.border_width_left = 2
		hover_style.border_color = Color(0.98, 0.88, 0.55)
		btn.add_theme_stylebox_override("hover", hover_style)

		var chap_name: String = item["name"]
		btn.pressed.connect(func():
			md_label.scroll_to_anchor(chap_name)
		)
		toc_list.add_child(btn)


	var back_btn := Button.new()
	back_btn.text = "◀  返回主菜单"
	back_btn.custom_minimum_size = Vector2(220, 44)
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

	var panel_size := Vector2(480, 520)
	panel.size = panel_size
	var vp := get_viewport_rect().size
	panel.position = Vector2((vp.x - panel_size.x) * 0.5, (vp.y - panel_size.y) * 0.5)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "💬  联系作者"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(0.98, 0.88, 0.55))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	var bili_btn := Button.new()
	bili_btn.text = "B站：@Ka3m"
	bili_btn.custom_minimum_size = Vector2(400, 44)
	bili_btn.add_theme_font_size_override("font_size", 15)
	bili_btn.pressed.connect(func():
		OS.shell_open("https://space.bilibili.com/99815426")
	)
	vbox.add_child(bili_btn)

	var tip_lbl := Label.new()
	tip_lbl.text = "如果这个项目对你有帮助，欢迎投喂支持！"
	tip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip_lbl.add_theme_font_size_override("font_size", 14)
	tip_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	vbox.add_child(tip_lbl)

	# 真实赞赏码图片展示（带金色精致外框）
	var qr_frame := PanelContainer.new()
	qr_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	qr_frame.add_theme_stylebox_override("panel", _make_panel_style())
	vbox.add_child(qr_frame)

	var qr_rect := TextureRect.new()
	qr_rect.texture = _get_qr_texture()
	qr_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE

	qr_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr_rect.custom_minimum_size = Vector2(220, 220)
	qr_frame.add_child(qr_rect)

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

const EMBEDDED_BEGINNER_GUIDE: String = """# 辛迪加新手入门指南

欢迎来到 **不朽辛迪加** 解密与推演战场！
本指南将帮助你快速掌握游戏的核心机制与运作原理，轻松开始你的黑帮调查之旅。

---

## 一、 游戏核心目标

你是一名对抗黑帮组织的特工，你的最终目标是**瓦解整个不朽辛迪加组织**。

- **收集情报**：在各种遭遇战中对黑帮成员进行审讯或商谈，收集四大部门的情报。
- **解锁藏身处**：当某个部门的情报达到 **100%** 时，即可锁定该部门藏身处位置并启动终极突袭。
- **剿灭首领**：直击部门首领，将其逐一拿下！

---

## 二、 组织架构与部门

不朽辛迪加组织共有 **17 名成员**，其中 **14 名成员** 参与主解密面板的活动（分布在 **4 大部门** 与自由人中），剩下的 **3 名成员** 留存在替补池中：

1. **🚚 运输部**：负责组织的物资运输与通货流动。
2. **🛡️ 防御部**：负责组织的工事防守与装备强化。
3. **🔬 研究部**：负责高科技隐匿道具与加密研究。
4. **⚖️ 调停部**：负责组织内务调停与外围干预。

### 成员身份与特殊规则
- **首领**：各部门的最高负责人（带冠标记），控制该部门的藏身处。
- **下属**：部门旗下的正式成员。
- **自由人**：暂时不属于任何部门的游荡成员（0 星级）。
- **👥 14人上阵与3人替补**：主解密面板上固定有 14 名成员活动。当面板上的成员因商谈或背叛被“逐出/退出组织”时，替补池（3人）中的成员会随机替补登场。
- **👑 首领参战条件**：首领极其谨慎！只有当该部门旗下**下属的星级累计达到 3 星或以上**时，首领才有可能亲自参与遭遇战。
- **🔒 特殊保护人物**：**格拉维奇** 属于特殊保留人物，在开局初始盘面的 14 张成员卡中**绝对不会出现**，而是保留在替补池中。

---

## 三、 遭遇刷新与安全屋

### 1. 遭遇战生成规则
- 每回合系统会为你安排 **最多 3 场遭遇战**。
- **部门刷新规律**：在每回合的遭遇战队列中，**🔬 研究部** 与 **⚖️ 调停部** 为 **必定出现** 的部门；而 **🚚 运输部** 与 **🛡️ 防御部** 则为 **二选一随机出现**。

### 2. 🛡️ 安全屋屏蔽与衰减机制
- **安全屋屏蔽**：当某个部门的情报累计达到 **100%** 并解锁安全屋后，**该部门在接下来的回合中将被暂时屏蔽，不会再触发其遭遇战**。这能帮助你集中精力清剿其他部门！
- **情报衰减警告**：安全屋解锁后，你每**成功完成 1 次遭遇战**，该部门的安全屋倒计时就会推进 1 次。若成功完成 **3 次遭遇战** 后仍未发起突袭，该部门的情报将自动衰减 10%（降至 90%）。

---

## 四、 遭遇战四大决策

面对出场的成员，你需要逐一做出以下决策：

### 1. 🔍 审讯
- **原理**：将该成员抓入审讯室关押。
- **效果**：成员在狱中每回合持续提供情报；出狱时该成员星级下降 1 星。

### 2. 🕊️ 释放
- **原理**：当场无条件释放该成员。
- **效果**：成员安全离开，星级保持不变，不提供额外情报。

### 3. ⚔️ 背叛 —— 2人遭遇战可用
利用两名出场成员之间的矛盾引发斗争。可能出现的结果如下：

| 背叛选项 | 触发条件 | 主要效果 |
|---------|---------|---------|
| **窃取情报** | 有目标时 | 获取遭遇部门情报 +6；与目标变为**敌对 (红线)** |
| **窃取阶级** | 目标拥有星级 | 吸取目标星级，目标降为 0 星自由人；若执行者为自由人则加入目标部门；变为**敌对 (红线)** |
| **逐出组织** | 有目标时 | 将目标彻底驱逐出辛迪加，触发替补成员补位 |
| **打压宿敌** | 双方属于不同部门 | 本部门全体 +1 星，对方部门全体 -1 星；双方变**敌对 (红线)** |
| **摧毁对方装备** | 双方属于不同部门 | 摧毁对方部门全体成员的所有装备；双方变**敌对 (红线)** |
| **篡位** | 下属对抗同部门首领 | 下属反抗夺权，直接登上本部门首领宝座；双方变**敌对 (红线)** |

### 4. 🤝 商谈 (Bargain) —— 仅剩1人时可用
与最后一名成员达成暗中交易。可能出现的结果如下：

| 商谈选项 | 触发条件 | 主要效果 |
|---------|---------|---------|
| **获取情报** | 始终可用 | 按星级获取遭遇部门情报（3星=8、2星=6、1星=4、0星自由人=2） |
| **获取大量情报** | 始终可用 | 直接获得遭遇部门情报 +20 |
| **结盟** | 盘上有已揭示非信任成员 | 与目标建立**信任 (绿线)**；目标若为自由人则吸收加入本部门 |
| **退出组织** | 始终可用 | 执行者自己主动脱离辛迪加，触发替补成员补位 |
| **调动职位** | 存在同星同职跨部门成员 | 与跨部门同星级同职务的成员互换部门位置 |
| **化解部门恩怨** | 执行者非自由人 且 本部门有死敌 | 移除本部门全体成员的所有敌对关系 |
| **摧毁部门装备** | 执行者非自由人 | 清空本部门全体成员的所有装备 |
| **劫狱** | 审讯室有在押囚犯 | 一次性提前释放审讯室所有囚犯，并直接结算结算全部剩余情报 |
| **获取道具** | 始终可用 | 掉落传奇装备、通货物品、加密物品、地图或圣甲虫 |

---

## 五、 遭遇战2人动作规则

当遭遇战剩下 2 人时，卡牌上方会自动为你判定亮出 **⚔ 处决** 还是 **☠ 背叛** 选项。

不需要记忆繁琐规则！只需记住 **3 条黄金口诀** 即可秒懂：

1. 💚 **只要有【信任绿线】** $\rightarrow$ **永远是 ☠ 背叛**（盟友间均可背叛）。
2. 👑 **同部门【上下级关系】** $\rightarrow$ **首领选 ⚔ 处决，下属选 ☠ 背叛**（首领掌控生杀，下属反抗下压）。
3. ⚔️ **其他所有情况** $\rightarrow$ **一律是 ⚔ 处决**（死敌、平级无关系、跨部门无关系等）。

### 🎯 2人动作速查表
| 两人关系状况 | 点击首领/左卡牌 | 点击下属/右卡牌 | 一句话规则说明 |
|:---|:---:|:---:|:---|
| **拥有信任关系 (绿线)** | **☠ 背叛** | **☠ 背叛** | 盟友之间，任意一方均可选择背叛 |
| **同部门上下级 (无绿线)** | **⚔ 处决** | **☠ 背叛** | 首领处决下属，下属背叛首领 |
| **同部门平级 / 仇敌 (红线)** | **⚔ 处决** | **⚔ 处决** | 无信任关系，直接武力处决 |
| **跨部门成员 (无绿线)** | **⚔ 处决** | **⚔ 处决** | 异部门无信任关系，直接武力处决 |

---

## 六、 人际关系与红绿线

- **💚 信任关系 (绿线)**：成员之间互相认可。在后续遭遇战中更有可能结伴出场，提供更多组合操作机会。
- **❤️ 敌对关系 (红线)**：成员之间水火不容。在遭遇战中更容易触发打压、剥夺和篡位等激烈效果。

---

## 七、 审讯室与情报收集

1. **审讯室机制**：最多同时关押 3 名囚犯，按刑期自动倒计时。
2. **情报结算**：囚犯在押期间，每回合按其星级自动生成对应部门情报。
3. **安全屋大捷**：部门情报达 100% 即锁定藏身处，等待你的终极清剿！

### ⚖️ 关键规则对比：审讯减刑期 vs 安全屋衰减
- **审讯囚犯减刑期**：只需要**参与 1 次遭遇战**即可（不论该场遭遇战最终是否成功完成，只要参与了一次遭遇战，狱中囚犯的剩余刑期就会减少 1 回合）。
- **安全屋情报衰减**：需要**成功完成 1 次遭遇战**才计入有效回合（安全屋解锁后，只有成功完成 3 次遭遇战后仍未突袭，情报才会衰减 10%）。

---

## 💡 新手通关小贴士

1. **优先提升星级**：利用背叛或商谈帮助关键成员升星，高星级成员审讯时能提供成倍的情报！
2. **巧用审讯室**：审讯室满员时，可以通过商谈中的“劫狱”选项一次性释放全部囚犯并直接结算所有剩余情报。
3. **利用关系网络**：多建立信任与敌对关系，能大幅增加后续遭遇战参战的人数，让你的决策效率翻倍！
4. **注意减刑与衰减区别**：囚犯减刑只需“参与遭遇战”，而安全屋衰减需要“成功完成遭遇战”，合理利用这一时间差可以更稳健地规划你的突袭顺序！
"""
