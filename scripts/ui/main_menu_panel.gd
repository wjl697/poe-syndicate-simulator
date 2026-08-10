class_name MainMenuPanel
extends Control

## 主菜单界面：位于品牌加载动画与模式选择大厅之间
## 提供模式选择、百科大全、联系作者、退出 四个入口

signal mode_selection_requested
signal encyclopedia_requested
signal contact_requested
signal exit_requested

var _tex_bg := preload("res://辛迪加素材/界面UI/开局背景.png")
var _tex_btn := preload("res://辛迪加素材/界面UI/按钮2.png")
var _font_noto := preload("res://辛迪加素材/字体/NotoSansSC-VariableFont_wght.ttf")

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()

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

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.custom_minimum_size = vp_size
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 24)
	add_child(root)

	# 2. 标题
	var title_lbl := Label.new()
	title_lbl.text = "辛 迪 加"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 52)
	title_lbl.add_theme_color_override("font_color", Color(0.98, 0.88, 0.55))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	title_lbl.add_theme_constant_override("shadow_offset_x", 3)
	title_lbl.add_theme_constant_override("shadow_offset_y", 3)
	root.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "— 主 菜 单 —"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 18)
	sub_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	sub_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	sub_lbl.add_theme_constant_override("shadow_offset_x", 2)
	sub_lbl.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(sub_lbl)

	# 3. 垂直位置弹簧垫片：调高度控制按钮列上下位置 (值越大按钮越靠下)
	var btn_col_spacer := Control.new()
	btn_col_spacer.custom_minimum_size = Vector2(0, 630)
	root.add_child(btn_col_spacer)

	# 4. 选项按钮列 (垂直排列，居中放置)
	var btn_col := VBoxContainer.new()
	btn_col.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_col.add_theme_constant_override("separation", 1)
	root.add_child(btn_col)

	_add_menu_button(btn_col, "模式选择", _on_mode_selection_pressed)
	_add_menu_button(btn_col, "游戏百科", _on_encyclopedia_pressed)
	_add_menu_button(btn_col, "联系作者", _on_contact_pressed)
	_add_menu_button(btn_col, "退出程序", _on_exit_pressed)

func _add_menu_button(parent: Node, text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(260, 0)  # ← 调宽度：改 260 即可，按钮居中宽度变化而中心不变；高度保持内容自适应
	btn.add_theme_font_size_override("font_size", 18)
	var btn_font := FontVariation.new()
	btn_font.base_font = _font_noto
	btn_font.variation_embolden = 0.5   # ← 矢量加粗：0 常规 / 0.5 中粗 / 1.0 更粗（比 outline 伪加粗更自然）
	btn.add_theme_font_override("font", btn_font)
	btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	btn.add_theme_constant_override("shadow_offset_x", 2)
	btn.add_theme_constant_override("shadow_offset_y", 2)

	var btn_normal := StyleBoxTexture.new()
	btn_normal.texture = _tex_btn
	btn_normal.texture_margin_left = 28
	btn_normal.texture_margin_top = 10
	btn_normal.texture_margin_right = 28
	btn_normal.texture_margin_bottom = 10

	var btn_hover := btn_normal.duplicate()
	btn_hover.modulate_color = Color(1.2, 1.15, 0.95, 1.0)

	var btn_pressed := btn_normal.duplicate()
	btn_pressed.modulate_color = Color(0.8, 0.75, 0.7, 1.0)

	btn.add_theme_stylebox_override("normal", btn_normal)
	btn.add_theme_stylebox_override("hover", btn_hover)
	btn.add_theme_stylebox_override("pressed", btn_pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(callback)
	parent.add_child(btn)

func _on_mode_selection_pressed():
	mode_selection_requested.emit()

func _on_encyclopedia_pressed():
	encyclopedia_requested.emit()

func _on_contact_pressed():
	contact_requested.emit()

func _on_exit_pressed():
	exit_requested.emit()
