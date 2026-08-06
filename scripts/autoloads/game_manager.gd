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
	Division.TRANSPORT: "res://辛迪加素材/界面UI/运输部角标.png",
	Division.FORTIFICATION: "res://辛迪加素材/界面UI/防卫部角标.png",
	Division.RESEARCH: "res://辛迪加素材/界面UI/科研部角标.png",
	Division.INTERVENTION: "res://辛迪加素材/界面UI/调停部角标.png",
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
	var prison_intel_division: int = 0      # 关押期间情报贡献去向部门 (Division.NONE=0)
	var has_pending_prison_penalty: bool = false # 延迟执行的出狱降星惩罚

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
		c.prison_intel_division = prison_intel_division
		c.has_pending_prison_penalty = has_pending_prison_penalty
		return c

	func to_dict() -> Dictionary:
		return {
			"member_name": member_name,
			"portrait_path": portrait_path,
			"division": division,
			"is_leader": is_leader,
			"rank": rank,
			"is_imprisoned": is_imprisoned,
			"prison_turns_left": prison_turns_left,
			"prison_rank_snapshot": prison_rank_snapshot,
			"prison_intel_per_turn_points": prison_intel_per_turn_points,
			"is_on_board": is_on_board,
			"cached_betray_effect": cached_betray_effect,
			"cached_bargain_effect": cached_bargain_effect,
			"cached_bargain_target": cached_bargain_target,
			"is_revealed": is_revealed,
			"equipment_count": equipment_count,
			"prison_intel_division": prison_intel_division,
			"has_pending_prison_penalty": has_pending_prison_penalty
		}

	static func from_dict(d: Dictionary) -> MemberState:
		var m = MemberState.new(d.get("member_name", ""), d.get("portrait_path", ""))
		m.update_from_dict(d)
		return m

	func update_from_dict(d: Dictionary):
		division = int(d.get("division", 0))
		is_leader = bool(d.get("is_leader", false))
		rank = int(d.get("rank", 1))
		is_imprisoned = bool(d.get("is_imprisoned", false))
		prison_turns_left = int(d.get("prison_turns_left", 0))
		prison_rank_snapshot = int(d.get("prison_rank_snapshot", -1))
		prison_intel_per_turn_points = int(d.get("prison_intel_per_turn_points", 0))
		is_on_board = bool(d.get("is_on_board", true))
		cached_betray_effect = int(d.get("cached_betray_effect", -1))
		cached_bargain_effect = int(d.get("cached_bargain_effect", -1))
		cached_bargain_target = d.get("cached_bargain_target", "")
		is_revealed = bool(d.get("is_revealed", false))
		equipment_count = int(d.get("equipment_count", 0))
		prison_intel_division = int(d.get("prison_intel_division", 0))
		has_pending_prison_penalty = bool(d.get("has_pending_prison_penalty", false))

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

	func to_dict() -> Dictionary:
		return {
			"member_a": member_a,
			"member_b": member_b,
			"type": type
		}

	static func from_dict(d: Dictionary) -> RelationshipEntry:
		return RelationshipEntry.new(d.get("member_a", ""), d.get("member_b", ""), int(d.get("type", 0)))

# ===== 状态变量 =====
var is_sandbox_mode: bool = false            # 是否处于沙盒调试/自由布阵模式
var bench_pool: Array[String] = []          # 替补席成员名单
var members: Dictionary = {}                # name -> MemberState

var relationships: Array = []               # Array[RelationshipEntry]
var intelligence: Dictionary = {}           # Division -> float (0.0-1.0)
var safehouse_100_turns: Dictionary = {}    # Division -> int (turn count when reached 100%)
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
	randomize() # 确保随机种子每次运行不同
	members.clear()
	relationships.clear()
	intelligence.clear()
	safehouse_100_turns.clear()
	turn_count = 0
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
	var bench_list: Array = pool.slice(ACTIVE_MEMBER_COUNT)

	bench_pool.clear()
	for mname in bench_list:
		bench_pool.append(mname)

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
		if not safehouse_100_turns.has(div):
			safehouse_100_turns[div] = turn_count
			print("[DEBUG 安全屋就绪] 部门 ", DIVISION_NAMES.get(div, ""), " 达到 100% 情报，在回合 ", turn_count, " 开始记录")
	return new_points - old_points

func _remove_intel_points_from_division(div: int, points: int) -> int:
	if div == Division.NONE or points <= 0:
		return 0
	var old_points := _to_intel_points(intelligence.get(div, 0.0))
	var new_points := maxi(0, old_points - points)
	intelligence[div] = _to_intel_ratio(new_points)
	intelligence_changed.emit(div, intelligence[div])
	if new_points < INTEL_READY_THRESHOLD_POINTS:
		safehouse_100_turns.erase(div)
	return old_points - new_points

func _get_prison_intel_points_by_rank(rank: int) -> int:
	var safe_rank := clampi(rank, 0, 3)
	return PRISON_INTEL_PER_TURN_BY_RANK.get(safe_rank, 1)

func _resolve_intel_division_for_member(m: MemberState) -> int:
	if m.prison_intel_division != Division.NONE:
		return m.prison_intel_division
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
	var type_str = "信任" if rel_type == RelationType.TRUST else ("敌对" if rel_type == RelationType.RIVALRY else "中立")
	print("[关系变更] ", a, " 与 ", b, " 的关系变更为: ", type_str)
	var existing = get_relationship_between(a, b)
	if existing:
		relationships.erase(existing)
	relationships.append(RelationshipEntry.new(a, b, rel_type))

func _remove_relationship(a: String, b: String):
	print("[关系变更] 移除 ", a, " 与 ", b, " 之间的所有关系 (变回中立)")
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
	# 系统强制结束该成员剩余审讯回合并扣减一星级，直接回归部门作为部下
	_release_imprisoned_member(forced_release, true)
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

	# 检查满情报的部门是否在3个遭遇战回合内未突袭，强行掉落至90%
	var to_decay := []
	for div in safehouse_100_turns:
		if turn_count - safehouse_100_turns[div] >= 3:
			to_decay.append(div)
	for div in to_decay:
		intelligence[div] = 0.9
		safehouse_100_turns.erase(div)
		intelligence_changed.emit(div, 0.9)
		print("[DEBUG 情报衰减] 部门 ", DIVISION_NAMES.get(div, ""), " 情报已满 3 回合未突袭，衰减至 90%")

	encounter_queue.clear()
	current_encounter.clear()
	_apply_auto_subordinate_refill()

	# 确定本回合出现的部门（最多3个）
	# 运输/防卫 二选一 + 研究 + 调停
	var divisions_this_turn: Array[int] = []

	# 运输 or 防卫
	var tf_candidates: Array[int] = []
	if _division_has_encounterable(Division.TRANSPORT) and intelligence.get(Division.TRANSPORT, 0.0) < 1.0:
		tf_candidates.append(Division.TRANSPORT)
	if _division_has_encounterable(Division.FORTIFICATION) and intelligence.get(Division.FORTIFICATION, 0.0) < 1.0:
		tf_candidates.append(Division.FORTIFICATION)
	if not tf_candidates.is_empty():
		divisions_this_turn.append(tf_candidates[randi() % tf_candidates.size()])

	# 研究
	if _division_has_encounterable(Division.RESEARCH) and intelligence.get(Division.RESEARCH, 0.0) < 1.0:
		divisions_this_turn.append(Division.RESEARCH)

	# 调停
	if _division_has_encounterable(Division.INTERVENTION) and intelligence.get(Division.INTERVENTION, 0.0) < 1.0:
		divisions_this_turn.append(Division.INTERVENTION)

	if divisions_this_turn.is_empty():
		return {}

	divisions_this_turn.shuffle()

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

	# 启动第一个遭遇（如果第一个被跳过，则循环推进直至找到有效的，或队列为空）
	current_encounter = {}
	while not encounter_queue.is_empty():
		var enc = encounter_queue.pop_front()
		_check_and_release_imprisoned_subordinates_for_encounter(enc)
		_validate_encounter(enc)
		if not enc.get("members", []).is_empty():
			current_encounter = enc
			break
			
	if current_encounter.is_empty():
		# 队列里所有遭遇战均被跳过
		board_changed.emit()
		encounter_queue_advanced.emit(encounter_queue.size())
		save_game_to_disk()
		return {}
	
	_process_prison_intel()
	_reveal_encounter_members(current_encounter)

	# ===== 日志：遭遇开始 =====
	_log_encounter_start(current_encounter)

	encounter_started.emit(current_encounter)
	board_changed.emit()
	encounter_queue_advanced.emit(encounter_queue.size())
	save_game_to_disk()
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
		# 检查是否有在押的下属（允许被加入该部门的遭遇战中，等遭遇开启时才释放）
		var imprisoned_subs: Array = []
		for mname in members:
			var m: MemberState = members[mname]
			if m.division == div and not m.is_leader and m.is_on_board and m.is_imprisoned:
				if mname not in used_members:
					imprisoned_subs.append(m)
		
		if not imprisoned_subs.is_empty():
			var primary: MemberState = imprisoned_subs[randi() % imprisoned_subs.size()]
			enc_members.append(primary)
			print("[遭遇生成] 部门 ", DIVISION_NAMES.get(div, str(div)), " 无活跃下属，但允许在押下属 ", primary.member_name, " 参与该遭遇战（开启时释放）")
		else:
			# 该部门确实没有任何下属（无论是活跃还是在押），首领不单独出场，跳过本次遭遇
			print("[遭遇生成] ", DIVISION_NAMES.get(div, str(div)), " 无可用下属，跳过（首领不单独出场）")
			return {}
	else:
		# 随机选一个下属作为主成员
		var primary: MemberState = subordinates[randi() % subordinates.size()]
		enc_members.append(primary)

	var primary_name: String = enc_members[0].member_name
	print("[DEBUG 遭遇] 部门: ", GameManager.DIVISION_NAMES.get(div, str(div)), " | 主成员: ", primary_name, " (div=", enc_members[0].division, ")")

	# ====== 新的 PoE 加权抽样 + 槽位触发逻辑（微信拉群邀请模型） ======

	# 1. 检查全局遭遇锁定（只读锁定）
	var is_locked := false
	if not current_encounter.is_empty():
		for m in current_encounter.get("members", []):
			if m.member_name not in current_encounter.get("processed", []):
				is_locked = true
				break
	if is_locked:
		print("[遭遇生成] 检测到前场未决遭遇锁定，强制退化为单人遭遇战")
		return {
			"division": div,
			"members": enc_members,
			"processed": []
		}

	# 2. 检查首领是否合规
	var leader: MemberState = null
	for mname in members:
		var m: MemberState = members[mname]
		if m.division == div and m.is_leader:
			leader = m
			break

	var leader_eligible := false
	if leader != null and not leader.is_imprisoned and leader.is_on_board and not leader.member_name in used_members:
		if not has_unrevealed:
			var has_rel = get_relationship_between(primary_name, leader.member_name) != null
			var total_ranks := 0
			for check_mname in members:
				var check_m: MemberState = members[check_mname]
				if check_m.division == div and check_m.is_on_board and not check_m.is_imprisoned:
					total_ranks += check_m.rank
			if has_rel or total_ranks >= 3:
				leader_eligible = true

	# 3. 首领第一通道（VIP 判定）
	var leader_deployed_via_vip := false
	if leader_eligible:
		var base_leader_vip_rate := 0.05
		var more_leader_modifier := 2.0  # 对应 100% 增加几率天赋
		var final_leader_vip_rate = base_leader_vip_rate * more_leader_modifier
		if randf() <= final_leader_vip_rate:
			enc_members.append(leader)
			used_members[leader.member_name] = true
			leader_deployed_via_vip = true
			print("[遭遇生成] 首领 VIP 通道判定成功，加入 Slot 2: ", leader.member_name)

	# 4. 循环填充 3 个槽位
	var base_slot_rates = [0.35, 0.25, 0.15]
	var increased_reinforcement_chance := 0.15 + 0.50  # 天赋 15% + 圣甲虫 50%
	var dept_member_count = get_division_slot_count(div)

	for slot_idx in range(3):
		if enc_members.size() >= 4:
			break

		# 计算关系链 Proc 修正系数 (只检查候选池与主控成员 A 的关系)
		var max_rel_factor := 1.0
		for mname in members:
			if mname == primary_name or mname in used_members:
				continue
			var already_added := false
			for em in enc_members:
				if em.member_name == mname:
					already_added = true
					break
			if already_added:
				continue

			var m: MemberState = members[mname]
			if not m.is_on_board or m.is_imprisoned:
				continue

			var rel = get_relationship_between(primary_name, mname)
			if rel != null:
				if rel.type == RelationType.RIVALRY:
					max_rel_factor = maxf(max_rel_factor, 3.0)
				elif rel.type == RelationType.TRUST:
					max_rel_factor = maxf(max_rel_factor, 2.0)

		var base_rate = base_slot_rates[slot_idx]
		var final_rate = base_rate * (1.0 + increased_reinforcement_chance) * max_rel_factor

		# 掷骰判定槽位是否激活
		if randf() > final_rate:
			print("[遭遇生成] 增援槽位 ", slot_idx + 1, " 判定失败（概率为 ", final_rate, "），触发 Early Stop 终止后续生成")
			break

		# 动态构建可用候选人池并计算权重
		var candidates = []
		var weights = []
		var total_weight := 0.0

		for mname in members:
			if mname == primary_name or mname in used_members:
				continue
			var already_added := false
			for em in enc_members:
				if em.member_name == mname:
					already_added = true
					break
			if already_added:
				continue

			var m: MemberState = members[mname]
			if not m.is_on_board or m.is_imprisoned:
				continue

			# 开启安全屋的部门成员不支援其他部门遭遇战
			if m.division != Division.NONE and m.division != div and intelligence.get(m.division, 0.0) >= 1.0:
				continue

			# 首领特殊过滤
			if m.is_leader and m.division == div:
				if not leader_eligible:
					continue
				if leader_deployed_via_vip:
					continue

			# 跨部门中立者屏蔽
			var rel = get_relationship_between(primary_name, mname)
			if m.division != Division.NONE and m.division != div and rel == null:
				continue

			# 游民满员阻断
			if m.division == Division.NONE and dept_member_count >= MAX_MEMBERS_PER_DIVISION and rel == null:
				continue

			# 计算权重数值
			var weight := 0.0
			if rel != null:
				# VIP 关系户：宿敌与信任权重完全一致（30票）
				weight = 30.0
				if m.is_leader and m.division == div:
					# 首领 + 关系 + 天赋相伴几率倍增 100% = 60票
					weight = 60.0
			else:
				if m.division == div:
					if m.is_leader:
						# 首领 + 无关系 + 天赋相伴几率倍增 100% = 12票
						weight = 12.0
					else:
						# 同僚 + 无关系 = 4票
						weight = 4.0
				elif m.division == Division.NONE:
					# 自由人 + 无关系 = 1票
					weight = 1.0

			if weight > 0.0:
				candidates.append(m)
				weights.append(weight)
				total_weight += weight

		# 候选池为空判定
		if candidates.is_empty():
			print("[遭遇生成] 增援槽位 ", slot_idx + 1, " 构建候选池为空，触发 Early Stop")
			break

		# 轮盘抽样
		var r = randf() * total_weight
		var current_sum := 0.0
		var selected_idx := -1
		for idx in range(candidates.size()):
			current_sum += weights[idx]
			if r <= current_sum:
				selected_idx = idx
				break

		if selected_idx != -1:
			var selected = candidates[selected_idx]
			enc_members.append(selected)
			used_members[selected.member_name] = true
			print("[遭遇生成] 增援槽位 ", slot_idx + 1, " 抽中: ", selected.member_name, " (权重=", weights[selected_idx], ")")

	return {
		"division": div,
		"members": enc_members,
		"processed": [],
	}

func _validate_encounter(enc: Dictionary) -> void:
	if enc.is_empty() or not enc.has("members"):
		return

	# 1) 首先过滤掉已入狱、不在盘面上或其所属部门安全屋已就绪的成员（但是允许本部门在押的下属保留，因为随后会被释放）
	var alive_members: Array = []
	for m in enc.members:
		var allow_imprisoned = (int(m.division) == int(enc.division) and not m.is_leader)
		var is_locked = (m.division != Division.NONE and m.division != int(enc.division) and intelligence.get(m.division, 0.0) >= 1.0)
		if (not m.is_imprisoned or allow_imprisoned) and m.is_on_board and not is_locked:
			alive_members.append(m)

	if alive_members.is_empty():
		enc.members = []
		return

	# 2) 寻找符合本次遭遇战部门（enc.division）的有效主干部下（锚点成员）
	var primary_member: MemberState = null
	var remaining_candidates: Array = []
	for m in alive_members:
		if int(m.division) == int(enc.division) and primary_member == null:
			primary_member = m
		else:
			remaining_candidates.append(m)

	# 3) 如果没有找到任何属于该部门的存活成员来担当主干，则本场遭遇战直接跳过
	if primary_member == null:
		print("[遭遇成员验证] 遭遇战部门 ", DIVISION_NAMES.get(int(enc.division), ""), " 没有可担当主干的存活下属，本场遭遇战跳过")
		enc.members = []
		return

	var valid_members: Array = [primary_member]
	var primary_name: String = primary_member.member_name

	# 4) 对其余增援候选人进行关系与部门校验
	for m in remaining_candidates:
		if int(m.division) == int(enc.division):
			# 同部门部下作为增援
			valid_members.append(m)
		elif m.division == Division.NONE:
			# 自由人增援不需要关系链限制（他们是为了加入部门而乱入的）
			valid_members.append(m)
		else:
			# 跨部门增援必须与新的主干成员有信任/宿敌关系
			var has_rel = get_relationship_between(primary_name, m.member_name) != null
			if has_rel:
				valid_members.append(m)
			else:
				print("[遭遇成员验证] 过滤成员 ", m.member_name, " (跨部门 ", DIVISION_NAMES.get(m.division, ""), " 且与主干成员 ", primary_name, " 无关系)")

	enc.members = valid_members

func _check_and_release_imprisoned_subordinates_for_encounter(enc: Dictionary) -> void:
	if enc.is_empty() or not enc.has("members"):
		return
	
	# 只释放真正参与本场遭遇战（且目前处于在押状态）的成员
	for m in enc.get("members", []):
		if m.is_imprisoned:
			print("[提前释放] 开启遭遇战，参与遭遇的在押成员 ", m.member_name, " 提前被释放（延迟结算降星）！")
			_release_imprisoned_member(m, false) # 延迟扣星
			m.has_pending_prison_penalty = true

func _reveal_encounter_members(enc: Dictionary):
	for m in enc.get("members", []):
		reveal_member(m.member_name)

func _log_encounter_start(enc: Dictionary):
	## 统一的遭遇开始日志辅助函数
	var div_name: String = DIVISION_NAMES.get(enc.get("division", Division.NONE), "未知")
	var member_descs: Array = []
	var enc_member_names: Array[String] = []
	for m in enc.get("members", []):
		var div_str: String = DIVISION_NAMES.get(m.division, "自由") if m.division != Division.NONE else "自由"
		var role_str := "首领" if m.is_leader else "部下"
		member_descs.append(m.member_name + "(" + str(m.rank) + "星/" + div_str + "/" + role_str + ")")
		enc_member_names.append(m.member_name)
	
	print("\n==================================================")
	print("[遭遇开始] ", div_name, "遭遇战 | 成员: ", ", ".join(member_descs))

	# 打印在押人员
	var imprisoned_names: Array = []
	for mname in members:
		var m = members[mname]
		if m.is_imprisoned:
			var div_str: String = DIVISION_NAMES.get(m.division, "自由") if m.division != Division.NONE else "自由"
			imprisoned_names.append(mname + "(" + str(m.rank) + "星/" + div_str + ", 剩" + str(m.prison_turns_left) + "回合)")
	if not imprisoned_names.is_empty():
		print("  ├─ [在押人员] ", ", ".join(imprisoned_names))
	else:
		print("  ├─ [在押人员] 无")

	# 打印本场遭遇战成员之间的关系链
	var rel_descs: Array = []
	for i in range(enc_member_names.size()):
		for j in range(i + 1, enc_member_names.size()):
			var rel = get_relationship_between(enc_member_names[i], enc_member_names[j])
			if rel:
				var type_str = "信任(绿线)" if rel.type == RelationType.TRUST else "敌对(红线)"
				rel_descs.append(enc_member_names[i] + " ↔ " + enc_member_names[j] + " (" + type_str + ")")
	if not rel_descs.is_empty():
		print("  └─ [成员关系] ", ", ".join(rel_descs))
	else:
		print("  └─ [成员关系] 均无关系")
	print("==================================================")

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

	current_encounter = {}
	while not encounter_queue.is_empty():
		var enc = encounter_queue.pop_front()
		_check_and_release_imprisoned_subordinates_for_encounter(enc)
		_validate_encounter(enc)
		if not enc.get("members", []).is_empty():
			current_encounter = enc
			break
			
	if current_encounter.is_empty():
		# 队列里所有遭遇战均被跳过
		board_changed.emit()
		encounter_queue_advanced.emit(encounter_queue.size())
		save_game_to_disk()
		return {}
	
	_process_prison_intel()
	ActionLogic.refresh_action_caches(self) # 每次新遭遇开启时刷新随机缓存
	_reveal_encounter_members(current_encounter)

	# ===== 日志：遭遇开始 =====
	_log_encounter_start(current_encounter)

	encounter_started.emit(current_encounter)
	board_changed.emit()
	encounter_queue_advanced.emit(encounter_queue.size())
	save_game_to_disk()
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

	# 延迟状态结算：如果被处理的成员拥有提前保释的延迟惩罚，在此刻安全落袋结算
	var m_after: MemberState = members.get(member_name)
	if m_after and m_after.is_on_board and m_after.has_pending_prison_penalty:
		m_after.has_pending_prison_penalty = false
		if m_after.rank > 1:
			m_after.rank -= 1
			var post_div = DIVISION_NAMES.get(m_after.division, "自由人")
			result.effects.append(m_after.member_name + " 因提前保释执行延迟降星惩罚（降至 " + str(m_after.rank) + " 星，归属：" + post_div + "）")
		else:
			result.effects.append(m_after.member_name + " 因提前保释执行延迟降星，但由于星级已是最低1星，本次不降星")

	current_encounter.get("processed", []).append(member_name)
	ActionLogic.refresh_action_caches(self)

	# ===== 日志：动作执行摘要 =====
	var aname := ActionLogic.get_action_name(self, action)
	print("[玩家决策] 处理成员: ", member_name, " | 选择操作: ", aname)
	for eff in result.get("effects", []):
		print("  ├─ [效果] ", eff)
	# 打印执行后成员关键状态
	if m_after:
		var div_str: String = DIVISION_NAMES.get(m_after.division, "自由人")
		var role_str := "首领" if m_after.is_leader else "部下"
		print("  └─ [状态更新] rank=", m_after.rank,
			" | div=", div_str, " | role=", role_str,
			" | imprisoned=", m_after.is_imprisoned)

	action_executed.emit(result)
	board_changed.emit()
	_check_encounter_end()
	save_game_to_disk()

func release_all_current_encounter():
	if current_encounter.is_empty():
		return
	save_state()
	var remaining: Array = _get_remaining_encounter_members()
	for m in remaining:
		var result: Dictionary = ActionLogic.execute_action(self, m.member_name, ActionType.RELEASE)
		current_encounter.get("processed", []).append(m.member_name)
		action_executed.emit(result)
	ActionLogic.refresh_action_caches(self)
	board_changed.emit()
	_check_encounter_end()
	save_game_to_disk()

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

func _promote_new_leader(div: int) -> String:
	# 优先从部门活跃下属中按等级最高提拔
	var candidates: Array = get_division_members(div)
	var valid: Array = []
	for c in candidates:
		if not c.is_leader and not c.is_imprisoned:
			valid.append(c)

	if not valid.is_empty():
		var max_rank = -1
		for c in valid:
			if c.rank > max_rank:
				max_rank = c.rank
		var best_candidates = []
		for c in valid:
			if c.rank == max_rank:
				best_candidates.append(c)
		var promoted_sub = best_candidates[randi() % best_candidates.size()]
		promoted_sub.is_leader = true
		return promoted_sub.member_name + " 被提拔为 " + DIVISION_NAMES.get(div, "") + " 新首领"

	# 部门内无下属时，优先随机招募自由人充当首领
	var free_members: Array = get_unassigned_members()
	var free_valid: Array = []
	for c in free_members:
		if not c.is_imprisoned:
			free_valid.append(c)
	if not free_valid.is_empty():
		var promoted_free = free_valid[randi() % free_valid.size()]
		promoted_free.is_leader = true
		promoted_free.division = div
		promoted_free.rank = maxi(1, promoted_free.rank)
		return promoted_free.member_name + " 从自由人中被提拔为 " + DIVISION_NAMES.get(div, "") + " 新首领"

	# 无自由人可用时，从其他部门随机调任1人担任首领，星级重置为1
	var transfer_pool: Array = []
	var transfer_leader_pool: Array = []
	for mname in members:
		var candidate = members[mname]
		if not candidate.is_on_board or candidate.is_imprisoned:
			continue
		if candidate.division == Division.NONE or candidate.division == div:
			continue
		if candidate.is_leader:
			transfer_leader_pool.append(candidate)
		else:
			transfer_pool.append(candidate)

	var promoted = null
	var promoted_from_div: int = Division.NONE
	var promoted_was_leader := false
	if not transfer_pool.is_empty():
		promoted = transfer_pool[randi() % transfer_pool.size()]
	elif not transfer_leader_pool.is_empty():
		promoted = transfer_leader_pool[randi() % transfer_leader_pool.size()]
		promoted_was_leader = true

	if promoted:
		promoted_from_div = promoted.division
		promoted.division = div
		promoted.is_leader = true
		promoted.rank = 1
		var msg = promoted.member_name + " 从 " + DIVISION_NAMES.get(promoted_from_div, "") + " 调任为 " + DIVISION_NAMES.get(div, "") + " 新首领（原部门星级作废，重置为1星）"
		if promoted_was_leader:
			# 递归提拔原部门的新首领
			var sub_msg = _promote_new_leader(promoted_from_div)
			if sub_msg != "":
				msg += " | " + sub_msg
		return msg
	else:
		return DIVISION_NAMES.get(div, "") + " 暂无可提拔人员，首领空缺"

func raid_safehouse(div: int):
	if not can_raid_safehouse(div):
		return
	save_state()
	
	# 首领变为自由人
	var leader = get_division_leader(div)
	if leader:
		leader.is_leader = false
		leader.division = Division.NONE
		# 首领变为没有星级（0星）的自由人
		leader.rank = 0
		print("[DEBUG 安全屋] 原首领变为0星自由人: ", leader.member_name)

	# 新首领晋升（非在押成员优先，包含自由人/调任逻辑）
	var promo_msg = _promote_new_leader(div)
	if promo_msg != "":
		print("[DEBUG 安全屋] ", promo_msg)

	# 重置该部门情报值，并清除衰减计时
	intelligence[div] = 0.0
	safehouse_100_turns.erase(div)
	intelligence_changed.emit(div, 0.0)
	
	board_changed.emit()
	save_game_to_disk()

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
	state.safehouse_100_turns = safehouse_100_turns.duplicate()
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

	var bp: Array[String] = []
	bp.append_array(bench_pool)
	state.bench_pool = bp
	
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
	safehouse_100_turns.clear()
	if state.has("safehouse_100_turns"):
		safehouse_100_turns = state.safehouse_100_turns.duplicate()
	turn_count = state.turn_count
	current_encounter = state.current_encounter
	
	encounter_queue.clear()
	encounter_queue.append_array(state.encounter_queue)
	
	prison_queue.clear()
	prison_queue.append_array(state.prison_queue)

	bench_pool.clear()
	if state.has("bench_pool"):
		bench_pool.append_array(state.bench_pool)
	
	for div in ALL_DIVISIONS:
		intelligence_changed.emit(div, intelligence.get(div, 0.0))
	state_restored.emit()
	board_changed.emit()
	if not current_encounter.is_empty():
		encounter_started.emit(current_encounter)
	else:
		encounter_ended.emit()
	encounter_queue_advanced.emit(encounter_queue.size())
	save_game_to_disk()

# ===== 工具函数 =====
func get_action_name(action: int) -> String:
	return ActionLogic.get_action_name(self, action)

func get_action_description(action: int) -> String:
	return ActionLogic.get_action_description(self, action)

func initialize_sandbox_mode(active_names: Array[String]):
	is_sandbox_mode = true
	safehouse_100_turns.clear()
	
	# 清理并根据选择设置14人上场，其余3人下场
	bench_pool.clear()
	for mname in members:
		var m = members[mname]
		if mname in active_names:
			m.is_on_board = false # 初始状态设为未摆放，从而在步骤2开始时背景无卡，玩家再行摆放
			m.is_revealed = true
			m.division = Division.NONE
			m.is_leader = false
			m.rank = 1  # 默认在沙盒模式初始放上去的卡给1星（自由人给0星在放上去的时候会自动重置，没关系）
			m.is_imprisoned = false
			m.equipment_count = 0
			m.cached_betray_effect = -1
			m.cached_bargain_effect = -1
			m.cached_bargain_target = ""
		else:
			m.is_on_board = false
			m.is_revealed = false
			m.division = Division.NONE
			m.is_leader = false
			m.rank = 0
			m.is_imprisoned = false
			m.equipment_count = 0
			m.cached_betray_effect = -1
			m.cached_bargain_effect = -1
			m.cached_bargain_target = ""
			bench_pool.append(mname)
	
	relationships.clear()
	intelligence.clear()
	for div in ALL_DIVISIONS:
		intelligence[div] = 0.0
		intelligence_changed.emit(div, 0.0)
	
	turn_count = 0
	current_encounter.clear()
	encounter_queue.clear()
	prison_queue.clear()
	history_stack.clear()
	
	board_changed.emit()

# ===== 磁盘持久化自动存取档系统 =====
const SAVE_FILE_PATH = "user://game_save.json"

func save_game_to_disk():
	var save_data = {}
	save_data["is_sandbox_mode"] = is_sandbox_mode
	save_data["bench_pool"] = bench_pool
	save_data["turn_count"] = turn_count
	
	save_data["intelligence"] = {}
	for k in intelligence:
		save_data["intelligence"][str(k)] = intelligence[k]
		
	save_data["safehouse_100_turns"] = {}
	for k in safehouse_100_turns:
		save_data["safehouse_100_turns"][str(k)] = safehouse_100_turns[k]
		
	save_data["members"] = {}
	for k in members:
		save_data["members"][k] = members[k].to_dict()
		
	var rels = []
	for rel in relationships:
		rels.append(rel.to_dict())
	save_data["relationships"] = rels
	
	# 当前遭遇
	var ce = current_encounter.duplicate()
	if ce.has("members"):
		var ce_m = []
		for m in ce["members"]:
			ce_m.append(m.member_name)
		ce["members"] = ce_m
	if ce.has("processed"):
		ce["processed"] = ce["processed"].duplicate()
	save_data["current_encounter"] = ce
	
	# 遭遇队列
	var eq = []
	for enc in encounter_queue:
		var c_enc = enc.duplicate()
		if enc.has("members"):
			var eq_m = []
			for m in enc["members"]:
				eq_m.append(m.member_name)
			c_enc["members"] = eq_m
		if enc.has("processed"):
			c_enc["processed"] = enc["processed"].duplicate()
		eq.append(c_enc)
	save_data["encounter_queue"] = eq
	
	# 监狱队列
	save_data["prison_queue"] = prison_queue
	
	# 保存至本地磁盘
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		print("【自动存档】游戏进度已成功保存到磁盘：" + SAVE_FILE_PATH)

func load_game_from_disk() -> bool:
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		return false
		
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if not file:
		return false
		
	var text = file.get_as_text()
	var json = JSON.new()
	if json.parse(text) != OK:
		return false
		
	var data = json.data
	if not data is Dictionary:
		return false
		
	is_sandbox_mode = bool(data.get("is_sandbox_mode", false))
	turn_count = int(data.get("turn_count", 0))
	
	# bench_pool
	bench_pool.clear()
	for mname in data.get("bench_pool", []):
		bench_pool.append(str(mname))
		
	# intelligence
	intelligence.clear()
	var intel_data = data.get("intelligence", {})
	for k in intel_data:
		intelligence[int(k)] = float(intel_data[k])
		
	# safehouse_100_turns
	safehouse_100_turns.clear()
	var s100 = data.get("safehouse_100_turns", {})
	for k in s100:
		safehouse_100_turns[int(k)] = int(s100[k])
		
	# members - 原地更新数据，不破坏引用
	var members_data = data.get("members", {})
	for k in members_data:
		if members.has(k):
			members[k].update_from_dict(members_data[k])
		else:
			# 以防万一如果有新卡，创建并装入
			members[k] = MemberState.from_dict(members_data[k])
		
	# relationships
	relationships.clear()
	for rel_d in data.get("relationships", []):
		relationships.append(RelationshipEntry.from_dict(rel_d))
		
	# current_encounter
	var ce = data.get("current_encounter", {})
	if not ce.is_empty():
		if ce.has("division"):
			ce["division"] = int(ce["division"])
		var ce_m = []
		for mname in ce.get("members", []):
			if members.has(mname):
				ce_m.append(members[mname])
		ce["members"] = ce_m
		if ce.has("processed"):
			ce["processed"] = ce["processed"].duplicate()
	current_encounter = ce
	
	# encounter_queue
	encounter_queue.clear()
	for enc in data.get("encounter_queue", []):
		var c_enc = enc.duplicate()
		if c_enc.has("division"):
			c_enc["division"] = int(c_enc["division"])
		var eq_m = []
		for mname in enc.get("members", []):
			if members.has(mname):
				eq_m.append(members[mname])
		c_enc["members"] = eq_m
		if enc.has("processed"):
			c_enc["processed"] = c_enc["processed"].duplicate()
		encounter_queue.append(c_enc)
	
	# prison_queue
	var pq_data = data.get("prison_queue", [])
	prison_queue.clear()
	for mname in pq_data:
		prison_queue.append(str(mname))
		
	# 清空并初始化历史撤销记录
	history_stack.clear()
	
	board_changed.emit()
	print("【自动读档】已从磁盘恢复游戏进度：" + SAVE_FILE_PATH)
	return true

func delete_save_file():
	if FileAccess.file_exists(SAVE_FILE_PATH):
		DirAccess.remove_absolute(SAVE_FILE_PATH)
		print("【自动存档】存档文件已删除。")
