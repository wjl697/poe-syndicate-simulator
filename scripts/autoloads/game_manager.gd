extends Node

# ===== 信号 =====
signal board_changed()
signal encounter_started(encounter_data: Dictionary)
signal encounter_ended()
signal encounter_queue_advanced(remaining: int)
signal action_executed(result: Dictionary)
signal intelligence_changed(division: int, value: float)
signal safehouse_ready(division: int)
signal mastermind_ready()
signal member_imprisoned(member_name: String)
signal member_released(member_name: String)
signal member_revealed(member_name: String)
signal turn_advanced(turn: int)

# ===== 枚举 =====
enum Division { NONE, TRANSPORT, FORTIFICATION, RESEARCH, INTERVENTION }
enum RelationType { TRUST, RIVALRY, NEUTRAL }
enum ActionType { INTERROGATE, EXECUTE, BARGAIN, BETRAY, RELEASE }

# ===== 常量 =====
const MAX_SUBORDINATES_PER_DIVISION := 4    # 每部门最多4个手下
const MAX_MEMBERS_PER_DIVISION := 5         # 1首领 + 4手下
const MAX_IMPRISONED := 3                   # 最多同时在押3人
const PRISON_DURATION := 3                  # 监禁持续3次遭遇
const ACTIVE_MEMBER_COUNT := 14             # 每局14人上场
const MAX_ENCOUNTER_MEMBERS := 4            # 单场遭遇最多4人
const MASTERMIND_INTEL_PER_RAID := 0.34

# 情报提供量 — 按星级
const INTEL_PER_RANK := {
	1: 0.10,
	2: 0.15,
	3: 0.20,
}

const MEMBER_DEFS: Array[String] = [
	"克雷尔", "卡美利亚", "古夫", "哈库", "尤尔金",
	"托拉", "杨纳斯", "格拉维奇", "爱斯林", "瓦甘",
	"瓦里西", "艾尔雷恩", "莱克", "西拉克", "逃逸怪",
	"里奥", "麟"
]

const DIVISION_NAMES := {
	Division.TRANSPORT: "运输部",
	Division.FORTIFICATION: "防卫部",
	Division.RESEARCH: "科研部",
	Division.INTERVENTION: "调停部",
}

const DIVISION_BADGE_PATHS := {
	Division.TRANSPORT: "res://辛迪加素材/运输部角标.png",
	Division.FORTIFICATION: "res://辛迪加素材/防卫部角标.png",
	Division.RESEARCH: "res://辛迪加素材/科研部角标.png",
	Division.INTERVENTION: "res://辛迪加素材/调停部角标.png",
}

const ALL_DIVISIONS: Array[int] = [
	Division.TRANSPORT, Division.FORTIFICATION,
	Division.RESEARCH, Division.INTERVENTION
]

# ===== 内部类 =====
class MemberState:
	var member_name: String
	var portrait_path: String
	var division: int = Division.NONE
	var is_leader: bool = false
	var rank: int = 1                       # 0=无级(游荡), 1~3星
	var is_imprisoned: bool = false
	var prison_turns_left: int = 0
	var is_on_board: bool = true
	var is_revealed: bool = false
	var equipment_count: int = 0            # 辛迪加装备(上限3)

	func _init(p_name: String = "", p_portrait: String = ""):
		member_name = p_name
		portrait_path = p_portrait

class RelationshipEntry:
	var member_a: String
	var member_b: String
	var type: int
	func _init(a: String = "", b: String = "", t: int = 0):
		member_a = a
		member_b = b
		type = t

# ===== 状态变量 =====
var members: Dictionary = {}                # name -> MemberState
var relationships: Array = []               # Array[RelationshipEntry]
var intelligence: Dictionary = {}           # Division -> float (0.0-1.0)
var mastermind_intel: float = 0.0
var turn_count: int = 0
var current_encounter: Dictionary = {}      # {division, members, processed}
var encounter_queue: Array[Dictionary] = [] # 多部门遭遇队列
var prison_queue: Array[String] = []        # 按入狱顺序记录名字

# ===== 生命周期 =====
func _ready():
	initialize_game()

func initialize_game():
	members.clear()
	relationships.clear()
	intelligence.clear()
	turn_count = 0
	mastermind_intel = 0.0
	current_encounter.clear()
	encounter_queue.clear()
	prison_queue.clear()

	for div in ALL_DIVISIONS:
		intelligence[div] = 0.0

	for mname in MEMBER_DEFS:
		var portrait = "res://辛迪加素材/人员/" + mname + ".png"
		members[mname] = MemberState.new(mname, portrait)

	_assign_members_randomly()
	_generate_initial_relationships()
	board_changed.emit()

# ===== 初始化辅助 =====
func _assign_members_randomly():
	var pool: Array = MEMBER_DEFS.duplicate()
	pool.shuffle()

	# 从17人中选14人上场
	var active_pool: Array = pool.slice(0, ACTIVE_MEMBER_COUNT)
	var bench_pool: Array = pool.slice(ACTIVE_MEMBER_COUNT)

	# 不上场的成员
	for mname in bench_pool:
		var m: MemberState = members[mname]
		m.is_on_board = false
		m.division = Division.NONE
		m.is_leader = false
		m.is_revealed = false

	# 打乱上场池
	active_pool.shuffle()
	var idx := 0

	# 每部门1个首领（共4人）
	for div in ALL_DIVISIONS:
		if idx >= active_pool.size():
			break
		var m: MemberState = members[active_pool[idx]]
		m.division = div
		m.is_leader = true
		m.is_on_board = true
		m.is_revealed = false
		m.rank = 1
		idx += 1

	# 每部门随机1~2名手下
	var sub_counts: Array[int] = []
	var remaining_subs: int = active_pool.size() - idx  # 10
	for _div in ALL_DIVISIONS:
		sub_counts.append(1)
	var assigned_subs: int = 4
	var extra_budget: int = mini(4, remaining_subs - assigned_subs - 2)
	extra_budget = maxi(0, extra_budget)
	var div_indices: Array = [0, 1, 2, 3]
	div_indices.shuffle()
	for i in range(extra_budget):
		sub_counts[div_indices[i]] = 2
		assigned_subs += 1

	for div_i in range(ALL_DIVISIONS.size()):
		var div: int = ALL_DIVISIONS[div_i]
		var count: int = sub_counts[div_i]
		for _j in range(count):
			if idx >= active_pool.size():
				break
			var m: MemberState = members[active_pool[idx]]
			m.division = div
			m.is_leader = false
			m.is_on_board = true
			m.is_revealed = false
			m.rank = 1
			idx += 1

	# 剩余为自由人员
	while idx < active_pool.size():
		var m: MemberState = members[active_pool[idx]]
		m.division = Division.NONE
		m.is_leader = false
		m.is_on_board = true
		m.is_revealed = false
		m.rank = 1
		idx += 1

func _generate_initial_relationships():
	var count := randi_range(3, 5)
	var on_board: Array = []
	for mname in members:
		if members[mname].is_on_board:
			on_board.append(mname)
	for _i in range(count):
		on_board.shuffle()
		if on_board.size() < 2:
			break
		var a: String = on_board[0]
		var b: String = on_board[1]
		if get_relationship_between(a, b) != null:
			continue
		var rtype: int = RelationType.TRUST if randf() > 0.5 else RelationType.RIVALRY
		relationships.append(RelationshipEntry.new(a, b, rtype))

# ===== 查询接口 =====
func get_division_leader(div: int):
	for mname in members:
		var m: MemberState = members[mname]
		if m.division == div and m.is_leader and m.is_on_board:
			return m
	return null

func get_division_members(div: int) -> Array:
	var result: Array = []
	for mname in members:
		var m: MemberState = members[mname]
		if m.division == div and not m.is_leader and m.is_on_board:
			result.append(m)
	return result

func get_all_division_members(div: int) -> Array:
	## 返回部门的所有成员（含首领）
	var result: Array = []
	for mname in members:
		var m: MemberState = members[mname]
		if m.division == div and m.is_on_board:
			result.append(m)
	return result

func get_unassigned_members() -> Array:
	var result: Array = []
	for mname in members:
		var m: MemberState = members[mname]
		if m.division == Division.NONE and m.is_on_board:
			result.append(m)
	return result

func get_relationships_for(mname: String) -> Array:
	var result: Array = []
	for rel in relationships:
		if rel.member_a == mname or rel.member_b == mname:
			result.append(rel)
	return result

func get_relationship_between(a: String, b: String):
	for rel in relationships:
		if (rel.member_a == a and rel.member_b == b) or \
		   (rel.member_a == b and rel.member_b == a):
			return rel
	return null

func get_division_slot_count(div: int) -> int:
	var count := 0
	for mname in members:
		var m: MemberState = members[mname]
		if m.division == div and m.is_on_board:
			count += 1
	return count

func _get_remaining_encounter_members() -> Array:
	## 获取当前遭遇中尚未处理的成员
	var result: Array = []
	if current_encounter.is_empty():
		return result
	for m in current_encounter.get("members", []):
		if m.member_name not in current_encounter.get("processed", []):
			result.append(m)
	return result

func _get_imprisoned_count() -> int:
	var count := 0
	for mname in members:
		if members[mname].is_imprisoned:
			count += 1
	return count

# ===== 揭示系统 =====
func reveal_member(member_name: String) -> void:
	var m: MemberState = members.get(member_name)
	if m and not m.is_revealed:
		m.is_revealed = true
		member_revealed.emit(member_name)

# ================================================================
#                       遭遇系统 (重写)
# ================================================================

func generate_encounter() -> Dictionary:
	## 生成一个回合的遭遇，返回第一个遭遇事件
	turn_count += 1
	_process_prison_intel()
	turn_advanced.emit(turn_count)

	encounter_queue.clear()
	current_encounter.clear()

	# 确定本回合出现的部门（最多3个）
	# 运输/防卫 二选一 + 研究 + 调停
	var divisions_this_turn: Array[int] = []

	# 运输 or 防卫
	var tf_candidates: Array[int] = []
	if _division_has_encounterable(Division.TRANSPORT):
		tf_candidates.append(Division.TRANSPORT)
	if _division_has_encounterable(Division.FORTIFICATION):
		tf_candidates.append(Division.FORTIFICATION)
	if not tf_candidates.is_empty():
		divisions_this_turn.append(tf_candidates[randi() % tf_candidates.size()])

	# 研究
	if _division_has_encounterable(Division.RESEARCH):
		divisions_this_turn.append(Division.RESEARCH)

	# 调停
	if _division_has_encounterable(Division.INTERVENTION):
		divisions_this_turn.append(Division.INTERVENTION)

	if divisions_this_turn.is_empty():
		return {}

	# 为每个部门生成遭遇事件
	for div in divisions_this_turn:
		var enc := _generate_single_encounter(div)
		if not enc.is_empty():
			encounter_queue.append(enc)

	if encounter_queue.is_empty():
		return {}

	# 启动第一个遭遇
	current_encounter = encounter_queue.pop_front()
	_reveal_encounter_members(current_encounter)
	encounter_started.emit(current_encounter)
	board_changed.emit()
	encounter_queue_advanced.emit(encounter_queue.size())
	return current_encounter

func _division_has_encounterable(div: int) -> bool:
	for mname in members:
		var m: MemberState = members[mname]
		if m.division == div and m.is_on_board and not m.is_imprisoned:
			return true
	return false

func _generate_single_encounter(div: int) -> Dictionary:
	## 按 "主成员 + 增援" 模型生成单个部门遭遇
	var enc_members: Array = []

	# --- 1. 选择主成员（非首领的部门下属） ---
	var subordinates: Array = []
	for mname in members:
		var m: MemberState = members[mname]
		if m.division == div and not m.is_leader and m.is_on_board and not m.is_imprisoned:
			subordinates.append(m)

	if subordinates.is_empty():
		# 如果部门只有首领没有手下，首领出场
		var leader = get_division_leader(div)
		if leader and not leader.is_imprisoned:
			enc_members.append(leader)
		if enc_members.is_empty():
			return {}
	else:
		# 随机选一个下属作为主成员
		var primary: MemberState = subordinates[randi() % subordinates.size()]
		enc_members.append(primary)

	var primary_name: String = enc_members[0].member_name

	# --- 2. 增援：同部门成员（极高概率） ---
	for mname in members:
		if enc_members.size() >= MAX_ENCOUNTER_MEMBERS:
			break
		var m: MemberState = members[mname]
		if m.member_name == primary_name:
			continue
		if m.division == div and m.is_on_board and not m.is_imprisoned:
			if randf() < 0.85:  # 同部门极高概率
				enc_members.append(m)

	# --- 3. 增援：关系链（信任/宿敌） ---
	var relation_candidates: Array = []
	for rel in get_relationships_for(primary_name):
		var other_name: String = rel.member_b if rel.member_a == primary_name else rel.member_a
		var other: MemberState = members.get(other_name)
		if other == null or not other.is_on_board or other.is_imprisoned:
			continue
		# 已在列表中跳过
		var already := false
		for em in enc_members:
			if em.member_name == other_name:
				already = true
				break
		if already:
			continue
		relation_candidates.append({"member": other, "type": rel.type})

	# 按关系增援
	relation_candidates.shuffle()
	for candidate in relation_candidates:
		if enc_members.size() >= MAX_ENCOUNTER_MEMBERS:
			break
		var prob: float
		if candidate.type == RelationType.TRUST:
			prob = 0.50  # 盟友中等概率
		else:
			prob = 0.40  # 死敌中等概率
		if randf() < prob:
			enc_members.append(candidate.member)

	return {
		"division": div,
		"members": enc_members,
		"processed": [],
	}

func _reveal_encounter_members(enc: Dictionary):
	for m in enc.get("members", []):
		reveal_member(m.member_name)

func advance_encounter_queue() -> Dictionary:
	## 当前遭遇完成后，推进到队列中的下一个
	if encounter_queue.is_empty():
		return {}
	current_encounter = encounter_queue.pop_front()
	_reveal_encounter_members(current_encounter)
	encounter_started.emit(current_encounter)
	board_changed.emit()
	encounter_queue_advanced.emit(encounter_queue.size())
	return current_encounter

# ================================================================
#                   操作可用性判定 (重写)
# ================================================================

func get_available_actions(member: MemberState) -> Array:
	## 根据剩余未处理成员数决定可用操作
	var remaining := _get_remaining_encounter_members()
	var remaining_count: int = remaining.size()
	var actions: Array = []

	# --- 审讯：始终可用 ---
	actions.append(ActionType.INTERROGATE)

	# --- 处决：剩余 ≥ 3 人时所有人可处决 ---
	if remaining_count >= 3:
		actions.append(ActionType.EXECUTE)

	# --- 商谈(Betray)：恰好剩 2 人且非宿敌 ---
	if remaining_count == 2:
		var other: MemberState = null
		for m in remaining:
			if m.member_name != member.member_name:
				other = m
				break
		if other:
			var rel = get_relationship_between(member.member_name, other.member_name)
			# 非宿敌才可商谈（无关系或信任都可以）
			if rel == null or rel.type != RelationType.RIVALRY:
				actions.append(ActionType.BETRAY)

	# --- 谈判(Bargain)：恰好剩 1 人 ---
	if remaining_count == 1:
		actions.append(ActionType.BARGAIN)

	# --- 释放：始终可用 ---
	actions.append(ActionType.RELEASE)

	return actions

# ================================================================
#                     操作执行 (重写)
# ================================================================

func execute_action(member_name: String, action: int):
	var member: MemberState = members.get(member_name)
	if member == null:
		return
	var result := {"action": action, "member": member_name, "effects": []}

	match action:
		ActionType.INTERROGATE: _do_interrogate(member, result)
		ActionType.EXECUTE:     _do_execute(member, result)
		ActionType.BARGAIN:     _do_bargain(member, result)
		ActionType.BETRAY:      _do_betray(member, result)
		ActionType.RELEASE:
			result.effects.append("释放了 " + member.member_name + "（棋盘不变）")

	current_encounter.get("processed", []).append(member_name)
	action_executed.emit(result)
	board_changed.emit()
	_check_encounter_end()

# ================================================================
#                    审讯 (Interrogate) — 重写
# ================================================================

func _do_interrogate(m: MemberState, result: Dictionary):
	# 审讯上限检查 — 第4人入狱时释放最早的囚犯
	if _get_imprisoned_count() >= MAX_IMPRISONED:
		_force_release_oldest_prisoner(result)

	# 如果是首领 → 下台
	if m.is_leader:
		_leader_step_down(m, result)

	# 入狱
	m.is_imprisoned = true
	m.prison_turns_left = PRISON_DURATION
	prison_queue.append(m.member_name)

	# 立即提供一次情报（基于星级）
	_provide_intel_for_member(m, result)

	result.effects.append(m.member_name + " 入狱 " + str(PRISON_DURATION) + " 次遭遇")
	member_imprisoned.emit(m.member_name)

func _leader_step_down(m: MemberState, result: Dictionary):
	## 首领下台，提拔替代者
	var div: int = m.division
	m.is_leader = false
	result.effects.append(m.member_name + " 从 " + DIVISION_NAMES.get(div, "") + " 首领下台")

	# 优先从同部门手下中提拔
	var candidates: Array = get_division_members(div)
	# 排除被审讯的自己和在押成员
	var valid: Array = []
	for c in candidates:
		if c.member_name != m.member_name and not c.is_imprisoned:
			valid.append(c)

	if valid.is_empty():
		# 无手下，从自由人中提拔
		var free := get_unassigned_members()
		for f in free:
			if not f.is_imprisoned:
				valid.append(f)

	if not valid.is_empty():
		var promoted: MemberState = valid[randi() % valid.size()]
		promoted.is_leader = true
		promoted.division = div
		result.effects.append(promoted.member_name + " 被提拔为 " + DIVISION_NAMES.get(div, "") + " 新首领")
	else:
		result.effects.append(DIVISION_NAMES.get(div, "") + " 暂无新首领")

func _force_release_oldest_prisoner(result: Dictionary):
	## 当第4人被审讯时，强制释放最早入狱的囚犯（不提供剩余情报）
	if prison_queue.is_empty():
		return
	var oldest_name: String = prison_queue.pop_front()
	var oldest: MemberState = members.get(oldest_name)
	if oldest == null:
		return

	oldest.is_imprisoned = false
	oldest.prison_turns_left = 0
	# 释放时降1星
	if oldest.rank > 0:
		oldest.rank -= 1
	# 0星变无部门
	if oldest.rank <= 0:
		oldest.rank = 0
		if not oldest.is_leader:
			oldest.division = Division.NONE
		result.effects.append(oldest.member_name + " 降为0星，变为自由人")
	else:
		result.effects.append(oldest.member_name + " 被强制释放（降至 " + str(oldest.rank) + " 星）")
	member_released.emit(oldest.member_name)

func _provide_intel_for_member(m: MemberState, result: Dictionary):
	## 根据成员星级为其部门提供情报
	if m.division == Division.NONE:
		return
	var rank_for_intel: int = maxi(1, m.rank)
	var gain: float = INTEL_PER_RANK.get(rank_for_intel, 0.10)
	intelligence[m.division] = minf(1.0, intelligence.get(m.division, 0.0) + gain)
	result.effects.append(DIVISION_NAMES.get(m.division, "") + " 情报 +" + str(int(gain * 100)) + "%")
	intelligence_changed.emit(m.division, intelligence[m.division])
	if intelligence[m.division] >= 1.0:
		safehouse_ready.emit(m.division)

# ================================================================
#                    处决 (Execute) — 重写
# ================================================================

func _do_execute(m: MemberState, result: Dictionary):
	# 星级提升
	if m.rank < 3:
		m.rank += 1
		result.effects.append(m.member_name + " 升至 " + str(m.rank) + " 星")
	else:
		result.effects.append(m.member_name + " 已是最高等级（3星）")

	# 0星成员入职当前遭遇部门
	if m.rank == 1 and m.division == Division.NONE:
		var enc_div: int = current_encounter.get("division", Division.NONE)
		if enc_div != Division.NONE and get_division_slot_count(enc_div) < MAX_MEMBERS_PER_DIVISION:
			m.division = enc_div
			result.effects.append(m.member_name + " 加入 " + DIVISION_NAMES.get(enc_div, ""))

	# 装备
	if m.equipment_count < 3:
		m.equipment_count += 1
		result.effects.append(m.member_name + " 获得辛迪加装备（" + str(m.equipment_count) + "/3）")

# ================================================================
#                    商谈 (Betray) — 重写
# ================================================================

func _do_betray(m: MemberState, result: Dictionary):
	## 商谈：需恰好剩2人，对另一人造成负面效果，建立宿敌关系
	var remaining := _get_remaining_encounter_members()
	var other: MemberState = null
	for rm in remaining:
		if rm.member_name != m.member_name:
			other = rm
			break

	if other == null:
		result.effects.append("商谈失败 — 没有目标")
		return

	# 建立宿敌关系（覆盖现有关系）
	var existing_rel = get_relationship_between(m.member_name, other.member_name)
	if existing_rel:
		relationships.erase(existing_rel)
	relationships.append(RelationshipEntry.new(m.member_name, other.member_name, RelationType.RIVALRY))
	result.effects.append(m.member_name + " 与 " + other.member_name + " 成为宿敌")

	# 随机结果
	var outcome := randi() % 7
	match outcome:
		0: # 获得另一个部门的情报
			var other_divs: Array = ALL_DIVISIONS.duplicate()
			other_divs.erase(m.division)
			if not other_divs.is_empty():
				var target_div: int = other_divs[randi() % other_divs.size()]
				var gain := 0.15
				intelligence[target_div] = minf(1.0, intelligence.get(target_div, 0.0) + gain)
				result.effects.append(DIVISION_NAMES.get(target_div, "") + " 情报 +" + str(int(gain * 100)) + "%")
				intelligence_changed.emit(target_div, intelligence[target_div])
				if intelligence[target_div] >= 1.0:
					safehouse_ready.emit(target_div)
		1: # 窃取对方星级
			if other.rank > 0:
				other.rank -= 1
				if other.rank <= 0:
					other.rank = 0
					if not other.is_leader:
						other.division = Division.NONE
					result.effects.append(other.member_name + " 降为0星，变为自由人")
				else:
					result.effects.append(other.member_name + " 降至 " + str(other.rank) + " 星")
			if m.rank < 3:
				m.rank += 1
				result.effects.append(m.member_name + " 升至 " + str(m.rank) + " 星")
		2: # 成为该部门新首领
			var enc_div: int = current_encounter.get("division", Division.NONE)
			if enc_div != Division.NONE:
				var old_leader = get_division_leader(enc_div)
				if old_leader and old_leader.member_name != m.member_name:
					old_leader.is_leader = false
					result.effects.append(old_leader.member_name + " 从首领下台")
				m.is_leader = true
				m.division = enc_div
				result.effects.append(m.member_name + " 成为 " + DIVISION_NAMES.get(enc_div, "") + " 新首领")
			else:
				result.effects.append(m.member_name + " 获得了额外奖励")
		3: # 将对方踢出辛迪加
			_kick_member_and_replace(other, result)
		4: # 摧毁另一部门所有成员装备
			var target_div := other.division
			if target_div != Division.NONE:
				var div_all := get_all_division_members(target_div)
				for dm in div_all:
					dm.equipment_count = 0
				result.effects.append(DIVISION_NAMES.get(target_div, "") + " 所有成员装备被摧毁")
			else:
				result.effects.append(m.member_name + " 获得了通货奖励")
		5: # 提升自己部门全员星级，降低对方部门全员星级
			if m.division != Division.NONE:
				var my_div_all := get_all_division_members(m.division)
				for dm in my_div_all:
					if dm.rank < 3:
						dm.rank += 1
				result.effects.append(DIVISION_NAMES.get(m.division, "") + " 全员星级+1")
			if other.division != Division.NONE and other.division != m.division:
				var their_div_all := get_all_division_members(other.division)
				for dm in their_div_all:
					if dm.rank > 1:
						dm.rank -= 1
				result.effects.append(DIVISION_NAMES.get(other.division, "") + " 全员星级-1")
		6: # 获得辛迪加装备
			if m.equipment_count < 3:
				m.equipment_count += 1
				result.effects.append(m.member_name + " 获得辛迪加装备（" + str(m.equipment_count) + "/3）")
			else:
				result.effects.append(m.member_name + " 获得了通货奖励")

# ================================================================
#                    谈判 (Bargain) — 重写
# ================================================================

func _do_bargain(m: MemberState, result: Dictionary):
	## 谈判：仅剩1人时的丰富结果
	var outcome := randi() % 9
	match outcome:
		0: # 获得某部门情报
			if m.division != Division.NONE:
				var gain := 0.20
				intelligence[m.division] = minf(1.0, intelligence.get(m.division, 0.0) + gain)
				result.effects.append(DIVISION_NAMES.get(m.division, "") + " 情报 +" + str(int(gain * 100)) + "%")
				intelligence_changed.emit(m.division, intelligence[m.division])
				if intelligence[m.division] >= 1.0:
					safehouse_ready.emit(m.division)
			else:
				# 自由人时随机给一个部门情报
				var rdiv: int = ALL_DIVISIONS[randi() % ALL_DIVISIONS.size()]
				var gain := 0.15
				intelligence[rdiv] = minf(1.0, intelligence.get(rdiv, 0.0) + gain)
				result.effects.append(DIVISION_NAMES.get(rdiv, "") + " 情报 +" + str(int(gain * 100)) + "%")
				intelligence_changed.emit(rdiv, intelligence[rdiv])
		1: # 招募无星级成员（升级+入部门+建立信任）
			var free := get_unassigned_members()
			var recruit: MemberState = null
			for f in free:
				if f.member_name != m.member_name and not f.is_imprisoned:
					recruit = f
					break
			if recruit:
				if recruit.rank < 3:
					recruit.rank += 1
				if m.division != Division.NONE and get_division_slot_count(m.division) < MAX_MEMBERS_PER_DIVISION:
					recruit.division = m.division
					result.effects.append(recruit.member_name + " 加入 " + DIVISION_NAMES.get(m.division, ""))
				# 建立信任
				var ex_rel = get_relationship_between(m.member_name, recruit.member_name)
				if ex_rel:
					relationships.erase(ex_rel)
				relationships.append(RelationshipEntry.new(m.member_name, recruit.member_name, RelationType.TRUST))
				result.effects.append(m.member_name + " 与 " + recruit.member_name + " 建立信任")
			else:
				result.effects.append("没有可招募的自由人")
		2: # 与同星级成员交换部门
			var swap_target: MemberState = null
			for mname in members:
				var candidate: MemberState = members[mname]
				if candidate.member_name == m.member_name:
					continue
				if candidate.is_on_board and not candidate.is_imprisoned \
				   and candidate.rank == m.rank and candidate.division != Division.NONE \
				   and candidate.division != m.division and not candidate.is_leader:
					swap_target = candidate
					break
			if swap_target:
				var tmp_div: int = m.division
				var tmp_leader: bool = m.is_leader
				m.division = swap_target.division
				m.is_leader = false
				swap_target.division = tmp_div
				swap_target.is_leader = false
				result.effects.append(m.member_name + " 与 " + swap_target.member_name + " 交换了部门")
			else:
				result.effects.append(m.member_name + " 提供了少量情报")
				if m.division != Division.NONE:
					intelligence[m.division] = minf(1.0, intelligence.get(m.division, 0.0) + 0.05)
					intelligence_changed.emit(m.division, intelligence[m.division])
		3: # 离开辛迪加（新人替换）
			_kick_member_and_replace(m, result)
		4: # 立即完成所有审讯
			var released_any := false
			for qname in prison_queue.duplicate():
				var prisoner: MemberState = members.get(qname)
				if prisoner == null:
					continue
				# 给予剩余情报
				var remaining_turns: int = prisoner.prison_turns_left
				for _t in range(remaining_turns):
					_provide_intel_for_member(prisoner, result)
				# 释放
				prisoner.is_imprisoned = false
				prisoner.prison_turns_left = 0
				if prisoner.rank > 0:
					prisoner.rank -= 1
				if prisoner.rank <= 0:
					prisoner.rank = 0
					if not prisoner.is_leader:
						prisoner.division = Division.NONE
				member_released.emit(prisoner.member_name)
				released_any = true
			prison_queue.clear()
			if released_any:
				result.effects.append("所有囚犯被立即释放，已获取全部剩余情报")
			else:
				result.effects.append("当前没有在押囚犯")
		5: # 摧毁该部门所有成员装备
			if m.division != Division.NONE:
				var div_all := get_all_division_members(m.division)
				for dm in div_all:
					dm.equipment_count = 0
				result.effects.append(DIVISION_NAMES.get(m.division, "") + " 所有成员装备被摧毁")
			else:
				result.effects.append(m.member_name + " 获得了通货奖励")
		6: # 获得情报 + 宿敌变中立
			if m.division != Division.NONE:
				var gain := 0.10
				intelligence[m.division] = minf(1.0, intelligence.get(m.division, 0.0) + gain)
				result.effects.append(DIVISION_NAMES.get(m.division, "") + " 情报 +" + str(int(gain * 100)) + "%")
				intelligence_changed.emit(m.division, intelligence[m.division])
			# 移除一个宿敌关系
			for rel in get_relationships_for(m.member_name):
				if rel.type == RelationType.RIVALRY:
					var rival_name: String = rel.member_b if rel.member_a == m.member_name else rel.member_a
					relationships.erase(rel)
					result.effects.append(m.member_name + " 与 " + rival_name + " 关系变为中立")
					break
		7: # 移除同部门内所有宿敌关系
			if m.division != Division.NONE:
				var div_members := get_all_division_members(m.division)
				var div_names: Array[String] = []
				for dm in div_members:
					div_names.append(dm.member_name)
				var removed := 0
				for rel in relationships.duplicate():
					if rel.type == RelationType.RIVALRY:
						if rel.member_a in div_names and rel.member_b in div_names:
							relationships.erase(rel)
							removed += 1
				if removed > 0:
					result.effects.append(DIVISION_NAMES.get(m.division, "") + " 内 " + str(removed) + " 个宿敌关系已移除")
				else:
					result.effects.append(DIVISION_NAMES.get(m.division, "") + " 内没有宿敌关系")
			else:
				result.effects.append(m.member_name + " 获得了通货奖励")
		8: # 掉落战利品
			var loot_table: Array = ["隐匿装备", "圣甲虫", "通货堆", "随机暗金", "随机地图"]
			var loot: String = loot_table[randi() % loot_table.size()]
			result.effects.append(m.member_name + " 掉落了 " + loot)

# ================================================================
#                    辅助方法
# ================================================================

func _kick_member_and_replace(m: MemberState, result: Dictionary):
	## 将成员踢出辛迪加，用板凳上的新人替换
	var kicked_name: String = m.member_name
	var was_leader: bool = m.is_leader
	var was_div: int = m.division

	# 移出棋盘
	m.is_on_board = false
	m.division = Division.NONE
	m.is_leader = false
	m.is_imprisoned = false
	m.is_revealed = false
	m.rank = 1
	m.equipment_count = 0
	if m.member_name in prison_queue:
		prison_queue.erase(m.member_name)

	result.effects.append(kicked_name + " 被踢出辛迪加")

	# 查找板凳成员替换
	var replacement: MemberState = null
	for mname in members:
		var candidate: MemberState = members[mname]
		if not candidate.is_on_board and candidate.member_name != kicked_name:
			replacement = candidate
			break

	if replacement:
		replacement.is_on_board = true
		replacement.division = Division.NONE
		replacement.is_leader = false
		replacement.rank = 1
		replacement.is_revealed = false
		replacement.equipment_count = 0
		replacement.is_imprisoned = false
		result.effects.append(replacement.member_name + " 作为新人加入辛迪加")
	else:
		result.effects.append("没有替补成员可用")

	# 如果被踢的是首领，处理首领继承
	if was_leader and was_div != Division.NONE:
		var candidates: Array = get_division_members(was_div)
		var valid: Array = []
		for c in candidates:
			if not c.is_imprisoned:
				valid.append(c)
		if valid.is_empty():
			var free := get_unassigned_members()
			for f in free:
				if not f.is_imprisoned:
					valid.append(f)
		if not valid.is_empty():
			var promoted: MemberState = valid[randi() % valid.size()]
			promoted.is_leader = true
			promoted.division = was_div
			result.effects.append(promoted.member_name + " 被提拔为 " + DIVISION_NAMES.get(was_div, "") + " 新首领")

# ===== 回合处理 =====
func _process_prison_intel():
	## 每次遭遇开始时处理在押囚犯：
	## - 剩余刑期-1
	## - 到期释放，降1星
	var to_release: Array[String] = []
	for mname in members:
		var m: MemberState = members[mname]
		if m.is_imprisoned:
			m.prison_turns_left -= 1
			if m.prison_turns_left <= 0:
				to_release.append(m.member_name)

	for rname in to_release:
		var m: MemberState = members[rname]
		m.is_imprisoned = false
		m.prison_turns_left = 0
		prison_queue.erase(rname)
		# 释放时降1星
		if m.rank > 0:
			m.rank -= 1
		# 0星变无部门
		if m.rank <= 0:
			m.rank = 0
			if not m.is_leader:
				m.division = Division.NONE
		member_released.emit(rname)

func _check_encounter_end():
	if current_encounter.is_empty():
		return
	for m in current_encounter.get("members", []):
		if m.member_name not in current_encounter.get("processed", []):
			return
	# 当前遭遇完成
	current_encounter.clear()
	encounter_ended.emit()

# ===== 藏身处 =====
func can_raid_safehouse(div: int) -> bool:
	return intelligence.get(div, 0.0) >= 1.0

func raid_safehouse(div: int):
	if not can_raid_safehouse(div):
		return
	var leader = get_division_leader(div)
	if leader:
		mastermind_intel = minf(1.0, mastermind_intel + MASTERMIND_INTEL_PER_RAID)
		leader.is_leader = false
		leader.division = Division.NONE
	for m in get_division_members(div):
		m.division = Division.NONE
		m.is_leader = false
	intelligence[div] = 0.0
	intelligence_changed.emit(div, 0.0)
	if mastermind_intel >= 1.0:
		mastermind_ready.emit()
	board_changed.emit()

# ===== 主脑 =====
func can_fight_mastermind() -> bool:
	return mastermind_intel >= 1.0

func fight_mastermind():
	if not can_fight_mastermind():
		return
	mastermind_intel = 0.0
	var result := {"action": "mastermind", "effects": ["击败了主脑卡塔莉娜！", "获得了独特奖励！"]}
	action_executed.emit(result)
	board_changed.emit()

# ===== 工具函数 =====
func get_action_name(action: int) -> String:
	match action:
		ActionType.INTERROGATE: return "审讯"
		ActionType.EXECUTE: return "处决"
		ActionType.BARGAIN: return "谈判"
		ActionType.BETRAY: return "商谈"
		ActionType.RELEASE: return "释放"
	return ""

func get_action_description(action: int) -> String:
	match action:
		ActionType.INTERROGATE: return "监禁3次遭遇，根据星级获取情报，释放时降1星"
		ActionType.EXECUTE: return "星级+1，0星入职部门，获得装备（≥3人时可用）"
		ActionType.BARGAIN: return "获得奖励或改变全局状态（仅剩1人时）"
		ActionType.BETRAY: return "以另一名成员为代价获得利益，建立宿敌（剩2人时）"
		ActionType.RELEASE: return "释放，不改变棋盘"
	return ""
