extends Node2D

## 主场景控制器 — 创建面板、UI层，协调遭遇流程

var _board: SyndicateBoard
var _ui_layer: CanvasLayer

# UI 组件
# var _encounter_panel: EncounterPanel
# var _action_panel: ActionPanel
var _card_overlay: CardActionOverlay
var _encounter_btn: Button
var _sandbox_btn: Button           # 沙盒模式入口按钮
var _turn_label: Label
var _info_label: Label
var _queue_label: Label           # 遭遇队列剩余提示
var _safehouse_buttons: Dictionary = {}  # Division -> Button
var _reset_btn: Button
var _undo_btn: Button
var _sandbox_wizard: Control = null

# 状态
var _current_encounter_member: String = ""
var _showing_result: bool = false
var _finish_enc_btn: Button        # 接替 EncounterPanel 的流程控制按钮
var _hover_timer: SceneTreeTimer = null
var _pending_hover_member: String = ""

func _ready():
	_build_board()
	_build_ui_layer()
	_connect_manager_signals()
	_connect_board_signals()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE) 
	
	# 自动加载存档进度
	var has_save = GameManager.load_game_from_disk()
	if not has_save:
		GameManager.initialize_game()
	else:
		_on_state_restored()
		_on_queue_updated(GameManager.encounter_queue.size())
		_update_sandbox_button_ui() 

# ===== 构建面板（世界空间） =====
func _build_board():
	_board = SyndicateBoard.new()
	_board.name = "Board"
	_board.y_sort_enabled = true # 开启 Y 轴自动排序
	# --- 核心修复：将棋盘中心点对齐到背景图中心 (960, 540) ---
	_board.position = Vector2(960, 540)
	add_child(_board)

# ===== 构建 UI 层（屏幕空间） =====
func _build_ui_layer():
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UILayer"
	_ui_layer.layer = 10
	add_child(_ui_layer)

	# --- HUD ---
	var hud := Control.new()
	hud.name = "HUD"
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(hud)

	# 开始遭遇按钮 — 左上角
	_encounter_btn = _make_button("⚔  开始遭遇", Vector2(20, 20), Color(0.15, 0.4, 0.7))
	_encounter_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_encounter_btn.custom_minimum_size = Vector2(180, 56)
	_encounter_btn.pressed.connect(_on_encounter_pressed)
	hud.add_child(_encounter_btn)

	# 回合计数 — 右上角
	_turn_label = Label.new()
	_turn_label.text = "回合: 0"
	_turn_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_turn_label.position = Vector2(-180, 16)
	_turn_label.add_theme_font_size_override("font_size", 20)
	_turn_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	_turn_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_turn_label.add_theme_constant_override("shadow_offset_x", 2)
	_turn_label.add_theme_constant_override("shadow_offset_y", 2)
	hud.add_child(_turn_label)

	# 沙盒模式按钮 — 右上角（在回合标签左侧）
	_sandbox_btn = _make_button("🛠 沙盒模式: 关", Vector2(-380, 16), Color(0.4, 0.4, 0.4))
	_sandbox_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_sandbox_btn.custom_minimum_size = Vector2(160, 40)
	_sandbox_btn.pressed.connect(_on_sandbox_pressed)
	hud.add_child(_sandbox_btn)

	# 状态信息 — 顶部中央
	_info_label = Label.new()
	_info_label.text = "点击「开始遭遇」进行游戏"
	_info_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_info_label.position = Vector2(-200, 16)
	_info_label.size = Vector2(400, 40)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.add_theme_font_size_override("font_size", 18)
	_info_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	_info_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_info_label.add_theme_constant_override("shadow_offset_x", 1)
	_info_label.add_theme_constant_override("shadow_offset_y", 1)
	hud.add_child(_info_label)

	# 遭遇队列提示 — 顶部中央偏下
	_queue_label = Label.new()
	_queue_label.text = ""
	_queue_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_queue_label.position = Vector2(-200, 44)
	_queue_label.size = Vector2(400, 30)
	_queue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_queue_label.add_theme_font_size_override("font_size", 15)
	_queue_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.3))
	_queue_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_queue_label.add_theme_constant_override("shadow_offset_x", 1)
	_queue_label.add_theme_constant_override("shadow_offset_y", 1)
	hud.add_child(_queue_label)

	# 藏身处突袭按钮 — 右下方，每个部门一个
	var div_index := 0
	for div in GameManager.ALL_DIVISIONS:
		var btn := _make_button("突袭 " + GameManager.DIVISION_NAMES[div], Vector2(-200, -80 - div_index * 50), Color(0.5, 0.3, 0.1))
		btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		btn.custom_minimum_size = Vector2(170, 40)
		btn.visible = false
		var div_copy := div
		btn.pressed.connect(func(): _on_raid_pressed(div_copy))
		hud.add_child(btn)
		_safehouse_buttons[div] = btn
		div_index += 1

	# 重置游戏按钮 — 右上
	_reset_btn = _make_button("↺ 重置游戏", Vector2(-180, 50), Color(0.4, 0.2, 0.2))
	_reset_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_reset_btn.custom_minimum_size = Vector2(140, 36)
	_reset_btn.pressed.connect(_on_reset_pressed)
	hud.add_child(_reset_btn)

	# 撤销操作按钮 — 重置下方
	_undo_btn = _make_button("↩ 撤销操作", Vector2(-180, 100), Color(0.3, 0.4, 0.5))
	_undo_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_undo_btn.custom_minimum_size = Vector2(140, 36)
	_undo_btn.pressed.connect(_on_undo_pressed)
	hud.add_child(_undo_btn)

	# --- 卡片操作覆盖层 (核心交互模式) ---
	_card_overlay = CardActionOverlay.new()
	_card_overlay.action_chosen.connect(_on_action_chosen)
	hud.add_child(_card_overlay)

	# --- 流程控制按钮 (替代旧版面板上的按钮) ---
	_finish_enc_btn = _make_button("➡ 处理下一波", Vector2(-200, -80), Color(0.1, 0.5, 0.2))
	_finish_enc_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_finish_enc_btn.custom_minimum_size = Vector2(170, 44)
	_finish_enc_btn.visible = false
	_finish_enc_btn.pressed.connect(_on_next_encounter)
	hud.add_child(_finish_enc_btn)

# ===== 连接信号 =====
func _connect_manager_signals():
	GameManager.turn_advanced.connect(_on_turn_advanced)
	GameManager.encounter_ended.connect(_on_encounter_ended)
	GameManager.encounter_queue_advanced.connect(_on_queue_updated)
	GameManager.action_executed.connect(_on_action_result)
	GameManager.safehouse_ready.connect(_on_safehouse_ready)
	GameManager.intelligence_changed.connect(_on_intel_changed_check)
	GameManager.state_restored.connect(_on_state_restored)

func _connect_board_signals():
	if _board:
		_board.card_clicked.connect(_on_board_card_clicked)
		_board.card_hovered.connect(_on_board_card_hovered)
		_board.card_unhovered.connect(_on_board_card_unhovered)

# ===== 按钮事件 =====
func _on_encounter_pressed():
	if not GameManager.current_encounter.is_empty() or not GameManager.encounter_queue.is_empty():
		return  # 遭遇进行中
	var enc := GameManager.generate_encounter()
	if enc.is_empty():
		_info_label.text = "没有可遭遇的成员"
		_queue_label.text = ""
		return

	var div_name: String = GameManager.DIVISION_NAMES.get(enc.get("division", 0), "未知")
	_info_label.text = "⚔ " + div_name + " 遭遇发生！点击卡片进行处理"
	_card_overlay.visible = false

	# 高亮参与遭遇的成员
	var names: Array = []
	for m in enc.get("members", []):
		names.append(m.member_name)
	_board.highlight_cards(names)
	_update_ui_state()

func _on_board_card_clicked(member_name: String):
	if _sandbox_wizard != null and is_instance_valid(_sandbox_wizard):
		_sandbox_wizard.handle_board_card_clicked(member_name)
		return

	# 检查是否在遭遇中
	if GameManager.current_encounter.is_empty():
		return
		
	# 检查是否为遭遇成员
	var is_enc_member := false
	for m in GameManager.current_encounter.get("members", []):
		if m.member_name == member_name:
			is_enc_member = true
			break
	if not is_enc_member:
		return

	# 检查是否已处理
	if member_name in GameManager.current_encounter.get("processed", []):
		return

	_current_encounter_member = member_name
	var member = GameManager.members.get(member_name)
	if member == null:
		return
	var actions := GameManager.get_available_actions(member)
		
	var screen_pos := Vector2(get_viewport_rect().size * 0.5)
	var card = _board.get_card(member_name)
	if card:
		screen_pos = card.get_global_transform_with_canvas().origin
		
	# 显示卡片操作覆盖层
	_card_overlay.show_member_actions(member, actions, screen_pos)

func _on_encounter_member_selected(_name: String):
	# 这个方法是原 EncounterPanel 的信号回调，现在已废弃但保持签名防止报错
	pass

# ===== 卡片悬停处理 =====
func _on_board_card_hovered(member_name: String, screen_pos: Vector2):
	if GameManager.current_encounter.is_empty():
		return

	var is_enc_member := false
	for m in GameManager.current_encounter.get("members", []):
		if m.member_name == member_name:
			is_enc_member = true
			break
	if not is_enc_member:
		return

	if member_name in GameManager.current_encounter.get("processed", []):
		return

	_pending_hover_member = member_name
	var timer = get_tree().create_timer(0.12)
	_hover_timer = timer
	await timer.timeout
	
	if _hover_timer == timer and _pending_hover_member == member_name:
		_current_encounter_member = member_name
		var member = GameManager.members.get(member_name)
		if member == null:
			return
		var actions := GameManager.get_available_actions(member)
		_card_overlay.show_member_actions(member, actions, screen_pos)

func _on_board_card_unhovered(member_name: String):
	if _pending_hover_member == member_name:
		_pending_hover_member = ""
func _try_hide_action_panel():
	pass

func _on_action_chosen(member_name: String, action: int):
	_showing_result = true
	GameManager.execute_action(member_name, action)

func _on_action_result(result: Dictionary):
	if _showing_result:
		_showing_result = false
		
		# 取消刚刚处理过的卡片的高亮效果
		var mname: String = result.get("member", "")
		var card = _board.get_card(mname)
		if card:
			card.set_highlighted(false)
			
		# 即使选择完卡片，也在一个简短延迟后自动关闭遮罩层
		await get_tree().create_timer(0.2).timeout
		_card_overlay.dismiss()

func _update_ui_state():
	var in_encounter := not GameManager.current_encounter.is_empty() or not GameManager.encounter_queue.is_empty()
	_encounter_btn.disabled = in_encounter
	
	# 下一个部门按钮控制
	if GameManager.current_encounter.is_empty() and not GameManager.encounter_queue.is_empty():
		_finish_enc_btn.text = "➡ 下一个部门"
		_finish_enc_btn.visible = true
	else:
		_finish_enc_btn.visible = false

func _on_encounter_ended():
	_board.clear_highlights()
	_update_ui_state()

	# 检查遭遇队列是否还有后续部门遭遇
	if not GameManager.encounter_queue.is_empty():
		_info_label.text = "当前部门遭遇结束"
	else:
		# 本回合所有遭遇已结束，自动还原，无需手动关闭
		_on_encounter_dismissed()

func _on_encounter_dismissed():
	_card_overlay.dismiss()
	_board.clear_highlights()
	_info_label.text = "点击「开始遭遇」继续"
	_queue_label.text = ""
	_update_ui_state()

func _on_next_encounter():
	## 推进到下一个部门遭遇
	_board.clear_highlights()

	var enc := GameManager.advance_encounter_queue()
	if enc.is_empty():
		_on_encounter_dismissed()
		return

	var div_name: String = GameManager.DIVISION_NAMES.get(enc.get("division", 0), "未知")
	_info_label.text = "⚔ " + div_name + " 遭遇发生！点击卡片进行处理"

	# 高亮参与遭遇的成员
	var names: Array = []
	for m in enc.get("members", []):
		names.append(m.member_name)
	_board.highlight_cards(names)
	_update_ui_state()

func _on_turn_advanced(turn: int):
	_turn_label.text = "回合: " + str(turn)

func _on_queue_updated(remaining: int):
	if remaining > 0:
		_queue_label.text = "⏳ 还有 " + str(remaining) + " 个部门遭遇待处理"
	else:
		_queue_label.text = ""

func _on_safehouse_ready(div: int):
	if _safehouse_buttons.has(div):
		_safehouse_buttons[div].visible = false
	_info_label.text = GameManager.DIVISION_NAMES.get(div, "") + " 藏身处可突袭！"

func _on_intel_changed_check(div: int, value: float):
	if _safehouse_buttons.has(div):
		_safehouse_buttons[div].visible = false

func _on_raid_pressed(div: int):
	GameManager.raid_safehouse(div)
	if _safehouse_buttons.has(div):
		_safehouse_buttons[div].visible = false
	_info_label.text = GameManager.DIVISION_NAMES.get(div, "") + " 藏身处已突袭！"

func _on_reset_pressed():
	if _sandbox_wizard != null and is_instance_valid(_sandbox_wizard):
		_sandbox_wizard.queue_free()
		_sandbox_wizard = null
	GameManager.is_sandbox_mode = false
	_update_sandbox_button_ui()

	# 清理
	# _encounter_panel.visible = false
	# _action_panel.hide_panel()
	_board.clear_highlights()
	for div in _safehouse_buttons:
		_safehouse_buttons[div].visible = false
	_queue_label.text = ""

	# 移除旧 Board 并重建
	_board.queue_free()
	await get_tree().process_frame
	GameManager.initialize_game()
	GameManager.delete_save_file()
	_build_board()
	_connect_board_signals()
	_update_ui_state()
	_info_label.text = "游戏已重置"
	_turn_label.text = "回合: 0"

func _on_undo_pressed():
	if GameManager.can_undo():
		GameManager.undo()

func _on_state_restored():
	_turn_label.text = "回合: " + str(GameManager.turn_count)
	_card_overlay.dismiss()
	
	# 恢复各部门藏身处按钮可见性 (卡牌下方已集成，此处HUD保持隐藏)
	for div in _safehouse_buttons:
		_safehouse_buttons[div].visible = false
			
	_board.clear_highlights()
	_update_ui_state()
	
	if not GameManager.current_encounter.is_empty():
		var enc = GameManager.current_encounter
		var div_name: String = GameManager.DIVISION_NAMES.get(enc.get("division", 0), "未知")
		_info_label.text = "⚔ " + div_name + " 遭遇发生！点击卡片进行处理"
		
		var names: Array = []
		var processed = GameManager.current_encounter.get("processed", [])
		for m in GameManager.current_encounter.get("members", []):
			if m.member_name not in processed:
				names.append(m.member_name)
		_board.highlight_cards(names)
	else:
		_info_label.text = "点击「开始遭遇」继续"

# ===== 辅助 =====
func _make_button(text: String, pos: Vector2, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.position = pos

	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed_s := style.duplicate()
	pressed_s.bg_color = color.darkened(0.1)
	btn.add_theme_stylebox_override("pressed", pressed_s)

	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color.WHITE)
	return btn

func _on_sandbox_pressed():
	if _sandbox_wizard != null and is_instance_valid(_sandbox_wizard):
		_sandbox_wizard.queue_free()
		_sandbox_wizard = null
		GameManager.is_sandbox_mode = false
		_update_sandbox_button_ui()
		_set_top_buttons_visible(true)
		_on_reset_pressed()
		return

	if GameManager.is_sandbox_mode:
		# 如果沙盒模式开着但是向导不在，直接关掉沙盒模式并重置
		GameManager.is_sandbox_mode = false
		_update_sandbox_button_ui()
		_set_top_buttons_visible(true)
		_on_reset_pressed()
	else:
		# 如果当前正常模式已经有进度，弹出警告确认窗口
		if GameManager.turn_count > 0 or not GameManager.current_encounter.is_empty():
			_show_sandbox_confirmation_popup()
		else:
			_start_sandbox_wizard()

func _show_sandbox_confirmation_popup():
	# 创建黑色半透明背景遮罩
	var backdrop := Control.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui_layer.add_child(backdrop)
	
	var color_rect := ColorRect.new()
	color_rect.color = Color(0, 0, 0, 0.45)
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(color_rect)
	
	# 居中的 PanelContainer 控制面板
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.98)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.7, 0.55, 0.2, 0.8) # 金色边框
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 15
	style.content_margin_left = 25
	style.content_margin_right = 25
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	
	var panel_size := Vector2(420, 190)
	panel.size = panel_size
	var vp := get_viewport_rect().size
	panel.position = Vector2((vp.x - panel_size.x) * 0.5, (vp.y - panel_size.y) * 0.5)
	backdrop.add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)
	
	var title_lbl := Label.new()
	title_lbl.text = "⚠️ 警告"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35))
	vbox.add_child(title_lbl)
	
	var text_lbl := Label.new()
	text_lbl.text = "进入沙盒模式将会清空当前正在进行的游戏局进度。\n您确定要切换至沙盒模式吗？"
	text_lbl.add_theme_font_size_override("font_size", 14)
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(text_lbl)
	
	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 15)
	vbox.add_child(btn_hbox)
	
	var cancel_btn := Button.new()
	cancel_btn.text = " 取消 "
	cancel_btn.pressed.connect(func(): backdrop.queue_free())
	btn_hbox.add_child(cancel_btn)
	
	var ok_btn := Button.new()
	ok_btn.text = " 确定 "
	ok_btn.pressed.connect(func():
		backdrop.queue_free()
		_start_sandbox_wizard()
	)
	btn_hbox.add_child(ok_btn)

func _start_sandbox_wizard():
	# 开启沙盒向导
	var wizard_script := preload("res://scripts/ui/sandbox_setup_wizard.gd")
	_sandbox_wizard = wizard_script.new()
	_sandbox_wizard.completed.connect(_on_wizard_completed)
	_sandbox_wizard.closed.connect(_on_wizard_closed)
	_ui_layer.add_child(_sandbox_wizard)

	# 布阵导向期间，隐藏上方三个游戏按钮
	_set_top_buttons_visible(false)

	# 临时将按钮显示为“正在布阵...”
	_sandbox_btn.text = "🛠 正在布阵..."
	_set_button_color(_sandbox_btn, Color(0.6, 0.4, 0.1))

func _on_wizard_completed():
	_sandbox_wizard = null
	GameManager.is_sandbox_mode = true
	print("Sandbox Wizard completed: Sandbox Mode active!")
	_update_sandbox_button_ui()
	_set_top_buttons_visible(true)
	_refresh_ui_after_sandbox_activation()
	GameManager.save_game_to_disk()

func _refresh_ui_after_sandbox_activation():
	# 隐藏突袭和挑战主脑按钮
	for div in _safehouse_buttons:
		_safehouse_buttons[div].visible = false
	
	# 重设提示文本
	_queue_label.text = ""
	_info_label.text = "点击「开始遭遇」继续"
	_turn_label.text = "回合: " + str(GameManager.turn_count)
	
	# 重设卡牌高亮和操作遮罩
	_card_overlay.dismiss()
	_board.clear_highlights()
	
	# 刷新顶级控制按钮状态 (开始遭遇、处理下一波)
	_update_ui_state()

func _on_wizard_closed():
	_sandbox_wizard = null
	GameManager.is_sandbox_mode = false
	print("Sandbox Wizard aborted/closed: Normal Mode active!")
	_update_sandbox_button_ui()
	_set_top_buttons_visible(true)
	_on_reset_pressed()

func _set_top_buttons_visible(v: bool):
	if is_instance_valid(_encounter_btn): _encounter_btn.visible = v
	if is_instance_valid(_reset_btn): _reset_btn.visible = v
	if is_instance_valid(_undo_btn): _undo_btn.visible = v

func _update_sandbox_button_ui():
	if GameManager.is_sandbox_mode:
		_sandbox_btn.text = "🛠 沙盒模式: 开"
		_set_button_color(_sandbox_btn, Color(0.15, 0.6, 0.5)) # Teal for Active
	else:
		_sandbox_btn.text = "🛠 沙盒模式: 关"
		_set_button_color(_sandbox_btn, Color(0.4, 0.4, 0.4)) # Gray for Inactive

func _set_button_color(btn: Button, color: Color):
	var style = btn.get_theme_stylebox("normal")
	if style is StyleBoxFlat:
		style.bg_color = color
	var hover = btn.get_theme_stylebox("hover")
	if hover is StyleBoxFlat:
		hover.bg_color = color.lightened(0.2)
	var pressed = btn.get_theme_stylebox("pressed")
	if pressed is StyleBoxFlat:
		pressed.bg_color = color.darkened(0.1)

func _input(event: InputEvent):
	# 1. F11 切换全屏/窗口模式
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		var mode := DisplayServer.window_get_mode()
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
