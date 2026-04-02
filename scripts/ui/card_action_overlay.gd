class_name CardActionOverlay
extends Control

## 卡片操作覆盖层 — 放大显示选中成员，两侧显示操作后果

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

	# 恢复固定高度设置 (314 像素)
	var center := screen_pos
	var slot_w := 258.0
	var slot_h := 314.0 # 黑色底板高度固定为 314
	var frame_size := _tex_btn_bg.get_size()
	
	var vp_size := get_viewport_rect().size
	
	# --- Y轴边界限制 ---
	# 防止面板(尤其是自由人面板)超出屏幕底部或顶部
	var min_y: float = slot_h * 0.5 + 20.0
	var max_y: float = vp_size.y - slot_h * 0.5 - 20.0
	center.y = clampf(center.y, min_y, max_y)
	
	var layout_mode := 0 # 0: 居中, 1: 靠左(面板全在右边), 2: 靠右(面板全在左边)
	if center.x - slot_w * 1.5 < 20:
		layout_mode = 1
	elif center.x + slot_w * 1.5 > vp_size.x - 20:
		layout_mode = 2

	# --- 第一层：最底层透明黑色面板 (三连板) ---
	var base_bg := ColorRect.new()
	base_bg.color = Color(0, 0, 0, 0.88)
	base_bg.size = Vector2(slot_w * 3, slot_h)
	
	var bg_start_x := 0.0
	if layout_mode == 0:
		bg_start_x = center.x - slot_w * 1.5
	elif layout_mode == 1:
		bg_start_x = center.x - slot_w * 0.5
	elif layout_mode == 2:
		bg_start_x = center.x - slot_w * 2.5
		
	base_bg.position = Vector2(bg_start_x, center.y - slot_h * 0.5)
	base_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(base_bg)
	_action_panels.append(base_bg)

	# --- 第二层：选项背板 (不修改尺寸，直接居中并上移 20 像素) ---
	var middle_frame := TextureRect.new()
	middle_frame.texture = _tex_btn_bg
	middle_frame.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	middle_frame.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	middle_frame.size = frame_size
	middle_frame.position = center - frame_size * 0.5 + Vector2(0, -15)
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
	card_blocker.size = Vector2(300, 380)
	card_blocker.position = center - Vector2(150, 190)
	card_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_card_container.add_child(card_blocker)

	# 统一上移量
	var sync_offset := Vector2(0, -15)
	
	# 计算让卡片刚好“填满”背板高度（250 像素）的缩放值
	var card_native_size := _tex_bg.get_size()
	var auto_scale_f := 250.0 / card_native_size.y
	var card_scale := Vector2(auto_scale_f, auto_scale_f)

	# 卡片背景 (单独下移 15 像素)
	_card_bg = Sprite2D.new()
	_card_bg.texture = _tex_bg
	_card_bg.position = center + Vector2(0, 15) + sync_offset 
	_card_bg.scale = card_scale
	_card_container.add_child(_card_bg)

	# 光晕
	_card_halo = Sprite2D.new()
	_card_halo.texture = _tex_halo_lead if member.is_leader else _tex_halo_mem
	_card_halo.position = _card_bg.position
	_card_halo.scale = card_scale
	_card_container.add_child(_card_halo)

	# 头像
	_portrait = Sprite2D.new()
	var ptex: Texture2D = load(member.portrait_path)
	if ptex:
		_portrait.texture = ptex
		var bg_size := _tex_bg.get_size() * auto_scale_f
		var p_size: Vector2 = ptex.get_size()
		var fit: float = minf(bg_size.x * 0.55 / p_size.x, bg_size.y * 0.85 / p_size.y)
		_portrait.scale = Vector2(fit, fit)
	_portrait.position = _card_bg.position + Vector2(0, -10)
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
		# 计算在纸张左上角的位置 (相对于纸张中心)
		var offset_val := 80.0 * auto_scale_f / 0.3 # 动态单位
		div_sprite.position = _card_bg.position + Vector2(-40, -50) * (auto_scale_f / 0.3)
		div_sprite.scale = Vector2(0.2, 0.2) * (auto_scale_f / 0.3)
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
		# 计算在纸张右上角的位置
		rank_sprite.position = _card_bg.position + Vector2(50, -50) * (auto_scale_f / 0.3)
		rank_sprite.scale = Vector2(0.2, 0.2) * (auto_scale_f / 0.3)
		rank_sprite.modulate.a = 0.8
		_card_container.add_child(rank_sprite)

	# 文字信息 (适配高度后的偏移)
	_card_name = Label.new()
	_card_name.text = member.member_name
	_card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_name.add_theme_font_size_override("font_size", 22)
	_card_name.add_theme_color_override("font_color", Color(0, 0, 0)) # 改为纯黑色
	# 已移除黑色文字阴影
	_card_name.size = Vector2(250, 40)
	_card_name.position = center + Vector2(-125, 65) + sync_offset
	_card_container.add_child(_card_name)

	_card_info = Label.new()
	# 既然有了图标，下方仅显示职位描述（部长/首领等）
	var role_text := ""
	if member.is_leader:
		role_text = "首领"
	_card_info.text = role_text
	_card_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_info.add_theme_font_size_override("font_size", 16)
	_card_info.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
	_card_info.size = Vector2(250, 30)
	_card_info.position = center + Vector2(-125, 90) + sync_offset
	_card_container.add_child(_card_info)

	# --- 操作按钮分布 (保持 258 像素的格子逻辑) ---
	_build_action_panels(actions, center, layout_mode)

	modulate = Color(1, 1, 1, 0)
	visible = true
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.25).set_ease(Tween.EASE_OUT)

func _build_action_panels(actions: Array, center: Vector2, layout_mode: int):
	var slot_w := 258.0
	var slot_h := 310.0
	var btn_w := 140.0
	var btn_h := 38.0

	var panel_idx := 0
	for action in actions:
		if action == GameManager.ActionType.RELEASE:
			var btn_pos := center + Vector2(-btn_w * 0.5, slot_h * 0.5 - btn_h + 7)
			_create_action_button(action, btn_pos, btn_w, btn_h)
		else:
			var slot_offset_x := 0.0
			if layout_mode == 0:
				slot_offset_x = -1.5 if action == GameManager.ActionType.INTERROGATE else 0.5
			elif layout_mode == 1:
				slot_offset_x = 0.5 if panel_idx == 0 else 1.5
			elif layout_mode == 2:
				slot_offset_x = -1.5 if panel_idx == 0 else -2.5
				
			var panel_pos := center + Vector2(slot_w * slot_offset_x, -slot_h * 0.5)
			_create_side_panel(action, panel_pos, slot_w, slot_h, btn_w, btn_h)
			panel_idx += 1

func _create_side_panel(action: int, pos: Vector2, w: float, h: float, btn_w: float, btn_h: float):
	# 不再创建独立的背景，因为第一层透黑面板已经覆盖了这些区域

	# 文本说明
	var desc := _get_detailed_description(action)
	var desc_label := RichTextLabel.new()
	desc_label.bbcode_enabled = true
	desc_label.fit_content = true
	desc_label.custom_minimum_size = Vector2(w - 30, 0)
	
	# 设置字体颜色和居中
	desc_label.add_theme_font_size_override("normal_font_size", 16)
	desc_label.add_theme_color_override("default_color", Color(0.9, 0.8, 0.6))
	desc_label.text = "[center]" + desc + "[/center]"
	
	# 置于该区域的中间靠上
	desc_label.position = pos + Vector2(15, (h - btn_h - 20) * 0.5 - 25)
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
	btn.text = GameManager.get_action_name(action)
	btn.add_theme_font_size_override("font_size", 17)
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
	if _member_data == null:
		return ""
	var name: String = _member_data.member_name
	var rank: int = _member_data.rank
	var div_name: String = GameManager.DIVISION_NAMES.get(_member_data.division, "无") if _member_data.division != GameManager.Division.NONE else "无"

	match action:
		GameManager.ActionType.INTERROGATE:
			var intel: float = GameManager.INTEL_PER_RANK.get(rank, 0.10)
			return name + " 被囚禁 " + str(GameManager.PRISON_DURATION) + " 回合。\n" + div_name + " 情报每回合 +" + str(int(intel * 100)) + "%。\n释放后等级 -1"
		GameManager.ActionType.EXECUTE:
			return name + " 等级 +1\n入职当前部门，获得藏身处装备"
		GameManager.ActionType.BARGAIN:
			return name + " 提供一次性奖励\n不改变棋盘状态"
		GameManager.ActionType.BETRAY:
			return name + " 与另一名成员互换部门\n建立宿敌关系"
		GameManager.ActionType.RELEASE:
			return "释放 " + name + "\n不改变棋盘"
	return ""

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
