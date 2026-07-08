class_name CardActionOverlay
extends Control

## 卡片操作覆盖层 — 放大显示选中成员，两侧显示操作后果
const ActionLogic = preload("res://scripts/gameplay/action_logic.gd")

signal action_chosen(member_name: String, action: int)

var _member_data = null
var _bg: ColorRect                 # 全屏暗色背景
var _card_container: Control       # 中央卡片区域
var _portrait: Sprite2D            # 放大头像
var _card_bg: Sprite2D             # 卡片背景
var _card_halo: Sprite2D           # 光晕
var _card_name: Label              # 名字
var _card_info: Label              # 职位/部门
var _action_panels: Array = []     # 操作面板节点列表

# 纹理
var _tex_bg := preload("res://辛迪加素材/人物背景.png")
var _tex_halo_mem := preload("res://辛迪加素材/成员光晕.png")
var _tex_halo_lead := preload("res://辛迪加素材/首领光晕.png")
var _tex_btn_bg := preload("res://辛迪加素材/选项背板.png")
var _tex_btn_main := preload("res://辛迪加素材/按钮.png")

func _ready():
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# 暗色背景 - 
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 0.5) 
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

var _dismiss_tw: Tween = null

func show_member_actions(member, actions: Array, screen_pos: Vector2):
	_member_data = member
	if _dismiss_tw and _dismiss_tw.is_valid():
		_dismiss_tw.kill()
		_dismiss_tw = null
	_clear_content()

	# 恢复固定高度设置 (缩小后约 236 像素)
	var center := screen_pos
	var slot_w := 194.0
	var slot_h := 236.0 # 黑色底板高度（原314 * 0.75）
	var frame_size := _tex_btn_bg.get_size() * 0.75
	
	var vp_size := get_viewport_rect().size
	
	# --- Y轴边界限制 ---
	var min_y: float = slot_h * 0.5 + 20.0
	var max_y: float = vp_size.y - slot_h * 0.5 - 20.0
	center.y = clampf(center.y, min_y, max_y)
	
	# --- X轴边界限制（保证左右面板不超出屏幕）---
	var min_x: float = slot_w * 1.5 + 20.0  # 291 + 20 = 311
	var max_x: float = vp_size.x - slot_w * 1.5 - 20.0  # 1920 - 311 = 1609
	center.x = clampf(center.x, min_x, max_x)

	# --- 第一层：最底层透明黑色面板 (三连板，卡片居中，两侧各一格) ---
	var base_bg := ColorRect.new()
	base_bg.color = Color(0, 0, 0, 0.88)
	base_bg.size = Vector2(slot_w * 3, slot_h)
	base_bg.position = Vector2(center.x - slot_w * 1.5, center.y - slot_h * 0.5)
	base_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(base_bg)
	_action_panels.append(base_bg)

	# --- 第二层：选项背板 (不修改尺寸，直接居中并上移 20 像素) ---
	var middle_frame := TextureRect.new()
	middle_frame.texture = _tex_btn_bg
	middle_frame.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	middle_frame.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	middle_frame.size = frame_size
	middle_frame.scale = Vector2(0.75, 0.75)
	middle_frame.position = center - frame_size * 0.5 + Vector2(0, -11)
	middle_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(middle_frame)
	_action_panels.append(middle_frame)

	# --- 第三层：卡片内容容器 (对齐到中心，同步上移 15 像素) ---
	_card_container = Control.new()
	_card_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card_container)
	
	# 添加不可见的拦截遮罩，防止鼠标穿透点到后面的卡片
	var card_blocker := ColorRect.new()
	card_blocker.color = Color(0, 0, 0, 0)
	card_blocker.size = Vector2(225, 285)
	card_blocker.position = center - Vector2(113, 143)
	card_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_card_container.add_child(card_blocker)

	# 统一上移量
	var sync_offset := Vector2(0, -11)
	
	# 计算让卡片刚好"填满"背板高度（188 像素）的缩放值（原250 * 0.75）
	var card_native_size := _tex_bg.get_size()
	var auto_scale_f := 188.0 / card_native_size.y
	var card_scale := Vector2(auto_scale_f, auto_scale_f)

	# 卡片背景 (单独下移 11 像素)
	_card_bg = Sprite2D.new()
	_card_bg.texture = _tex_bg
	_card_bg.position = center + Vector2(0, 11) + sync_offset 
	_card_bg.scale = card_scale
	_card_container.add_child(_card_bg)

	# 光晕 (与 member_card.gd 保持一致的缩放与 Y 轴偏移比例)
	_card_halo = Sprite2D.new()
	_card_halo.texture = _tex_halo_lead if member.is_leader else _tex_halo_mem
	_card_halo.position = _card_bg.position + Vector2(0, _tex_bg.get_size().y * auto_scale_f * MemberCard.HALO_Y_OFFSET_RATIO)
	_card_halo.scale = card_scale * MemberCard.HALO_SCALE_MULT
	_card_container.add_child(_card_halo)

	# 头像 (与 member_card.gd 保持一致的缩放与 Y 轴偏移比例)
	_portrait = Sprite2D.new()
	var ptex: Texture2D = load(member.portrait_path)
	if ptex:
		_portrait.texture = ptex
		var bg_size := _tex_bg.get_size() * auto_scale_f
		var p_size: Vector2 = ptex.get_size()
		var fit: float = minf(bg_size.x * MemberCard.PORTRAIT_FIT_SCALE / p_size.x, bg_size.y * MemberCard.PORTRAIT_FIT_SCALE / p_size.y)
		_portrait.scale = Vector2(fit, fit)
	_portrait.position = _card_bg.position + Vector2(0, _tex_bg.get_size().y * auto_scale_f * MemberCard.PORTRAIT_Y_OFFSET_RATIO)
	_card_container.add_child(_portrait)

	# --- 新增：部门标志 (左上角) ---
	var div_icon_path := ""
	match member.division:
		GameManager.Division.TRANSPORT: div_icon_path = "res://辛迪加素材/运输部角标.png"
		GameManager.Division.FORTIFICATION: div_icon_path = "res://辛迪加素材/防卫部角标.png"
		GameManager.Division.RESEARCH: div_icon_path = "res://辛迪加素材/科研部角标.png"
		GameManager.Division.INTERVENTION: div_icon_path = "res://辛迪加素材/调停部角标.png"
	
	if div_icon_path != "" and FileAccess.file_exists(div_icon_path):
		var div_sprite := Sprite2D.new()
		div_sprite.texture = load(div_icon_path)
		div_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # 缩小时抗锯齿
		div_sprite.position = _card_bg.position + MemberCard.BADGE_BASE_POS * auto_scale_f
		div_sprite.scale = Vector2(MemberCard.BADGE_BASE_SCALE, MemberCard.BADGE_BASE_SCALE) * auto_scale_f
		div_sprite.modulate.a = 0.8
		_card_container.add_child(div_sprite)

	# --- 新增：星级标志 (右上角) ---
	var rank_icon_path := ""
	match member.rank:
		1: rank_icon_path = "res://辛迪加素材/一星等级.png"
		2: rank_icon_path = "res://辛迪加素材/二星等级.png"
		3: rank_icon_path = "res://辛迪加素材/三星等级.png"
	
	if rank_icon_path != "" and FileAccess.file_exists(rank_icon_path):
		var rank_sprite := Sprite2D.new()
		rank_sprite.texture = load(rank_icon_path)
		rank_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # 缩小时抗锯齿
		rank_sprite.position = _card_bg.position + MemberCard.STAR_BASE_POS * auto_scale_f
		rank_sprite.scale = Vector2(MemberCard.STAR_BASE_SCALE, MemberCard.STAR_BASE_SCALE) * auto_scale_f
		
		# 为三星图标单独向左上微调，注意带上全局卡片缩放系数(auto_scale_f)
		if member.rank == 3:
			rank_sprite.position += Vector2(-22, -18) * auto_scale_f
			
		rank_sprite.modulate.a = 0.8
		_card_container.add_child(rank_sprite)

	# 文字信息 (完全参考 member_card.gd 比例对齐)
	_card_name = Label.new()
	_card_name.text = member.member_name
	_card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 字号从 16 加大到 20 以匹配主卡片的等效缩放
	_card_name.add_theme_font_size_override("font_size", 20)
	_card_name.add_theme_color_override("font_color", Color(0, 0, 0)) # 改为纯黑色
	
	var bg_size_scaled := _tex_bg.get_size() * auto_scale_f
	_card_name.size = Vector2(bg_size_scaled.x * 0.8, 30)
	_card_name.position = _card_bg.position + Vector2(-bg_size_scaled.x * 0.4, bg_size_scaled.y * 0.2)
	_card_container.add_child(_card_name)

	_card_info = Label.new()
	# 既然有了图标，下方仅显示职位描述（部长/首领等）
	var role_text := ""
	if member.is_leader:
		role_text = "首领"
	_card_info.text = role_text
	_card_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_info.add_theme_font_size_override("font_size", 12)
	_card_info.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
	_card_info.size = Vector2(bg_size_scaled.x * 0.8, 22)
	_card_info.position = _card_bg.position + Vector2(-bg_size_scaled.x * 0.4, bg_size_scaled.y * 0.2 + 30)
	_card_container.add_child(_card_info)

	# --- 操作按钮分布（固定左右展开）---
	_build_action_panels(actions, center)

	modulate = Color(1, 1, 1, 0)
	visible = true
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.25).set_ease(Tween.EASE_OUT)

func _build_action_panels(actions: Array, center: Vector2):
	var slot_w := 194.0
	var slot_h := 233.0
	var btn_w := 105.0
	var btn_h := 29.0

	# 固定：左侧面板 offset=-1.5，右侧面板 offset=0.5
	var side_offsets: Array = [-1.5, 0.5]

	var panel_idx := 0
	for action in actions:
		if action == GameManager.ActionType.RELEASE:
			var btn_pos := center + Vector2(-btn_w * 0.5, slot_h * 0.5 - btn_h + 7)
			_create_action_button(action, btn_pos, btn_w, btn_h)
		else:
			if panel_idx >= side_offsets.size():
				# 侧栏最多两项，超出则跳过，避免说明文字和按钮重叠。
				continue
			var slot_offset_x: float = side_offsets[panel_idx]
			var panel_pos := center + Vector2(slot_w * slot_offset_x, -slot_h * 0.5)
			_create_side_panel(action, panel_pos, slot_w, slot_h, btn_w, btn_h)
			panel_idx += 1

func _create_side_panel(action: int, pos: Vector2, w: float, h: float, btn_w: float, btn_h: float):
	# 不再创建独立的背景，因为第一层透黑面板已经覆盖了这些区域

	# 文本说明 — 使用 Label 以支持原生垂直居中
	var desc := _get_detailed_description(action)
	var desc_label := Label.new()
	desc_label.text = desc
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6))
	
	# 固定尺寸 = 面板可用区域（去掉按钮和留白），Label 会在此范围内垂直居中文字
	var available_h := h - btn_h - 10.0
	desc_label.size = Vector2(w - 22, available_h)
	desc_label.position = pos + Vector2(11, 5)
	add_child(desc_label)
	_action_panels.append(desc_label)

	# 底部操作按钮
	var btn_pos := pos + Vector2((w - btn_w) * 0.5, h - btn_h - 1)
	_create_action_button(action, btn_pos, btn_w, btn_h)

func _create_action_button(action: int, pos: Vector2, w: float, h: float):
	var btn := Button.new()
	btn.position = pos
	btn.size = Vector2(w, h)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.text = ActionLogic.get_action_button_text(GameManager, _member_data, action)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.8)) # 淡金色文字

	# Use texture StyleBox
	var style := StyleBoxTexture.new()
	style.texture = _tex_btn_main
	# Set margins for 9-patch (assuming default UI style margins)
	style.texture_margin_left = 6
	style.texture_margin_right = 6
	style.texture_margin_top = 6
	style.texture_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.modulate_color = Color(1.2, 1.2, 1.2) # Brighten on hover
	btn.add_theme_stylebox_override("hover", hover)
	
	var pressed := style.duplicate()
	pressed.modulate_color = Color(0.8, 0.8, 0.8) # Darken on press
	btn.add_theme_stylebox_override("pressed", pressed)
	
	var act_copy: int = action
	btn.pressed.connect(func(): 
		_on_action_pressed(act_copy)
	)

	add_child(btn)
	_action_panels.append(btn)

func _get_detailed_description(action: int) -> String:
	return ActionLogic.get_overlay_description(GameManager, _member_data, action)

func _on_action_pressed(action: int):
	if _member_data:
		action_chosen.emit(_member_data.member_name, action)
	dismiss()

func dismiss():
	if not visible: return
	if _dismiss_tw and _dismiss_tw.is_valid():
		_dismiss_tw.kill()
		_dismiss_tw = null
	visible = false
	modulate.a = 0.0
	_clear_content()

func is_mouse_over_content() -> bool:
	if not visible or _action_panels.is_empty(): return false
	var mpos = get_global_mouse_position()
	# 完全以第一层的三连黑色透明方框 (base_bg) 的实际边框为准
	# 不再遍历其他带有透明边缘的图片控件（如 middle_frame 的全尺寸边框）
	var base_bg = _action_panels[0] as Control
	return base_bg.get_global_rect().has_point(mpos)

func _process(_delta: float):
	if not visible:
		return
	if not is_mouse_over_content():
		dismiss()


func _clear_content():
	# 清除动态创建的子节点（保留 _bg）
	for child in get_children():
		if child != _bg:
			child.queue_free()
	_action_panels.clear()
	_card_container = null
	_portrait = null
	_card_bg = null
	_card_halo = null
	_card_name = null
	_card_info = null
