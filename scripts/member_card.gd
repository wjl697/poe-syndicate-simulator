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
var progress_bar: TextureProgressBar
var _highlight_tween: Tween = null

# 预加载纹理
var _tex_bg        := preload("res://辛迪加素材/人物背景.png")
var _tex_halo_mem  := preload("res://辛迪加素材/成员光晕.png")
var _tex_halo_lead := preload("res://辛迪加素材/首领光晕.png")
var _tex_star1     := preload("res://辛迪加素材/一星等级.png")
var _tex_star2     := preload("res://辛迪加素材/二星等级.png")
var _tex_star3     := preload("res://辛迪加素材/三星等级.png")
var _tex_question  := preload("res://辛迪加素材/问号.png")

# 部门角标纹理
var _tex_badge_transport     := preload("res://辛迪加素材/运输部角标.png")
var _tex_badge_fortification := preload("res://辛迪加素材/防卫部角标.png")
var _tex_badge_research      := preload("res://辛迪加素材/科研部角标.png")
var _tex_badge_intervention  := preload("res://辛迪加素材/调停部角标.png")


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
	progress_bar = TextureProgressBar.new()
	progress_bar.texture_under = preload("res://辛迪加素材/进度条背板.png")
	progress_bar.texture_over = preload("res://辛迪加素材/进度条.png")
	progress_bar.texture_progress = preload("res://辛迪加素材/进度条黄色.png")
	progress_bar.z_index = 6
	progress_bar.visible = false
	add_child(progress_bar)

	# --- 点击区域 (使用 Control 完美处理遮挡关系) ---
	var hit_control := Control.new()
	hit_control.size = Vector2(280, 380)
	hit_control.position = Vector2(-140, -190)
	hit_control.mouse_filter = Control.MOUSE_FILTER_STOP
	hit_control.gui_input.connect(_on_control_gui_input)
	hit_control.mouse_entered.connect(_on_mouse_entered)
	hit_control.mouse_exited.connect(_on_mouse_exited)
	add_child(hit_control)
	_tree_built = true

func setup(data) -> void:
	if not _tree_built:
		_build_tree()
	member_data = data
	update_display()

func update_display() -> void:
	if member_data == null:
		return

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
				var bg_size: Vector2 = bg_sprite.texture.get_size()
				var p_size: Vector2 = ptex.get_size()
				var fit_scale: float = minf(bg_size.x * 0.55 / p_size.x, bg_size.y * 0.85 / p_size.y)
				portrait_sprite.scale = Vector2(fit_scale, fit_scale)
				portrait_sprite.position = Vector2(0, -bg_size.y * 0.02)

	# 光晕 — 815x447 图层，直接对齐背景
	halo_sprite.texture = _tex_halo_lead if member_data.is_leader else _tex_halo_mem
	halo_sprite.scale = Vector2.ONE
	halo_sprite.position = Vector2.ZERO

	# 星级 — 815x447 图层，直接对齐背景
	if is_hidden or member_data.rank <= 0:
		star_sprite.visible = false
	else:
		star_sprite.visible = true
		match member_data.rank:
			1: star_sprite.texture = _tex_star1
			2: star_sprite.texture = _tex_star2
			3: star_sprite.texture = _tex_star3
		star_sprite.scale = Vector2(0.8, 0.8)
		star_sprite.position = Vector2(170, -155)
		star_sprite.modulate.a = 0.8

	# 部门角标 — 815x447 图层，直接对齐背景
	if member_data.division == GameManager.Division.NONE:
		badge_sprite.visible = false
	else:
		badge_sprite.visible = true
		var badge_tex: Texture2D = _get_badge_texture(member_data.division)
		if badge_tex:
			badge_sprite.texture = badge_tex
			badge_sprite.scale =  Vector2(0.8, 0.8)
			badge_sprite.position = Vector2(-125, -145)
			badge_sprite.modulate.a = 0.8

	# 名称 — 隐藏时显示「???」
	if is_hidden:
		name_label.text = ""
	else:
		name_label.text = member_data.member_name
	if bg_sprite.texture:
		var bg_size: Vector2 = bg_sprite.texture.get_size()
		name_label.position = Vector2(-bg_size.x * 0.4, bg_size.y * 0.2)
		name_label.size = Vector2(bg_size.x * 0.8, 60)

	# 入狱
	prison_icon.visible = member_data.is_imprisoned
	if member_data.is_imprisoned:
		modulate = Color(0.5, 0.5, 0.65, 0.8)
	else:
		modulate = Color.WHITE

	# 部门情报进度条更新逻辑 (仅部门首领显示，且排除主脑)
	if not is_hidden and member_data.is_leader and member_data.division != GameManager.Division.NONE:
		progress_bar.visible = true
		if progress_bar.texture_over:
			var pb_native_size = progress_bar.texture_over.get_size()
			# 为了适配各种素材尺寸，我们将其等比缩放至约占据卡牌宽度的大部分（比如 180 像素）
			var target_w := 210.0
			var pb_scale := 1.0
			if pb_native_size.x > 0:
				pb_scale = minf(target_w / pb_native_size.x, 1.0)
			progress_bar.scale = Vector2(pb_scale, pb_scale)
			var pb_actual_size = pb_native_size * pb_scale
			# 将其居中置于名字下方 (名字的 Y 为 bg_size.y * 0.2，大约为 89)
			if bg_sprite.texture:
				var bg_y = bg_sprite.texture.get_size().y * 0.32
				progress_bar.position = Vector2(-pb_actual_size.x * 0.5, bg_y)
		
		# 读取该部门当前的情报值并转换为进度 (使用正确的变量名: intelligence)
		var raw_val: float = GameManager.intelligence.get(member_data.division, 0.0)
		var percent: float = raw_val if raw_val <= 1.0 else (raw_val / 100.0)
		progress_bar.max_value = 100
		progress_bar.value = percent * 100
	else:
		progress_bar.visible = false

func _get_badge_texture(division: int) -> Texture2D:
	match division:
		GameManager.Division.TRANSPORT:     return _tex_badge_transport
		GameManager.Division.FORTIFICATION: return _tex_badge_fortification
		GameManager.Division.RESEARCH:      return _tex_badge_research
		GameManager.Division.INTERVENTION:  return _tex_badge_intervention
	return null

func set_highlighted(on: bool) -> void:
	# 先停止所有现有的动画
	for tw in get_tree().get_processed_tweens():
		if tw.is_valid() and (tw.get_total_elapsed_time() < 1000 or true): # 一般直接 kill 就好
			pass # 这样不够精确
	
	# 更简单的方法：直接 kill halo_sprite 上的 tween
	var old_tw = get_node_or_null("__highlight_tween")
	if old_tw: 
		old_tw.queue_free() # 不好使，Tween 不是 Node
		
	# 真正有效的方法：在 MemberCard 中存一个变量
	if _highlight_tween:
		_highlight_tween.kill()
		_highlight_tween = null
	
	if on:
		modulate = Color(1.3, 1.2, 0.8, 1.0)
		_highlight_tween = create_tween().set_loops()
		_highlight_tween.tween_property(halo_sprite, "modulate:a", 1.0, 0.4)
		_highlight_tween.tween_property(halo_sprite, "modulate:a", 0.5, 0.4)
	else:
		modulate = Color.WHITE if (member_data == null or not member_data.is_imprisoned) else Color(0.5, 0.5, 0.65, 0.8)
		halo_sprite.modulate.a = 1.0 # 恢复不透明度


func _on_control_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if member_data:
			card_clicked.emit(member_data.member_name)

func _on_mouse_entered() -> void:
	if member_data:
		card_hovered.emit(member_data.member_name)

func _on_mouse_exited() -> void:
	if member_data:
		card_unhovered.emit(member_data.member_name)
