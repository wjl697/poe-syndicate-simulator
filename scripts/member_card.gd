class_name MemberCard
extends Node2D

## 成员卡片组件 — 显示成员头像、光晕、星级、名称

signal card_clicked(member_name: String)
signal card_hovered(member_name: String)
signal card_unhovered(member_name: String)

var member_data = null  # GameManager.MemberState reference

# 子节点
var halo_sprite: Sprite2D
var bg_sprite: Sprite2D
var portrait_sprite: Sprite2D
var badge_sprite: Sprite2D
var star_sprite: Sprite2D
var name_label: Label
var prison_icon: Sprite2D
var progress_bg: Sprite2D
var progress_bar: TextureProgressBar
var prison_turn_badge: Sprite2D
var prison_turn_label: Label
var _hit_control: Control
var _highlight_tween: Tween = null
var _progress_hover_rect: Rect2 = Rect2()
var _progress_tooltip_text: String = ""
var _tooltip_panel: PanelContainer = null
static var _shared_prison_font_size: int = -1  # 类级别共享，所有实例只计算一次

# 预加载纹理
var _tex_bg        := preload("res://辛迪加素材/人物背景.png")
var _tex_halo_mem  := preload("res://辛迪加素材/成员光晕.png")
var _tex_halo_lead := preload("res://辛迪加素材/首领光晕.png")
var _tex_star1     := preload("res://辛迪加素材/一星等级.png")
var _tex_star2     := preload("res://辛迪加素材/二星等级.png")
var _tex_star3     := preload("res://辛迪加素材/三星等级.png")
var _tex_question  := preload("res://辛迪加素材/问号.png")
var _tex_prison_turn := preload("res://辛迪加素材/回合数.png")
var _font_main := preload("res://辛迪加素材/zt.ttf")

# 部门角标纹理
var _tex_badge_transport     := preload("res://辛迪加素材/运输部角标.png")
var _tex_badge_fortification := preload("res://辛迪加素材/防卫部角标.png")
var _tex_badge_research      := preload("res://辛迪加素材/科研部角标.png")
var _tex_badge_intervention  := preload("res://辛迪加素材/调停部角标.png")

const PRISON_TURN_BADGE_SCALE := 1.1

# ── 星级图标 & 部门角标 布局常量 ──
# 修改这里，悬停放大卡片会自动同步
const STAR_BASE_SCALE   := 1.2
const STAR_BASE_POS     := Vector2(160, -130)
const BADGE_BASE_SCALE  := 0.8
const BADGE_BASE_POS    := Vector2(-125, -145)

# ── 头像与光晕 布局常量（修改此处可同步影响操作面板内的预览卡片） ──
const PORTRAIT_FIT_SCALE := 1.0
const PORTRAIT_Y_OFFSET_RATIO := -0.04
const HALO_SCALE_MULT := 1.15
const HALO_Y_OFFSET_RATIO := -0.02
const PRISON_TURN_BADGE_ANCHOR_Y_RATIO := 0.64
const PRISON_TURN_BADGE_OFFSET := Vector2(0.0, -75.0) # x 向右，y 向下
const PRISON_TURN_TEXT_MAX_SIZE := 60
const PRISON_TURN_TEXT_MIN_SIZE := 16
const PRISON_TURN_TEXT_INNER_MARGIN := Vector2(18.0, 8.0) # 底图内边距，越小文字越“顶满”
const PRISON_TURN_TEXT_Y_OFFSET := -1.0
const PRISON_TURN_TEXT_COLOR := Color8(154, 131, 94)
const PRISON_TURN_TEXT_FAKE_BOLD_OUTLINE := 2
const PRISON_TURN_TEXT_FIT_TEMPLATE := "剩余88回合" # 统一按模板测字号，避免不同数字导致视觉高度不齐


func _ready():
	if not _tree_built:
		_build_tree()

var _tree_built: bool = false

func _build_tree():
	# --- 启用排序，让卡片内部零件不会和其他卡片交叉 ---
	y_sort_enabled = true
	# 确保卡片整体是一个封闭的 Z 层级
	z_as_relative = true
	z_index = 0

	# --- 人物背景底板（最底层） ---
	bg_sprite = Sprite2D.new()
	bg_sprite.texture = _tex_bg
	bg_sprite.z_index = 0
	add_child(bg_sprite)

	# --- 光晕（背景之上，头像之下） ---
	halo_sprite = Sprite2D.new()
	halo_sprite.texture = _tex_halo_mem
	halo_sprite.z_index = 1
	add_child(halo_sprite)

	# --- 头像 ---
	portrait_sprite = Sprite2D.new()
	portrait_sprite.z_index = 2
	add_child(portrait_sprite)

	# --- 部门角标 ---
	badge_sprite = Sprite2D.new()
	badge_sprite.z_index = 3
	badge_sprite.visible = false
	add_child(badge_sprite)

	# --- 星级 ---
	star_sprite = Sprite2D.new()
	star_sprite.texture = _tex_star1
	star_sprite.z_index = 4
	add_child(star_sprite)

	# --- 名称 ---
	name_label = Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 48)
	name_label.add_theme_color_override("font_color", Color(0, 0, 0))
	# 移除原本的黑色阴影，保证文字在纸张上更清晰
	name_label.remove_theme_color_override("font_shadow_color")
	name_label.z_index = 5
	add_child(name_label)

	# --- 入狱标记 ---
	prison_icon = Sprite2D.new()
	prison_icon.visible = false
	prison_icon.z_index = 6
	add_child(prison_icon)

	# --- 部门情报进度条 ---
	progress_bg = Sprite2D.new()
	progress_bg.texture = preload("res://辛迪加素材/进度条背板.png")
	progress_bg.z_index = 6
	progress_bg.visible = false
	add_child(progress_bg)

	progress_bar = TextureProgressBar.new()
	progress_bar.texture_under = preload("res://辛迪加素材/进度条.png")
	progress_bar.texture_progress = preload("res://辛迪加素材/进度条黄色.png")
	progress_bar.z_index = 7
	progress_bar.visible = false
	add_child(progress_bar)

	# --- 审讯剩余回合底图与文字 ---
	prison_turn_badge = Sprite2D.new()
	prison_turn_badge.texture = _tex_prison_turn
	prison_turn_badge.visible = false
	prison_turn_badge.z_index = 6
	add_child(prison_turn_badge)

	prison_turn_label = Label.new()
	prison_turn_label.visible = false
	prison_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 改为 TOP 配合手动计算位置，避免不同数字的外框不同导致中心点漂移
	prison_turn_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	prison_turn_label.z_index = 7
	prison_turn_label.add_theme_font_override("font", _font_main)
	prison_turn_label.add_theme_font_size_override("font_size", PRISON_TURN_TEXT_MAX_SIZE)
	prison_turn_label.add_theme_color_override("font_color", PRISON_TURN_TEXT_COLOR)
	# 同色描边模拟加粗，不产生阴影感。
	prison_turn_label.add_theme_color_override("font_outline_color", PRISON_TURN_TEXT_COLOR)
	prison_turn_label.add_theme_constant_override("outline_size", PRISON_TURN_TEXT_FAKE_BOLD_OUTLINE)
	prison_turn_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	prison_turn_label.add_theme_constant_override("shadow_offset_x", 0)
	prison_turn_label.add_theme_constant_override("shadow_offset_y", 0)
	add_child(prison_turn_label)

	# --- 点击区域 (使用 Control 完美处理遮挡关系) ---
	_hit_control = Control.new()
	_hit_control.size = Vector2(280, 380)
	_hit_control.position = Vector2(-140, -190)
	_hit_control.mouse_filter = Control.MOUSE_FILTER_STOP
	_hit_control.gui_input.connect(_on_control_gui_input)
	_hit_control.mouse_entered.connect(_on_mouse_entered)
	_hit_control.mouse_exited.connect(_on_mouse_exited)
	add_child(_hit_control)

	# --- 自定义悬浮情报提示面板 (跟随鼠标，黑底白字，类似于游戏原生) ---
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_panel.z_index = 20
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.9)
	style.set_content_margin_all(5)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	_tooltip_panel.add_theme_stylebox_override("panel", style)
	
	var t_label := Label.new()
	t_label.name = "Label"
	t_label.add_theme_font_size_override("font_size", 16)
	t_label.add_theme_color_override("font_color", Color.WHITE)
	t_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tooltip_panel.add_child(t_label)
	
	add_child(_tooltip_panel)

	# 确保类级别字号已计算（只在第一个实例时执行一次）
	if _shared_prison_font_size < 0:
		_shared_prison_font_size = _compute_prison_font_size()
	_tree_built = true

func setup(data) -> void:
	if not _tree_built:
		_build_tree()
	member_data = data
	update_display()

func update_display() -> void:
	if member_data == null:
		return

	var bg_size := Vector2.ZERO
	if bg_sprite.texture:
		bg_size = bg_sprite.texture.get_size()

	var is_hidden: bool = not member_data.is_revealed

	# 所有层级图片（背景、光晕、角标、星级、问号）都是 815x447 的预定位图层
	# 只需直接叠加，无需额外缩放或定位

	# 头像（451x450，需要缩放适配背景区域）
	if is_hidden:
		# 隐藏状态：显示问号（815x447 图层，与背景对齐）
		portrait_sprite.texture = _tex_question
		portrait_sprite.scale = Vector2.ONE
		portrait_sprite.position = Vector2.ZERO
	else:
		# 揭示状态：显示真实头像（451x450，需要缩放）
		var ptex = load(member_data.portrait_path)
		if ptex:
			portrait_sprite.texture = ptex
			if bg_sprite.texture:
				var p_size: Vector2 = ptex.get_size()
				var fit_scale: float = minf(bg_size.x * PORTRAIT_FIT_SCALE / p_size.x, bg_size.y * PORTRAIT_FIT_SCALE / p_size.y)
				portrait_sprite.scale = Vector2(fit_scale, fit_scale)
				portrait_sprite.position = Vector2(0, bg_size.y * PORTRAIT_Y_OFFSET_RATIO)

	# 光晕 — 815x447 图层，放大 1.35 倍并在 Y 轴微调向上对齐头像中心
	halo_sprite.texture = _tex_halo_lead if member_data.is_leader else _tex_halo_mem
	halo_sprite.scale = Vector2(HALO_SCALE_MULT, HALO_SCALE_MULT)
	halo_sprite.position = Vector2(0, bg_size.y * HALO_Y_OFFSET_RATIO)

	# 星级 — 815x447 图层，直接对齐背景
	if is_hidden or member_data.rank <= 0:
		star_sprite.visible = false
	else:
		star_sprite.visible = true
		match member_data.rank:
			1: star_sprite.texture = _tex_star1
			2: star_sprite.texture = _tex_star2
			3: star_sprite.texture = _tex_star3
		star_sprite.scale = Vector2(STAR_BASE_SCALE, STAR_BASE_SCALE)
		star_sprite.position = STAR_BASE_POS
		
		# 仅当是三星图标时，进行微调（向左上方偏移）
		if member_data.rank == 3:
			star_sprite.position += Vector2(-22, -18)
			
		star_sprite.modulate.a = 0.8

	# 部门角标 — 815x447 图层，直接对齐背景
	if member_data.division == GameManager.Division.NONE:
		badge_sprite.visible = false
	else:
		badge_sprite.visible = true
		var badge_tex: Texture2D = _get_badge_texture(member_data.division)
		if badge_tex:
			badge_sprite.texture = badge_tex
			badge_sprite.scale = Vector2(BADGE_BASE_SCALE, BADGE_BASE_SCALE)
			badge_sprite.position = BADGE_BASE_POS
			badge_sprite.modulate.a = 0.8

	# 名称 — 隐藏时显示「???」
	if is_hidden:
		name_label.text = ""
	else:
		name_label.text = member_data.member_name
	if bg_sprite.texture:
		name_label.position = Vector2(-bg_size.x * 0.4, bg_size.y * 0.2)
		name_label.size = Vector2(bg_size.x * 0.8, 60)

	# 入狱
	prison_icon.visible = member_data.is_imprisoned
	if member_data.is_imprisoned:
		modulate = Color.WHITE

		prison_turn_badge.visible = true
		prison_turn_label.visible = true
		var remain_turns: int = maxi(member_data.prison_turns_left, 0)
		prison_turn_label.text = "剩余" + str(remain_turns) + "回合"

		if _tex_prison_turn:
			var tex_size: Vector2 = _tex_prison_turn.get_size()
			var badge_scale := PRISON_TURN_BADGE_SCALE
			prison_turn_badge.scale = Vector2(badge_scale, badge_scale)
			var badge_y := 220.0
			if bg_sprite.texture:
				badge_y = bg_sprite.texture.get_size().y * PRISON_TURN_BADGE_ANCHOR_Y_RATIO
			badge_y += PRISON_TURN_BADGE_OFFSET.y
			prison_turn_badge.position = Vector2(round(PRISON_TURN_BADGE_OFFSET.x), round(badge_y))

			var badge_size := tex_size * badge_scale
			_layout_prison_turn_text(prison_turn_label.text, badge_size, badge_y)
	else:
		modulate = Color.WHITE
		prison_turn_badge.visible = false
		prison_turn_label.visible = false

	# 部门情报进度条更新逻辑（仅部门首领显示，未翻开时也可见）
	if member_data.is_leader and member_data.division != GameManager.Division.NONE:
		progress_bg.visible = true
		progress_bar.visible = true
		var pb_actual_size := Vector2.ZERO
		var pb_scale := 1.1 # 缩小到 1.1 倍，保持合适的宽度和比例
		
		if progress_bar.texture_under:
			var pb_native_size = progress_bar.texture_under.get_size()
			
			progress_bg.scale = Vector2(pb_scale, pb_scale)
			pb_actual_size = pb_native_size * pb_scale
			
			# 将背板置于卡牌的最下方，微调向下移动 13 像素防止挡住名字
			if bg_sprite.texture:
				var bg_y = 198.0
				var offset_x = 8.0 # 抵消素材图左侧纸张毛边导致的视觉偏左，向右微调 8 像素
				
				progress_bg.position = Vector2(offset_x, bg_y)
				
				# 必须显式设置 Control 的 size，否则 pivot_offset 缩放会因为默认 size 为 0 导致位置偏移
				progress_bar.size = pb_native_size
				progress_bar.pivot_offset = pb_native_size * 0.5
				progress_bar.scale = Vector2(pb_scale, pb_scale)
				
				# 进度条背板下方有投影，导致视觉中心偏上。这里将进度条位置向上微调 10 像素，同时向右偏移 8 像素以与背板对准
				progress_bar.position = Vector2(offset_x, bg_y - 10.0 * pb_scale) - pb_native_size * 0.5
				
				# 经精准检测，进度条轨道贴图(进度条.png)右侧有 15 像素透明空白，而左侧与黄色填充图(进度条黄色.png)均在 X=0 开始绘制左侧铜帽。
				# 因此，X 轴偏移必须为 0 像素，而 Y 轴由于轨道上方有 15 像素透明空白，需要向下偏移 15 像素，此时两者铜帽才能完美重合，不产生重影。
				progress_bar.texture_progress_offset = Vector2(0.0, 15.0)
		else:
			pb_actual_size = progress_bar.size
		
		# 读取该部门当前的情报值并转换为进度 (使用正确的变量名: intelligence)
		var raw_val: float = GameManager.intelligence.get(member_data.division, 0.0)
		var percent: float = raw_val if raw_val <= 1.0 else (raw_val / 100.0)
		var percent_int: int = int(round(percent * 100.0))
		var div_name: String = GameManager.DIVISION_NAMES.get(member_data.division, "未知部门")
		progress_bar.max_value = 100
		progress_bar.value = percent * 100
		
		# hover 触发区域也需要使用缩放后的实际居中范围
		var hover_y = 198.0
		var offset_x = 8.0
		_progress_hover_rect = Rect2(-pb_actual_size.x * 0.5 + offset_x, hover_y - pb_actual_size.y * 0.5, pb_actual_size.x, pb_actual_size.y)
			
		_progress_tooltip_text = div_name + " 情报进度: " + str(percent_int) + "% (" + str(percent_int) + "/100)"
	else:
		progress_bg.visible = false
		progress_bar.visible = false
		_progress_hover_rect = Rect2()
		_progress_tooltip_text = ""
		if _hit_control:
			_hit_control.tooltip_text = ""

func _compute_prison_font_size() -> int:
	## 根据固定常量和预加载纹理计算一次字号，供所有 update_display 复用
	var tex_size: Vector2 = _tex_prison_turn.get_size() if _tex_prison_turn else Vector2(200, 80)
	var badge_size := tex_size * PRISON_TURN_BADGE_SCALE
	var inner_size := Vector2(
		maxf(10.0, badge_size.x - PRISON_TURN_TEXT_INNER_MARGIN.x * 2.0),
		maxf(10.0, badge_size.y - PRISON_TURN_TEXT_INNER_MARGIN.y * 2.0)
	)
	var best := PRISON_TURN_TEXT_MIN_SIZE
	if _font_main:
		for size in range(PRISON_TURN_TEXT_MAX_SIZE, PRISON_TURN_TEXT_MIN_SIZE - 1, -1):
			var tw: float = _font_main.get_string_size(PRISON_TURN_TEXT_FIT_TEMPLATE, HORIZONTAL_ALIGNMENT_CENTER, -1.0, size).x
			var th: float = _font_main.get_height(size)
			if tw <= inner_size.x and th <= inner_size.y:
				best = size
				break
	return best

func _layout_prison_turn_text(_text: String, badge_size: Vector2, badge_y: float) -> void:
	var inner_size := Vector2(
		maxf(10.0, badge_size.x - PRISON_TURN_TEXT_INNER_MARGIN.x * 2.0),
		maxf(10.0, badge_size.y - PRISON_TURN_TEXT_INNER_MARGIN.y * 2.0)
	)
	# 手动基于字体实际高度计算垂直居中位置，不受文本内容（1、2、3）字形高度不同的影响
	var font_h: float = _font_main.get_height(_shared_prison_font_size) if _font_main else inner_size.y
	var label_pos := Vector2(
		PRISON_TURN_BADGE_OFFSET.x - inner_size.x * 0.5,
		badge_y - font_h * 0.5 + PRISON_TURN_TEXT_Y_OFFSET
	)
	prison_turn_label.position = Vector2(round(label_pos.x), round(label_pos.y))
	prison_turn_label.size = Vector2(round(inner_size.x), font_h + 20) # 高度给足避免裁剪
	# 直接使用类级别共享字号，所有卡片、所有回合数完全一致
	prison_turn_label.add_theme_font_size_override("font_size", _shared_prison_font_size)

func _get_badge_texture(division: int) -> Texture2D:
	match division:
		GameManager.Division.TRANSPORT:     return _tex_badge_transport
		GameManager.Division.FORTIFICATION: return _tex_badge_fortification
		GameManager.Division.RESEARCH:      return _tex_badge_research
		GameManager.Division.INTERVENTION:  return _tex_badge_intervention
	return null

func set_highlighted(on: bool) -> void:
	if _highlight_tween:
		_highlight_tween.kill()
		_highlight_tween = null
	
	halo_sprite.visible = true
	if on:
		modulate = Color.WHITE
		halo_sprite.modulate.a = 1.0
		_highlight_tween = create_tween().set_loops()
		_highlight_tween.tween_property(halo_sprite, "modulate:a", 0.3, 0.45)
		_highlight_tween.tween_property(halo_sprite, "modulate:a", 1.0, 0.45)
	else:
		modulate = Color.WHITE
		halo_sprite.modulate.a = 1.0


func _on_control_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_progress_tooltip(event.position)

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if member_data:
			card_clicked.emit(member_data.member_name)

func _on_mouse_entered() -> void:
	if member_data:
		card_hovered.emit(member_data.member_name)

func _on_mouse_exited() -> void:
	if _hit_control:
		_hit_control.tooltip_text = ""
	if _tooltip_panel:
		_tooltip_panel.visible = false
	if member_data:
		card_unhovered.emit(member_data.member_name)

func _update_progress_tooltip(local_pos_in_hit: Vector2) -> void:
	if _hit_control == null or _tooltip_panel == null:
		return
	if not progress_bar.visible or _progress_tooltip_text == "":
		_tooltip_panel.visible = false
		return

	var card_local_pos: Vector2 = _hit_control.position + local_pos_in_hit
	if _progress_hover_rect.has_point(card_local_pos):
		var raw_val: float = GameManager.intelligence.get(member_data.division, 0.0)
		var percent: float = raw_val if raw_val <= 1.0 else (raw_val / 100.0)
		var percent_int: int = int(round(percent * 100.0))
		_tooltip_panel.get_node("Label").text = str(percent_int) + "%"
		_tooltip_panel.visible = true
		
		# 核心修复：卡牌本身带有缩放，且相机 Camera2D 带有缩放 (zoom = 0.42)。
		# 我们将 tooltip 的全局缩放强制修正为相对于屏幕的 1.0 (Vector2.ONE / (global_scale * canvas_scale))
		# 对应的跟随偏移坐标也必须除以该总缩放，以在屏幕上产生恒定的像素位移。
		# 我们将偏移值调整为 (28, -14)，这在物理屏幕上能够完美避开鼠标指针的斜向身体，并留出合适的空白间距。
		var canvas_scale := get_canvas_transform().get_scale()
		var s := global_scale * canvas_scale
		if s.x > 0.001 and s.y > 0.001:
			_tooltip_panel.scale = Vector2.ONE / s
			_tooltip_panel.position = get_local_mouse_position() + Vector2(28, -14) / s
		else:
			_tooltip_panel.position = get_local_mouse_position() + Vector2(28, -14)
	else:
		_tooltip_panel.visible = false
