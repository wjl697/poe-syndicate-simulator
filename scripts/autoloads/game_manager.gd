extends Node

const ActionLogic = preload("res://scripts/gameplay/action_logic.gd")

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
enum ActionType { INTERROGATE, EXECUTE, BARGAIN, BETRAY, RELEASE, FORM_TRUST, FORM_RIVALRY }

# ===== 常量 =====
const MAX_SUBORDINATES_PER_DIVISION := 4    # 每部门最多4个手下
const MAX_MEMBERS_PER_DIVISION := 5         # 1首领 + 4手下
const MAX_IMPRISONED := 3                   # 最多同时在押3人
const PRISON_DURATION := 3                  # 监禁持续3次遭遇
const ACTIVE_MEMBER_COUNT := 14             # 每局14人上场
const MAX_ENCOUNTER_MEMBERS := 4            # 单场遭遇最多4人
const MASTERMIND_INTEL_PER_RAID := 0.34

# 情报规则（按“点”计算，1点=1%）
const INTEL_POINT_RATIO := 0.01
const INTEL_READY_THRESHOLD_POINTS := 100
const PRISON_INTEL_PER_TURN_BY_RANK := {
	0: 1,
	1: 3,
	2: 5,
	3: 7,
}
const BARGAIN_INTEL_GAIN_POINTS := 10
const BARGAIN_INTEL_LARGE_MIN_POINTS := 15
const BARGAIN_INTEL_LARGE_MAX_POINTS := 18
const BARGAIN_RELEASE_ALL_BONUS := 1.2
const BETRAY_STEAL_MIN_POINTS := 10
const BETRAY_STEAL_MAX_POINTS := 15
const BETRAY_FOR_INTEL_POINTS := 12

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
	var prison_rank_snapshot: int = -1      # 入狱时军衔快照（用于固定产出）
	var prison_intel_per_turn_points: int = 0
	var is_on_board: bool = true
	var cached_betray_effect: int = -1   # 预先Roll好的背叛结果
	var cached_bargain_effect: int = -1  # 预先Roll好的商谈结果
	var cached_bargain_target: String = "" # 预先Roll好的商谈目标
	var is_revealed: bool = false
	var equipment_count: int = 0            # 辛迪加装备(上限3)

	func _init(p_name: String = "", p_portrait: String = ""):
		member_name = p_name
		portrait_path = p_portrait

	func clone() -> MemberState:
		var c = MemberState.new(member_name, portrait_path)
		c.division = division
		c.is_leader = is_leader
		c.rank = rank
		c.is_imprisoned = is_imprisoned
		c.prison_turns_left = prison_turns_left
		c.prison_rank_snapshot = prison_rank_snapshot
		c.prison_intel_per_turn_points = prison_intel_per_turn_points
		c.is_on_board = is_on_board
		c.cached_betray_effect = cached_betray_effect
		c.cached_bargain_effect = cached_bargain_effect
		c.cached_bargain_target = cached_bargain_target
		c.is_revealed = is_revealed
		c.equipment_count = equipment_count
		return c

class RelationshipEntry:
	var member_a: String
	var member_b: String
	var type: int
	func _init(a: String = "", b: String = "", t: int = 0):
		member_a = a
		member_b = b
		type = t

	func clone() -> RelationshipEntry:
		return RelationshipEntry.new(member_a, member_b, type)

# ===== 状态变量 =====
var members: Dictionary = {}                # name -> MemberState
var relationships: Array = []               # Array[RelationshipEntry]
var intelligence: Dictionary = {}           # Division -> float (0.0-1.0)
var mastermind_intel: float = 0.0
var turn_count: int = 0
var current_encounter: Dictionary = {}      # {division, members, processed}
var encounter_queue: Array[Dictionary] = [] # 多部门遭遇队列
var prison_queue: Array[String] = []        # 按入狱顺序记录名字
var history_stack: Array[Dictionary] = []   # 用于回退的状态栈

# ===== 信号 =====
signal state_restored()

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
	history_stack.clear()

	for div in ALL_DIVISIONS:
		intelligence[div] = 0.0

	for mname in MEMBER_DEFS:
		var portrait = "res://辛迪加素材/人员/" + mname + ".png"
		members[mname] = MemberState.new(mname, portrait)

	_assign_members_randomly()
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
	
	# 随机决定使用哪种分配方法：
	# 如果随机到 4：每个部门都会分配到 2 个部下，剩下 2 个自由人。
	# 如果随机到 3：有三个部门会分配到 2 个部下，一个部门只有 1 个部下，剩下 3 个自由人。
	var extra_budget: int = [3, 4].pick_random()
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
		m.rank = 0
		idx += 1

func _generate_initial_relationships():
	# 关系线（信任/仇敌）只允许由玩家操作手动指定。
	return

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

func _to_intel_ratio(points: int) -> float:
	return float(points) * INTEL_POINT_RATIO

func _to_intel_points(value: float) -> int:
	return int(round(value * 100.0))

func _add_intel_points_to_division(div: int, points: int) -> int:
	if div == Division.NONE or points <= 0:
		return 0
	var old_points := _to_intel_points(intelligence.get(div, 0.0))
	var new_points := mini(INTEL_READY_THRESHOLD_POINTS, old_points + points)
	intelligence[div] = _to_intel_ratio(new_points)
	intelligence_changed.emit(div, intelligence[div])
	if new_points >= INTEL_READY_THRESHOLD_POINTS:
		safehouse_ready.emit(div)
	return new_points - old_points

func _remove_intel_points_from_division(div: int, points: int) -> int:
	if div == Division.NONE or points <= 0:
		return 0
	var old_points := _to_intel_points(intelligence.get(div, 0.0))
	var new_points := maxi(0, old_points - points)
	intelligence[div] = _to_intel_ratio(new_points)
	intelligence_changed.emit(div, intelligence[div])
	return old_points - new_points

func _get_prison_intel_points_by_rank(rank: int) -> int:
	var safe_rank := clampi(rank, 0, 3)
	return PRISON_INTEL_PER_TURN_BY_RANK.get(safe_rank, 1)

func _resolve_intel_division_for_member(m: MemberState) -> int:
	if m.division != Division.NONE:
		return m.division
	return current_encounter.get("division", Division.NONE)

func _pick_random_other_division(base_div: int) -> int:
	var choices: Array[int] = []
	for div in ALL_DIVISIONS:
		if base_div == Division.NONE or div != base_div:
			choices.append(div)
	if choices.is_empty():
		return Division.NONE
	return choices[randi() % choices.size()]

func _set_relationship_type(a: String, b: String, rel_type: int):
	var existing = get_relationship_between(a, b)
	if existing:
		relationships.erase(existing)
	relationships.append(RelationshipEntry.new(a, b, rel_type))

func _remove_relationship(a: String, b: String):
	var existing = get_relationship_between(a, b)
	if existing:
		relationships.erase(existing)

func _release_imprisoned_member(m: MemberState, apply_rank_penalty: bool = true):
	m.is_imprisoned = false
	m.prison_turns_left = 0
	m.prison_rank_snapshot = -1
	m.prison_intel_per_turn_points = 0
	prison_queue.erase(m.member_name)

	if apply_rank_penalty:
		if m.rank > 0:
			m.rank -= 1
		if m.rank <= 0:
			m.rank = 0
			if not m.is_leader:
				m.division = Division.NONE

	member_released.emit(m.member_name)

func _auto_fill_division_if_leader_only(div: int) -> String:
	## 若某部门仅剩首领：
	## 1) 优先从自由人中随机补1名下属
	## 2) 若无自由人，则从该部门在押成员中随机拉出1人，强制结束剩余审讯回合
	var leader: MemberState = get_division_leader(div)
	if leader == null:
		return ""

	var subordinates: Array = get_division_members(div)
	if not subordinates.is_empty():
		return ""

	var div_name: String = DIVISION_NAMES.get(div, "未知部门")
	var free_candidates: Array = []
	for mname in members:
		var m: MemberState = members[mname]
		if not m.is_on_board:
			continue
		if m.is_leader or m.is_imprisoned:
			continue
		if m.division == Division.NONE:
			free_candidates.append(m)

	if not free_candidates.is_empty():
		var picked: MemberState = free_candidates[randi() % free_candidates.size()]
		picked.division = div
		picked.is_leader = false
		# 自由人加入部门后至少为1星，确保其成为有效下属
		if picked.rank <= 0:
			picked.rank = 1
		return div_name + " 仅剩首领，系统自动补员：" + picked.member_name + " 加入该部门"

	var imprisoned_candidates: Array = []
	for mname in members:
		var prisoner: MemberState = members[mname]
		if not prisoner.is_on_board or not prisoner.is_imprisoned:
			continue
		if prisoner.division != div:
			continue
		if prisoner.is_leader:
			continue
		imprisoned_candidates.append(prisoner)

	if imprisoned_candidates.is_empty():
		return ""

	var forced_release: MemberState = imprisoned_candidates[randi() % imprisoned_candidates.size()]
	# 系统强制结束该成员剩余审讯回合，不额外降星，直接回归部门作为部下
	_release_imprisoned_member(forced_release, false)
	if forced_release.rank <= 0:
		forced_release.rank = 1
	forced_release.division = div
	forced_release.is_leader = false
	return div_name + " 无自由人可补位，系统强制结束 " + forced_release.member_name + " 的剩余审讯回合并令其回归部门"

func _apply_auto_subordinate_refill() -> Array[String]:
	## 对所有部门执行“仅剩首领自动补位”
	var messages: Array[String] = []
	for div in ALL_DIVISIONS:
		var refill_message: String = _auto_fill_division_if_leader_only(div)
		if refill_message == "":
			continue
		print("[自动补员] ", refill_message)
		messages.append(refill_message)
	return messages

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
	save_state()
	## 生成一个回合的遭遇，返回第一个遭遇事件
	turn_count += 1
	turn_advanced.emit(turn_count)

	encounter_queue.clear()
	current_encounter.clear()
	_apply_auto_subordinate_refill()

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

	# ====== DEBUG: 打印生成前所有自由人的实时状态 ======
	for _mn in members:
		var _m: MemberState = members[_mn]
		if _m.division == Division.NONE and _m.is_on_board:
			print("[DEBUG 生成前] 自由人: ", _mn, " rank=", _m.rank, " revealed=", _m.is_revealed)
	# ====== DEBUG END ======

	# 为每个部门生成遭遇事件
	# used_members 确保同一成员在同一回合只出现在一场遭遇战中
	var used_members: Dictionary = {}
	for div in divisions_this_turn:
		var enc := _generate_single_encounter(div, used_members)
		if not enc.is_empty():
			for m in enc.get("members", []):
				used_members[m.member_name] = true
			encounter_queue.append(enc)

	if encounter_queue.is_empty():
		return {}

	# 启动第一个遭遇（先根据上一轮在押人员承接回合）
	current_encounter = encounter_queue.pop_front()
	_process_prison_intel()
	_reveal_encounter_members(current_encounter)

	# ===== 日志：遭遇开始 =====
	_log_encounter_start(current_encounter)

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

func _has_unrevealed_members() -> bool:
	## 只检查非首领成员（部下 + 自由人）是否还有未翻牌的。
	## 首领卡自身的翻牌状态不影响该判断，避免"首领阻止首领出场"的死锁。
	for mname in members:
		var m: MemberState = members[mname]
		if m.is_on_board and not m.is_revealed and not m.is_leader:
			return true
	return false

func _generate_single_encounter(div: int, used_members: Dictionary = {}) -> Dictionary:
	## 按 "主成员 + 增援" 模型生成单个部门遭遇
	## used_members: 本回合已被其他遭遇战锁定的成员名集合，不得重复选入
	var enc_members: Array = []
	var has_unrevealed := _has_unrevealed_members()

	# --- 1. 选择主成员（非首领的部门下属） ---
	var subordinates: Array = []
	for mname in members:
		var m: MemberState = members[mname]
		if m.division == div and not m.is_leader and m.is_on_board and not m.is_imprisoned:
			if mname not in used_members:  # 不重复选入其他遭遇战已用的成员
				subordinates.append(m)

	if subordinates.is_empty():
		# 该部门没有可出战的下属，首领不单独出场，跳过本次遭遇
		print("[遭遇生成] ", DIVISION_NAMES.get(div, str(div)), " 无可用下属，跳过（首领不单独出场）")
		return {}
	else:
		# 随机选一个下属作为主成员
		var primary: MemberState = subordinates[randi() % subordinates.size()]
		enc_members.append(primary)

	var primary_name: String = enc_members[0].member_name
	print("[DEBUG 遭遇] 部门: ", GameManager.DIVISION_NAMES.get(div, str(div)), " | 主成员: ", primary_name, " (div=", enc_members[0].division, ")")

	# --- 2. 增援：同部门成员（极高概率） ---
	for mname in members:
		if enc_members.size() >= MAX_ENCOUNTER_MEMBERS:
			break
		if mname in used_members:
			continue
		var m: MemberState = members[mname]
		if m.member_name == primary_name:
			continue
		if m.is_leader and has_unrevealed:
			continue
		
		if m.division == div and m.is_on_board and not m.is_imprisoned:
			if randf() < 0.85:  # 同部门极高概率
				enc_members.append(m)
				print("[DEBUG 遭遇]   +同部门增援: ", m.member_name, " (div=", m.division, ")")

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
		if candidate.member.member_name in used_members:
			continue
			
		if candidate.member.is_leader and has_unrevealed:
			continue
			
		var prob: float
		if candidate.type == RelationType.TRUST:
			prob = 0.50  # 盟友中等概率
		else:
			prob = 0.40  # 死敌中等概率
		if randf() < prob:
			enc_members.append(candidate.member)
			print("[DEBUG 遭遇]   +关系增援: ", candidate.member.member_name, " (div=", candidate.member.division, ", rel_type=", candidate.type, ")")

	# --- 4. 增援：自由人（中等概率） ---
	# 如果部门未满员且遭遇战还有空位，自由人（无部门）有概率加入遭遇，从而试图加入该部门
	if get_division_slot_count(div) < MAX_MEMBERS_PER_DIVISION:
		var free_agents: Array = []
		for mname in members:
			var m: MemberState = members[mname]
			if m.division == Division.NONE and m.is_on_board and not m.is_imprisoned:
				free_agents.append(m)
				
		free_agents.shuffle()
		for m in free_agents:
			if enc_members.size() >= MAX_ENCOUNTER_MEMBERS:
				break
			if m.member_name in used_members:
				continue
			
			# 确保未加入
			var already := false
			for em in enc_members:
				if em.member_name == m.member_name:
					already = true
					break
			
			if not already and randf() < 0.35:  # 给予自由人 35% 的概率加入遭遇战
				enc_members.append(m)
				print("[DEBUG 遭遇]   +自由人乱入: ", m.member_name, " (div=", m.division, ")")

	return {
		"division": div,
		"members": enc_members,
		"processed": [],
	}

func _reveal_encounter_members(enc: Dictionary):
	for m in enc.get("members", []):
		reveal_member(m.member_name)

func _log_encounter_start(enc: Dictionary):
	## 统一的遭遇开始日志辅助函数
	var div_name: String = DIVISION_NAMES.get(enc.get("division", Division.NONE), "未知")
	var member_descs: Array = []
	for m in enc.get("members", []):
		var div_str: String = DIVISION_NAMES.get(m.division, "自由") if m.division != Division.NONE else "自由"
		member_descs.append(m.member_name + "(" + str(m.rank) + "星/" + div_str + ")")
	print("[遭遇开始] ", div_name, " | 成员: ", ", ".join(member_descs))

func advance_encounter_queue() -> Dictionary:
	save_state()
	## 当前遭遇完成后，推进到队列中的下一个
	if encounter_queue.is_empty():
		return {}

	# 在进入下一场遭遇战前，先处理“仅剩首领自动补位”
	# 这样可在同一回合内于“下一次遭遇战”立即生效，而不是等到下一回合。
	var refill_messages: Array[String] = _apply_auto_subordinate_refill()
	for msg in refill_messages:
		print("[遭遇切换补位] ", msg)

	current_encounter = encounter_queue.pop_front()
	_process_prison_intel()
	ActionLogic.refresh_action_caches(self) # 每次新遭遇开启时刷新随机缓存
	_reveal_encounter_members(current_encounter)

	# ===== 日志：遭遇开始 =====
	_log_encounter_start(current_encounter)

	encounter_started.emit(current_encounter)
	board_changed.emit()
	encounter_queue_advanced.emit(encounter_queue.size())
	return current_encounter

# ================================================================
#                   操作可用性 / 执行（集中到 ActionLogic）
# ================================================================

func get_available_actions(member: MemberState) -> Array:
	return ActionLogic.get_available_actions(self, member)

func execute_action(member_name: String, action: int):
	save_state()
	var result: Dictionary = ActionLogic.execute_action(self, member_name, action)
	if result.is_empty():
		return

	current_encounter.get("processed", []).append(member_name)
	ActionLogic.refresh_action_caches(self)

	# ===== 日志：动作执行摘要 =====
	var aname := ActionLogic.get_action_name(self, action)
	print("[行动] ", member_name, " → ", aname)
	for eff in result.get("effects", []):
		print("  └ ", eff)
	# 打印执行后成员关键状态
	var m_after: MemberState = members.get(member_name)
	if m_after:
		print("  [状态] rank=", m_after.rank,
			" | div=", DIVISION_NAMES.get(m_after.division, "自由人"),
			" | imprisoned=", m_after.is_imprisoned)

	action_executed.emit(result)
	board_changed.emit()
	_check_encounter_end()

# ===== 回合处理 =====
func _process_prison_intel():
	## 新一个部门遭遇开启时处理在押囚犯：
	## - 按入狱军衔提供当次遭遇情报
	## - 剩余刑期-1
	## - 到期释放，降1星
	## 注：本函数在遭遇开启时调用，同一次遭遇中被关押的人不会被计算，
	## 因为关押操作发生在这次调用之后。
	var to_release: Array[String] = []
	for mname in members:
		var m: MemberState = members[mname]
		if m.is_imprisoned:
			var intel_div := _resolve_intel_division_for_member(m)
			var tick_points := m.prison_intel_per_turn_points
			if tick_points <= 0:
				var snapshot_rank := m.prison_rank_snapshot if m.prison_rank_snapshot >= 0 else m.rank
				tick_points = _get_prison_intel_points_by_rank(snapshot_rank)
			_add_intel_points_to_division(intel_div, tick_points)
			m.prison_turns_left -= 1
			if m.prison_turns_left <= 0:
				to_release.append(m.member_name)

	for rname in to_release:
		var m: MemberState = members[rname]
		_release_imprisoned_member(m, true)

func _check_encounter_end():
	if current_encounter.is_empty():
		return
	for m in current_encounter.get("members", []):
		if m.member_name not in current_encounter.get("processed", []):
			return
	# 当前遭遇完成
	var div_name: String = DIVISION_NAMES.get(current_encounter.get("division", 0), "未知")
	print("[遭遇结束] ", div_name, " | 处理人数: ", current_encounter.get("processed", []).size())
	current_encounter.clear()
	encounter_ended.emit()

# ===== 藏身处 =====
func can_raid_safehouse(div: int) -> bool:
	return intelligence.get(div, 0.0) >= 1.0

func raid_safehouse(div: int):
	if not can_raid_safehouse(div):
		return
	save_state()
	var leader = get_division_leader(div)
	if leader:
		mastermind_intel = minf(1.0, mastermind_intel + MASTERMIND_INTEL_PER_RAID)
		leader.is_leader = false
		leader.division = Division.NONE
		leader.rank = 0
		print("[DEBUG 处决] ", leader.member_name, " 部门已设为 NONE")
	for m in get_division_members(div):
		m.division = Division.NONE
		m.is_leader = false
		m.rank = 0
		print("[DEBUG 处决] ", m.member_name, " 部门已设为 NONE")
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
	save_state()
	mastermind_intel = 0.0
	var result := {"action": "mastermind", "effects": ["击败了主脑卡塔莉娜！", "获得了独特奖励！"]}
	action_executed.emit(result)
	board_changed.emit()

# ===== 撤销系统 =====
func save_state():
	var state = {}
	state.members = {}
	for k in members:
		state.members[k] = members[k].clone()
	state.relationships = []
	for rel in relationships:
		state.relationships.append(rel.clone())
	state.intelligence = intelligence.duplicate()
	state.mastermind_intel = mastermind_intel
	state.turn_count = turn_count
	
	state.current_encounter = current_encounter.duplicate()
	if current_encounter.has("members"):
		var ce_m = []
		for m in current_encounter.members:
			ce_m.append(state.members[m.member_name])
		state.current_encounter.members = ce_m
	if current_encounter.has("processed"):
		state.current_encounter.processed = current_encounter.processed.duplicate()
		
	var eq: Array[Dictionary] = []
	for enc in encounter_queue:
		var c_enc = enc.duplicate()
		if enc.has("members"):
			var eq_m = []
			for m in enc.members:
				eq_m.append(state.members[m.member_name])
			c_enc.members = eq_m
		if enc.has("processed"):
			c_enc.processed = enc.processed.duplicate()
		eq.append(c_enc)
	state.encounter_queue = eq
		
	var pq: Array[String] = []
	pq.append_array(prison_queue)
	state.prison_queue = pq
	
	history_stack.append(state)
	if history_stack.size() > 10:
		history_stack.pop_front()

func can_undo() -> bool:
	return not history_stack.is_empty()

func undo():
	if history_stack.is_empty():
		return
	var state = history_stack.pop_back()
	members = state.members
	relationships = state.relationships
	intelligence = state.intelligence
	mastermind_intel = state.mastermind_intel
	turn_count = state.turn_count
	current_encounter = state.current_encounter
	
	encounter_queue.clear()
	encounter_queue.append_array(state.encounter_queue)
	
	prison_queue.clear()
	prison_queue.append_array(state.prison_queue)
	
	for div in ALL_DIVISIONS:
		intelligence_changed.emit(div, intelligence.get(div, 0.0))
	state_restored.emit()
	board_changed.emit()
	if not current_encounter.is_empty():
		encounter_started.emit(current_encounter)
	else:
		encounter_ended.emit()
	encounter_queue_advanced.emit(encounter_queue.size())

# ===== 工具函数 =====
func get_action_name(action: int) -> String:
	return ActionLogic.get_action_name(self, action)

func get_action_description(action: int) -> String:
	return ActionLogic.get_action_description(self, action)
