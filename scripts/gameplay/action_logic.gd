class_name ActionLogic
extends RefCounted

## 按钮规则与按钮文案中心：
## - 可用按钮判定
## - 按钮执行逻辑
## - 按钮名称 / 说明
## - 覆盖层黑色方框描述文字

static func get_available_actions(gm, member) -> Array:
	if member == null:
		return []

	var remaining: Array = gm._get_remaining_encounter_members()
	var remaining_count: int = remaining.size()
	var actions: Array = []

	# 审讯：默认可用（已在押不可选）
	if not member.is_imprisoned:
		actions.append(gm.ActionType.INTERROGATE)

	if remaining_count >= 3:
		actions.append(gm.ActionType.EXECUTE)
	elif remaining_count == 2:
		var other = _get_other_remaining_member(gm, member)
		if other != null:
			var has_trust = false
			var has_rivalry = false
			var rel = gm.get_relationship_between(member.member_name, other.member_name)
			if rel:
				if rel.type == gm.RelationType.TRUST: has_trust = true
				if rel.type == gm.RelationType.RIVALRY: has_rivalry = true
			
			var is_sup_sub = _is_hierarchy_pair(member, other, gm.Division.NONE)
			var is_leader = member.is_leader
			
			if has_trust:
				actions.append(gm.ActionType.BETRAY)
			elif is_sup_sub:
				if is_leader:
					actions.append(gm.ActionType.EXECUTE)
				else:
					actions.append(gm.ActionType.BETRAY)
			else:
				actions.append(gm.ActionType.EXECUTE)

	elif remaining_count == 1:
		actions.append(gm.ActionType.BARGAIN)

	# 释放始终可用（中间按钮）
	actions.append(gm.ActionType.RELEASE)
	return actions

static func execute_action(gm, member_name: String, action: int) -> Dictionary:
	var member = gm.members.get(member_name)
	if member == null:
		return {}

	var result = {"action": action, "member": member_name, "effects": []}
	match action:
		gm.ActionType.INTERROGATE: _do_interrogate(gm, member, result)
		gm.ActionType.EXECUTE: _do_execute(gm, member, result)
		gm.ActionType.BARGAIN: _do_bargain(gm, member, result)
		gm.ActionType.BETRAY: _do_betray(gm, member, result)
		gm.ActionType.RELEASE: result.effects.append("释放了 " + member.member_name + "（棋盘不变）")
	return result


# === Pre-roll Logic ===

static func refresh_action_caches(gm):
	var remaining = gm._get_remaining_encounter_members()
	var remaining_count = remaining.size()
	
	for mname in gm.members:
		gm.members[mname].cached_betray_effect = -1
		gm.members[mname].cached_bargain_effect = -1
		gm.members[mname].cached_bargain_target = ""
		
	if remaining_count == 2:
		var m1 = gm.members.get(remaining[0].member_name)
		var m2 = gm.members.get(remaining[1].member_name)
		if m1 and m2:
			m1.cached_betray_effect = _roll_betray_effect(gm, m1, m2)
			m2.cached_betray_effect = _roll_betray_effect(gm, m2, m1)
	elif remaining_count == 1:
		var m1 = gm.members.get(remaining[0].member_name)
		if m1:
			m1.cached_bargain_effect = _roll_bargain_effect(gm, m1)

enum BetrayEffect {
	INCREASE_INTEL_MAKE_RIVALRY,
	STEAL_RANK,
	REMOVE_FROM_SYNDICATE,
	RAISE_OWN_DIV_LOWER_OTHER_DIV,
	DESTROY_OTHER_DIV_EQUIP,
	GAIN_OTHER_DIV_INTEL
}

static func _roll_betray_effect(gm, member, other) -> int:
	var pool: Array[int] = []
	var is_sup_sub = _is_hierarchy_pair(member, other, gm.Division.NONE)
	var diff_div = (member.division != other.division) and (member.division != gm.Division.NONE) and (other.division != gm.Division.NONE)
	
	pool.append(BetrayEffect.INCREASE_INTEL_MAKE_RIVALRY)
	pool.append(BetrayEffect.REMOVE_FROM_SYNDICATE)
	
	if is_sup_sub:
		pool.append(BetrayEffect.STEAL_RANK)
	
	if diff_div:
		pool.append(BetrayEffect.RAISE_OWN_DIV_LOWER_OTHER_DIV)
		pool.append(BetrayEffect.DESTROY_OTHER_DIV_EQUIP)
		pool.append(BetrayEffect.GAIN_OTHER_DIV_INTEL)
		
	if pool.is_empty(): return -1
	return pool[randi() % pool.size()]

enum BargainEffect {
	GAIN_OWN_DIV_INTEL,
	GAIN_RIVAL_DIV_INTEL,
	FORM_TRUST_ANY_GAIN_INTEL,
	DROP_RANDOM_ITEM,
	REMOVE_FROM_SYNDICATE,
	RECRUIT_FREE_AGENT,
	REMOVE_ALL_RIVALRIES_IN_DIV,
	DESTROY_OWN_DIV_EQUIP,
	SWAP_DIVISION,
	COMPLETE_INTERROGATIONS
}

static func _roll_bargain_effect(gm, member) -> int:
	var pool: Array[int] = []
	pool.append(BargainEffect.GAIN_OWN_DIV_INTEL)
	pool.append(BargainEffect.DROP_RANDOM_ITEM)
	pool.append(BargainEffect.REMOVE_FROM_SYNDICATE)
	pool.append(BargainEffect.DESTROY_OWN_DIV_EQUIP)
	
	var processed = gm.current_encounter.get("processed", [])
	if processed.size() > 0:
		var last_name = processed[-1]
		var rel = gm.get_relationship_between(member.member_name, last_name)
		if rel and rel.type == gm.RelationType.RIVALRY:
			pool.append(BargainEffect.GAIN_RIVAL_DIV_INTEL)
			
	var board_count = 0
	var free_agents = false
	var same_rank_diff_div = false
	var has_any_rivalry_in_div = false
	
	var effective_div = member.division
	if effective_div == gm.Division.NONE:
		effective_div = gm.current_encounter.get("division", gm.Division.NONE)
	
	for mname in gm.members:
		var m = gm.members[mname]
		if not m.is_on_board or m.member_name == member.member_name: continue
		if m.is_revealed: board_count += 1
		if m.rank == 0 and m.is_revealed: free_agents = true
		if m.rank == member.rank and member.rank > 0 and m.division != member.division and m.division != gm.Division.NONE and m.is_revealed and not m.is_imprisoned:
			same_rank_diff_div = true
			
	if board_count > 0: pool.append(BargainEffect.FORM_TRUST_ANY_GAIN_INTEL)
	if free_agents and effective_div != gm.Division.NONE and gm.get_division_slot_count(effective_div) < gm.MAX_MEMBERS_PER_DIVISION: pool.append(BargainEffect.RECRUIT_FREE_AGENT)
	if same_rank_diff_div and not member.is_leader: pool.append(BargainEffect.SWAP_DIVISION)
	if gm.prison_queue.size() > 0: pool.append(BargainEffect.COMPLETE_INTERROGATIONS)
	
	if effective_div != gm.Division.NONE:
		var div_members = gm.get_division_members(effective_div)
		for dm in div_members:
			var rels = gm.get_relationships_for(dm.member_name)
			for r in rels:
				if r.type == gm.RelationType.RIVALRY:
					has_any_rivalry_in_div = true
					break
			if has_any_rivalry_in_div: break
		if has_any_rivalry_in_div:
			pool.append(BargainEffect.REMOVE_ALL_RIVALRIES_IN_DIV)
			
	if pool.is_empty(): return -1
	var chosen = pool[randi() % pool.size()]
	
	member.cached_bargain_target = ""
	if chosen == BargainEffect.SWAP_DIVISION:
		var valid_targets = []
		for k in gm.members:
			var cm = gm.members[k]
			if cm.is_on_board and not cm.is_imprisoned and not cm.is_leader and cm.rank == member.rank and cm.division != member.division and cm.division != gm.Division.NONE and cm.is_revealed:
				valid_targets.append(cm)
		if valid_targets.size() > 0:
			member.cached_bargain_target = valid_targets[randi() % valid_targets.size()].member_name
	elif chosen == BargainEffect.RECRUIT_FREE_AGENT:
		var free_agent_list = []
		for k in gm.members:
			var cm = gm.members[k]
			if cm.is_on_board and cm.rank == 0 and cm.is_revealed: free_agent_list.append(cm)
		if free_agent_list.size() > 0:
			member.cached_bargain_target = free_agent_list[randi() % free_agent_list.size()].member_name
	elif chosen == BargainEffect.FORM_TRUST_ANY_GAIN_INTEL:
		var valid_targets = []
		for k in gm.members:
			var cm = gm.members[k]
			if cm.is_on_board and cm.member_name != member.member_name and cm.is_revealed: valid_targets.append(cm)
		if valid_targets.size() > 0:
			member.cached_bargain_target = valid_targets[randi() % valid_targets.size()].member_name
	elif chosen == BargainEffect.DROP_RANDOM_ITEM:
		var loot_table = ["加密物品", "圣甲虫", "通货物品", "传奇物品", "地图"]
		member.cached_bargain_target = loot_table[randi() % loot_table.size()]

	return chosen


# === UI Texts ===

static func get_action_name(gm, action: int) -> String:
	match action:
		gm.ActionType.INTERROGATE: return "审讯"
		gm.ActionType.EXECUTE: return "处决"
		gm.ActionType.BARGAIN: return "商谈"
		gm.ActionType.BETRAY: return "背叛"
		gm.ActionType.RELEASE: return "释放"
	return ""

static func get_action_description(gm, action: int) -> String:
	match action:
		gm.ActionType.INTERROGATE: return "监禁3回合，按入狱军衔每回合产情报，释放时降1星"
		gm.ActionType.EXECUTE: return "星级+1（上限3），自由人可加入当前遭遇部门"
		gm.ActionType.BARGAIN: return "商谈：获得随机奖励或触发机制"
		gm.ActionType.BETRAY: return "背叛目标"
		gm.ActionType.RELEASE: return "释放，不改变棋盘"
	return ""

static func get_action_button_text(gm, member, action: int) -> String:
	return get_action_name(gm, action)

static func get_overlay_description(gm, member, action: int) -> String:
	if member == null: return ""
	var name = member.member_name
	var effective_div = member.division
	if effective_div == gm.Division.NONE:
		effective_div = gm.current_encounter.get("division", gm.Division.NONE)
	var div_name = gm.DIVISION_NAMES.get(effective_div, "无") if effective_div != gm.Division.NONE else "无"

	match action:
		gm.ActionType.INTERROGATE:
			var intel_points = gm.PRISON_INTEL_PER_TURN_BY_RANK.get(clampi(member.rank, 0, 3), 1)
			return name + " 被囚禁 " + str(gm.PRISON_DURATION) + " 回合。\n" + div_name + " 情报每回合 +" + str(intel_points) + " 点。\n释放后等级 -1"
		gm.ActionType.EXECUTE:
			if member.rank >= 3:
				return "【已达最大等级。无效果】"
			return name + " 等级 +1"
		gm.ActionType.RELEASE:
			return "释放 " + name + "\n不改变棋盘"
		gm.ActionType.BETRAY:
			var effect = member.cached_betray_effect
			var target = _get_other_remaining_member(gm, member)
			var target_name = target.member_name if target else "未知目标"
			var target_div_name = gm.DIVISION_NAMES.get(target.division, "无") if target and target.division != gm.Division.NONE else "无"
			
			match effect:
				BetrayEffect.INCREASE_INTEL_MAKE_RIVALRY: return "增加 " + div_name + " 情报，\n同时与 " + target_name + " 的关系变为敌对"
				BetrayEffect.STEAL_RANK: return "窃取 " + target_name + " 的等级加至自身（最高3星）并增加 " + div_name + " 情报，\n" + target_name + " 降为0星自由人并失去职务，且双方变为敌对"
				BetrayEffect.REMOVE_FROM_SYNDICATE: return "将 " + target_name + " 永远逐出不朽辛迪加\n（由替补补位）"
				BetrayEffect.RAISE_OWN_DIV_LOWER_OTHER_DIV: return "提升 " + div_name + " 全员军衔，\n降低 " + target_div_name + " 全员军衔"
				BetrayEffect.DESTROY_OTHER_DIV_EQUIP: return "摧毁 " + target_div_name + " 成员身上的所有装备"
				BetrayEffect.GAIN_OTHER_DIV_INTEL: return "获取 " + target_div_name + " 的情报"
			return "背叛 " + target_name
		gm.ActionType.BARGAIN:
			var effect = member.cached_bargain_effect
			match effect:
				BargainEffect.GAIN_OWN_DIV_INTEL: return "获取 " + div_name + " 情报"
				BargainEffect.GAIN_RIVAL_DIV_INTEL:
					# 从 processed 列表取上一个被处理成员的部门名
					var processed_list = gm.current_encounter.get("processed", [])
					var rival_div_name := "仇敌部门"
					if processed_list.size() > 0:
						var last_m = gm.members.get(processed_list[-1])
						if last_m and last_m.division != gm.Division.NONE:
							rival_div_name = gm.DIVISION_NAMES.get(last_m.division, "仇敌部门")
					return "获取 " + rival_div_name + " 情报\n并与仇敌关系变为中立"
				BargainEffect.FORM_TRUST_ANY_GAIN_INTEL:
					var t_m = gm.members.get(member.cached_bargain_target)
					var t_div_name := "未知部门"
					if t_m:
						t_div_name = gm.DIVISION_NAMES.get(t_m.division, "自由人") if t_m.division != gm.Division.NONE else "自由人"
					return "与 " + member.cached_bargain_target + " 达成信任 (若有仇敌则冰释前嫌)\n并获取 " + t_div_name + " 情报"
				BargainEffect.DROP_RANDOM_ITEM: return "掉落道具：\n" + member.cached_bargain_target
				BargainEffect.REMOVE_FROM_SYNDICATE: return "将自己永远从不朽辛迪加中除名\n（由替补补位）"
				BargainEffect.RECRUIT_FREE_AGENT: return "招募自由人 " + member.cached_bargain_target + " 加入 " + div_name + "\n并结为信任关系"
				BargainEffect.REMOVE_ALL_RIVALRIES_IN_DIV: return "移除 " + div_name + " 全员的所有仇敌死敌关系"
				BargainEffect.DESTROY_OWN_DIV_EQUIP: return "摧毁 " + div_name + " 所有成员的装备"
				BargainEffect.SWAP_DIVISION: return "与 " + member.cached_bargain_target + " 交换部门及职务"
				BargainEffect.COMPLETE_INTERROGATIONS: return "立即完成所有审讯\n囚犯释放并获得所有剩余情报"
			return "获取 " + div_name + " 情报"
	return ""

# === Helpers ===

static func _is_hierarchy_pair(a, b, none_div: int) -> bool:
	if a == null or b == null: return false
	if a.division == none_div or b.division == none_div: return false
	if a.division != b.division: return false
	return a.is_leader != b.is_leader

static func _get_other_remaining_member(gm, member):
	if member == null: return null
	var remaining: Array = gm._get_remaining_encounter_members()
	for rm in remaining:
		if rm.member_name != member.member_name: return rm
	return null

# === Execution ===

static func _do_interrogate(gm, m, result: Dictionary):
	if gm._get_imprisoned_count() >= gm.MAX_IMPRISONED:
		_force_release_oldest_prisoner(gm, result)

	if m.is_leader: _leader_step_down(gm, m, result)

	m.is_imprisoned = true
	m.prison_turns_left = gm.PRISON_DURATION
	m.prison_rank_snapshot = clampi(m.rank, 0, 3)
	m.prison_intel_per_turn_points = gm._get_prison_intel_points_by_rank(m.prison_rank_snapshot)
	# 审讯时将情报贡献去向部门设定为当前遭遇战所在的部门
	m.prison_intel_division = gm.current_encounter.get("division", gm.Division.NONE)
	gm.prison_queue.append(m.member_name)

	result.effects.append(m.member_name + " 入狱 " + str(gm.PRISON_DURATION) + " 次遭遇")
	var intel_div: int = m.prison_intel_division
	if intel_div != gm.Division.NONE:
		result.effects.append("每回合为 " + gm.DIVISION_NAMES.get(intel_div, "") + " 提供 " + str(m.prison_intel_per_turn_points) + " 点情报")
	gm.member_imprisoned.emit(m.member_name)

static func _leader_step_down(gm, m, result: Dictionary):
	var div: int = m.division
	m.is_leader = false
	result.effects.append(m.member_name + " 从 " + gm.DIVISION_NAMES.get(div, "") + " 首领下台")

	var promo_msg = gm._promote_new_leader(div)
	if promo_msg != "":
		for msg in promo_msg.split(" | "):
			result.effects.append(msg)

static func _force_release_oldest_prisoner(gm, result: Dictionary):
	if gm.prison_queue.is_empty(): return
	var oldest_name: String = gm.prison_queue.pop_front()
	var oldest = gm.members.get(oldest_name)
	if oldest == null: return

	gm._release_imprisoned_member(oldest, true)
	if oldest.rank <= 0:
		result.effects.append(oldest.member_name + " 降为0星，变为自由人")
	else:
		result.effects.append(oldest.member_name + " 被强制释放（降至 " + str(oldest.rank) + " 星）")

static func _do_execute(gm, m, result: Dictionary):
	# 在升星前记录状态，避免 rank 被修改后判断出错
	var was_free_agent: bool = (m.rank == 0 and m.division == gm.Division.NONE)

	if m.rank < 3:
		m.rank += 1
		result.effects.append(m.member_name + " 升至 " + str(m.rank) + " 星")
	else:
		result.effects.append(m.member_name + " 已是最高等级（无升星效果）")

	# 自由人（原 rank=0，division=NONE）加入当前遭遇部门
	if was_free_agent:
		var enc_div: int = gm.current_encounter.get("division", gm.Division.NONE)
		var slot_count: int = gm.get_division_slot_count(enc_div)
		print("[DEBUG 处决] 自由人加入检查: member=", m.member_name,
			" | enc_div=", enc_div,
			" | slot_count=", slot_count, "/", gm.MAX_MEMBERS_PER_DIVISION)
		if enc_div != gm.Division.NONE and slot_count < gm.MAX_MEMBERS_PER_DIVISION:
			m.division = enc_div
			result.effects.append(m.member_name + " 加入 " + gm.DIVISION_NAMES.get(enc_div, ""))
			print("[DEBUG 处决] 成功加入部门 div=", m.division)
		else:
			# 如果部门已满，无法加入，降回0星
			m.rank = 0
			# 去掉之前的升星信息
			if result.effects.size() > 0:
				result.effects.pop_back()
			result.effects.append(m.member_name + " 试图加入，但部门已满（仍为0星自由人）")
			print("[DEBUG 处决] 加入失败！enc_div=", enc_div, " slot=", slot_count, "/", gm.MAX_MEMBERS_PER_DIVISION)


static func _do_betray(gm, m, result: Dictionary):
	var effect = m.cached_betray_effect
	var target = _get_other_remaining_member(gm, m)
	if target == null:
		result.effects.append("背叛失败 — 找不到目标")
		return
		
	var div_name = gm.DIVISION_NAMES.get(m.division, "无")
	var target_div_name = gm.DIVISION_NAMES.get(target.division, "无")
	
	match effect:
		BetrayEffect.INCREASE_INTEL_MAKE_RIVALRY:
			if m.division != gm.Division.NONE:
				gm._add_intel_points_to_division(m.division, 15)
				result.effects.append(div_name + " 情报 +15 点")
			gm._set_relationship_type(m.member_name, target.member_name, gm.RelationType.RIVALRY)
			result.effects.append("与 " + target.member_name + " 结为仇敌")
			
		BetrayEffect.STEAL_RANK:
			if m.division != gm.Division.NONE:
				gm._add_intel_points_to_division(m.division, 15)
				result.effects.append(div_name + " 情报 +15 点")
			var steal_amount = target.rank
			m.rank = mini(3, m.rank + steal_amount)
			target.rank = 0
			if target.is_leader: _leader_step_down(gm, target, result)
			target.division = gm.Division.NONE
			gm._set_relationship_type(m.member_name, target.member_name, gm.RelationType.RIVALRY)
			result.effects.append(m.member_name + " 窃取等级升至 " + str(m.rank) + "星，" + target.member_name + " 降为0星自由人并结仇")
			
		BetrayEffect.REMOVE_FROM_SYNDICATE:
			_kick_member_and_replace(gm, target, result)
			
		BetrayEffect.RAISE_OWN_DIV_LOWER_OTHER_DIV:
			if m.division != gm.Division.NONE:
				var m_divs = gm.get_division_members(m.division)
				for md in m_divs: md.rank = mini(3, md.rank + 1)
				var leader_m = gm.get_division_leader(m.division)
				if leader_m: leader_m.rank = mini(3, leader_m.rank + 1)
				result.effects.append(div_name + " 全员军衔 +1")
			if target.division != gm.Division.NONE:
				var t_divs = gm.get_division_members(target.division)
				var leader_t = gm.get_division_leader(target.division)
				var to_demote = []
				to_demote.append_array(t_divs)
				if leader_t: to_demote.append(leader_t)
				for td in to_demote: 
					td.rank = maxi(0, td.rank - 1)
					if td.rank == 0: 
						if td.is_leader: _leader_step_down(gm, td, result)
						td.division = gm.Division.NONE
				result.effects.append(target_div_name + " 全员军衔 -1 (降至0星者脱离部门)")
			gm._remove_relationship(m.member_name, target.member_name)
				
		BetrayEffect.DESTROY_OTHER_DIV_EQUIP:
			if target.division != gm.Division.NONE:
				var t_divs = gm.get_division_members(target.division)
				var leader_t = gm.get_division_leader(target.division)
				var to_destroy = []
				to_destroy.append_array(t_divs)
				if leader_t: to_destroy.append(leader_t)
				for td in to_destroy: td.equipment_count = 0
				result.effects.append("摧毁了 " + target_div_name + " 全员的装备")
			gm._remove_relationship(m.member_name, target.member_name)
				
		BetrayEffect.GAIN_OTHER_DIV_INTEL:
			if target.division != gm.Division.NONE:
				gm._add_intel_points_to_division(target.division, 20)
				result.effects.append("获取 " + target_div_name + " 情报 +20 点")
			gm._remove_relationship(m.member_name, target.member_name)

static func _do_bargain(gm, m, result: Dictionary):
	var effect = m.cached_bargain_effect
	var effective_div = m.division
	if effective_div == gm.Division.NONE:
		effective_div = gm.current_encounter.get("division", gm.Division.NONE)
	var div_name = gm.DIVISION_NAMES.get(effective_div, "无")
	
	match effect:
		BargainEffect.GAIN_OWN_DIV_INTEL:
			if effective_div != gm.Division.NONE:
				gm._add_intel_points_to_division(effective_div, 20)
				result.effects.append(div_name + " 情报 +20 点")
				
		BargainEffect.GAIN_RIVAL_DIV_INTEL:
			var processed = gm.current_encounter.get("processed", [])
			if processed.size() > 0:
				var last_name = processed[-1]
				var t = gm.members.get(last_name)
				if t and t.division != gm.Division.NONE:
					gm._add_intel_points_to_division(t.division, 25)
					result.effects.append("获取仇敌部门 (" + gm.DIVISION_NAMES.get(t.division, "") + ") 情报 +25 点")
				if t:
					var rel = gm.get_relationship_between(m.member_name, t.member_name)
					if rel and rel.type == gm.RelationType.RIVALRY:
						gm._remove_relationship(m.member_name, t.member_name)
						result.effects.append("与 " + t.member_name + " 的关系变为中立")
					
		BargainEffect.FORM_TRUST_ANY_GAIN_INTEL:
			var t = gm.members.get(m.cached_bargain_target)
			if t:
				var rel = gm.get_relationship_between(m.member_name, t.member_name)
				if rel and rel.type == gm.RelationType.RIVALRY:
					gm._remove_relationship(m.member_name, t.member_name)
					result.effects.append("与 " + t.member_name + " 冰释前嫌 (中立)")
				else:
					gm._set_relationship_type(m.member_name, t.member_name, gm.RelationType.TRUST)
					result.effects.append("与 " + t.member_name + " 达成信任")
				if t.division != gm.Division.NONE:
					gm._add_intel_points_to_division(t.division, 15)
					result.effects.append("获取 " + gm.DIVISION_NAMES.get(t.division, "") + " 情报 +15")
					
		BargainEffect.DROP_RANDOM_ITEM:
			result.effects.append("掉落: " + m.cached_bargain_target)
			
		BargainEffect.REMOVE_FROM_SYNDICATE:
			_kick_member_and_replace(gm, m, result)
			
		BargainEffect.RECRUIT_FREE_AGENT:
			var t = gm.members.get(m.cached_bargain_target)
			if t:
				t.rank = 1
				t.division = effective_div
				var rel = gm.get_relationship_between(m.member_name, t.member_name)
				if rel and rel.type == gm.RelationType.RIVALRY:
					gm._remove_relationship(m.member_name, t.member_name)
					result.effects.append("招募自由人 " + t.member_name + " 加入" + div_name + " (关系变中立)")
				else:
					gm._set_relationship_type(m.member_name, t.member_name, gm.RelationType.TRUST)
					result.effects.append("招募自由人 " + t.member_name + " 加入" + div_name + " (结为信任)")
					
		BargainEffect.REMOVE_ALL_RIVALRIES_IN_DIV:
			if effective_div != gm.Division.NONE:
				var count = 0
				var m_divs = gm.get_division_members(effective_div)
				var leader_m = gm.get_division_leader(effective_div)
				var all_own = []
				all_own.append_array(m_divs)
				if leader_m: all_own.append(leader_m)
				
				for md in all_own:
					for rm in gm.members.values():
						var rel = gm.get_relationship_between(md.member_name, rm.member_name)
						if rel and rel.type == gm.RelationType.RIVALRY:
							gm._remove_relationship(md.member_name, rm.member_name)
							count += 1
				result.effects.append("移除了 " + div_name + " 内的所有仇敌红线 (共 " + str(count) + " 条)")
				
		BargainEffect.DESTROY_OWN_DIV_EQUIP:
			if effective_div != gm.Division.NONE:
				var m_divs = gm.get_division_members(effective_div)
				var leader_m = gm.get_division_leader(effective_div)
				var all_own = []
				all_own.append_array(m_divs)
				if leader_m: all_own.append(leader_m)
				for md in all_own: md.equipment_count = 0
				result.effects.append("作为求饶交换，摧毁了 " + div_name + " 所有成员的装备")
				
		BargainEffect.SWAP_DIVISION:
			var t = gm.members.get(m.cached_bargain_target)
			if t:
				var old_div = m.division
				var old_leader = m.is_leader
				m.division = t.division
				m.is_leader = t.is_leader
				t.division = old_div
				t.is_leader = old_leader
				result.effects.append("与 " + t.member_name + " 互换了部门和职务")
				
		BargainEffect.COMPLETE_INTERROGATIONS:
			var released_any = false
			var total_added = 0
			for qname in gm.prison_queue.duplicate():
				var prisoner = gm.members.get(qname)
				if prisoner == null or not prisoner.is_imprisoned: continue
				var div = gm._resolve_intel_division_for_member(prisoner)
				var turns = maxi(prisoner.prison_turns_left, 0)
				var pt = prisoner.prison_intel_per_turn_points
				if pt <= 0:
					var sr = prisoner.prison_rank_snapshot if prisoner.prison_rank_snapshot >= 0 else prisoner.rank
					pt = gm._get_prison_intel_points_by_rank(sr)
				total_added += gm._add_intel_points_to_division(div, turns * pt)
				gm._release_imprisoned_member(prisoner, true)
				released_any = true
			gm.prison_queue.clear()
			if released_any: result.effects.append("立即释放所有囚犯，获得剩余情报 +" + str(total_added))
			else: result.effects.append("当前无囚犯，无效果")

	# 兼容处理：如果 cached_bargain_effect 为 -1（未预滚，包括自由人商谈等边界情况）
	# 就走「获取当前部门情报」逐内内容
	if effective_div != gm.Division.NONE:
		gm._add_intel_points_to_division(effective_div, gm.BARGAIN_INTEL_GAIN_POINTS)
		result.effects.append("获取 " + div_name + " 情报 +" + str(gm.BARGAIN_INTEL_GAIN_POINTS) + " 点")
	else:
		result.effects.append("无部门可获得情报")

static func _kick_member_and_replace(gm, m, result: Dictionary):
	var kicked_name: String = m.member_name
	
	if m.is_leader: _leader_step_down(gm, m, result)
	
	m.is_on_board = false
	m.division = gm.Division.NONE
	m.is_leader = false
	m.is_imprisoned = false
	m.prison_turns_left = 0
	m.prison_rank_snapshot = -1
	m.prison_intel_per_turn_points = 0
	m.is_revealed = false
	m.rank = 1
	m.equipment_count = 0
	if m.member_name in gm.prison_queue: gm.prison_queue.erase(m.member_name)
	
	# 清除与该成员相关的所有关系链，防止其重置后带入旧关系
	var to_remove: Array = []
	for rel in gm.relationships:
		if rel.member_a == kicked_name or rel.member_b == kicked_name:
			to_remove.append(rel)
	for rel in to_remove:
		gm.relationships.erase(rel)
	
	# === 修复BUG：如果此人原本在当前遭遇战中，但他现在被除名（消失）了，我们需要自动将他标记为“已处理”，否则这局遭遇战会因为等待他的操作而永远卡住 ===
	var enc_members = gm.current_encounter.get("members", [])
	var processed_list = gm.current_encounter.get("processed", [])
	for em in enc_members:
		if em.member_name == kicked_name and not (kicked_name in processed_list):
			processed_list.append(kicked_name)
			break
	
	result.effects.append(kicked_name + " 被永远逐出辛迪加")

	if not (kicked_name in gm.bench_pool):
		gm.bench_pool.append(kicked_name)

	var replacement = null
	if not gm.bench_pool.is_empty():
		var rep_idx := -1
		for i in range(gm.bench_pool.size()):
			if gm.bench_pool[i] != kicked_name:
				rep_idx = i
				break
		if rep_idx == -1:
			rep_idx = 0
		var rep_name = gm.bench_pool[rep_idx]
		gm.bench_pool.remove_at(rep_idx)
		replacement = gm.members.get(rep_name)

	if replacement:
		replacement.is_on_board = true
		replacement.division = gm.Division.NONE
		replacement.is_leader = false
		replacement.rank = 0
		replacement.is_revealed = true # 新加入的成员自动翻开
		replacement.equipment_count = 0
		replacement.is_imprisoned = false
		replacement.prison_turns_left = 0
		replacement.prison_rank_snapshot = -1
		replacement.prison_intel_per_turn_points = 0
		result.effects.append(replacement.member_name + " 作为新人加入辛迪加")
	else:
		result.effects.append("没有替补成员可用")

static func get_betray_effects_status(gm, member) -> Array:
	var target = _get_other_remaining_member(gm, member)
	var is_sup_sub = _is_hierarchy_pair(member, target, gm.Division.NONE) if target else false
	var diff_div = false
	if member and target:
		diff_div = (member.division != target.division) and (member.division != gm.Division.NONE) and (target.division != gm.Division.NONE)
	
	var list := []
	var betray_effects := [
		BetrayEffect.INCREASE_INTEL_MAKE_RIVALRY,
		BetrayEffect.STEAL_RANK,
		BetrayEffect.REMOVE_FROM_SYNDICATE,
		BetrayEffect.RAISE_OWN_DIV_LOWER_OTHER_DIV,
		BetrayEffect.DESTROY_OTHER_DIV_EQUIP,
		BetrayEffect.GAIN_OTHER_DIV_INTEL
	]
	
	var div_name = gm.DIVISION_NAMES.get(member.division, "无")
	var target_name = target.member_name if target else "未知目标"
	var target_div_name = gm.DIVISION_NAMES.get(target.division, "无") if target and target.division != gm.Division.NONE else "无"

	for effect_id in betray_effects:
		var is_valid := false
		if effect_id == BetrayEffect.INCREASE_INTEL_MAKE_RIVALRY or effect_id == BetrayEffect.REMOVE_FROM_SYNDICATE:
			is_valid = (target != null)
		elif effect_id == BetrayEffect.STEAL_RANK:
			is_valid = is_sup_sub
		elif effect_id in [BetrayEffect.RAISE_OWN_DIV_LOWER_OTHER_DIV, BetrayEffect.DESTROY_OTHER_DIV_EQUIP, BetrayEffect.GAIN_OTHER_DIV_INTEL]:
			is_valid = diff_div
			
		var desc := ""
		match effect_id:
			BetrayEffect.INCREASE_INTEL_MAKE_RIVALRY: desc = "增加 " + div_name + " 情报，\n同时与 " + target_name + " 的关系变为敌对"
			BetrayEffect.STEAL_RANK: desc = "窃取 " + target_name + " 的等级加至自身（最高3星）并增加 " + div_name + " 情报，\n" + target_name + " 降为0星自由人并失去职务，且双方变为敌对"
			BetrayEffect.REMOVE_FROM_SYNDICATE: desc = "将 " + target_name + " 永远逐出不朽辛迪加\n（由替补补位）"
			BetrayEffect.RAISE_OWN_DIV_LOWER_OTHER_DIV: desc = "提升 " + div_name + " 全员军衔，\n降低 " + target_div_name + " 全员军衔"
			BetrayEffect.DESTROY_OTHER_DIV_EQUIP: desc = "摧毁 " + target_div_name + " 成员身上的所有装备"
			BetrayEffect.GAIN_OTHER_DIV_INTEL: desc = "获取 " + target_div_name + " 的情报"

		list.append({
			"id": effect_id,
			"name": get_betray_effect_name(effect_id),
			"description": desc,
			"is_valid": is_valid
		})
	return list

static func get_betray_effect_name(effect_id: int) -> String:
	match effect_id:
		BetrayEffect.INCREASE_INTEL_MAKE_RIVALRY: return "增加情报并结仇"
		BetrayEffect.STEAL_RANK: return "窃取等级并结仇"
		BetrayEffect.REMOVE_FROM_SYNDICATE: return "逐出辛迪加"
		BetrayEffect.RAISE_OWN_DIV_LOWER_OTHER_DIV: return "提升己方/降低敌方军衔"
		BetrayEffect.DESTROY_OTHER_DIV_EQUIP: return "摧毁对方部门装备"
		BetrayEffect.GAIN_OTHER_DIV_INTEL: return "获取对方部门情报"
	return "未知"

static func get_bargain_effects_status(gm, member) -> Array:
	var effective_div = member.division
	if effective_div == gm.Division.NONE:
		effective_div = gm.current_encounter.get("division", gm.Division.NONE)
	
	var div_name = gm.DIVISION_NAMES.get(effective_div, "无")
	
	var processed = gm.current_encounter.get("processed", [])
	var has_processed_rival = false
	if processed.size() > 0:
		var last_name = processed[-1]
		var rel = gm.get_relationship_between(member.member_name, last_name)
		if rel and rel.type == gm.RelationType.RIVALRY:
			has_processed_rival = true
			
	var board_count = 0
	var free_agents = false
	var same_rank_diff_div = false
	var has_any_rivalry_in_div = false
	
	for mname in gm.members:
		var m = gm.members[mname]
		if not m.is_on_board or m.member_name == member.member_name: continue
		if m.is_revealed: board_count += 1
		if m.rank == 0 and m.is_revealed: free_agents = true
		if m.rank == member.rank and member.rank > 0 and m.division != member.division and m.division != gm.Division.NONE and m.is_revealed and not m.is_imprisoned:
			same_rank_diff_div = true

	if effective_div != gm.Division.NONE:
		var div_members = gm.get_division_members(effective_div)
		for dm in div_members:
			var rels = gm.get_relationships_for(dm.member_name)
			for r in rels:
				if r.type == gm.RelationType.RIVALRY:
					has_any_rivalry_in_div = true
					break
			if has_any_rivalry_in_div: break

	var list := []
	var bargain_effects := [
		BargainEffect.GAIN_OWN_DIV_INTEL,
		BargainEffect.GAIN_RIVAL_DIV_INTEL,
		BargainEffect.FORM_TRUST_ANY_GAIN_INTEL,
		BargainEffect.DROP_RANDOM_ITEM,
		BargainEffect.REMOVE_FROM_SYNDICATE,
		BargainEffect.RECRUIT_FREE_AGENT,
		BargainEffect.REMOVE_ALL_RIVALRIES_IN_DIV,
		BargainEffect.DESTROY_OWN_DIV_EQUIP,
		BargainEffect.SWAP_DIVISION,
		BargainEffect.COMPLETE_INTERROGATIONS
	]

	for effect_id in bargain_effects:
		var is_valid := false
		var target := ""
		
		match effect_id:
			BargainEffect.GAIN_OWN_DIV_INTEL:
				is_valid = true
			BargainEffect.DROP_RANDOM_ITEM:
				is_valid = true
				target = ["加密物品", "圣甲虫", "通货物品", "传奇物品", "一张地图"].pick_random()
			BargainEffect.REMOVE_FROM_SYNDICATE:
				is_valid = true
			BargainEffect.DESTROY_OWN_DIV_EQUIP:
				is_valid = true
			BargainEffect.GAIN_RIVAL_DIV_INTEL:
				is_valid = has_processed_rival
			BargainEffect.FORM_TRUST_ANY_GAIN_INTEL:
				is_valid = board_count > 0
				if is_valid:
					var valid_targets = []
					for k in gm.members:
						var cm = gm.members[k]
						if cm.is_on_board and cm.member_name != member.member_name and cm.is_revealed:
							valid_targets.append(cm)
					if valid_targets.size() > 0:
						target = valid_targets.pick_random().member_name
			BargainEffect.RECRUIT_FREE_AGENT:
				is_valid = free_agents and effective_div != gm.Division.NONE and gm.get_division_slot_count(effective_div) < gm.MAX_MEMBERS_PER_DIVISION
				if is_valid:
					var free_agent_list = []
					for k in gm.members:
						var cm = gm.members[k]
						if cm.is_on_board and cm.rank == 0 and cm.is_revealed:
							free_agent_list.append(cm)
					if free_agent_list.size() > 0:
						target = free_agent_list.pick_random().member_name
			BargainEffect.SWAP_DIVISION:
				is_valid = same_rank_diff_div and not member.is_leader
				if is_valid:
					var valid_targets = []
					for k in gm.members:
						var cm = gm.members[k]
						if cm.is_on_board and not cm.is_imprisoned and not cm.is_leader and cm.rank == member.rank and cm.division != member.division and cm.division != gm.Division.NONE and cm.is_revealed:
							valid_targets.append(cm)
					if valid_targets.size() > 0:
						target = valid_targets.pick_random().member_name
			BargainEffect.COMPLETE_INTERROGATIONS:
				is_valid = gm.prison_queue.size() > 0
			BargainEffect.REMOVE_ALL_RIVALRIES_IN_DIV:
				is_valid = has_any_rivalry_in_div
				
		var desc := ""
		match effect_id:
			BargainEffect.GAIN_OWN_DIV_INTEL: desc = "获取 " + div_name + " 情报"
			BargainEffect.GAIN_RIVAL_DIV_INTEL:
				var processed_list = gm.current_encounter.get("processed", [])
				var rival_div_name := "仇敌部门"
				if processed_list.size() > 0:
					var last_m = gm.members.get(processed_list[-1])
					if last_m and last_m.division != gm.Division.NONE:
						rival_div_name = gm.DIVISION_NAMES.get(last_m.division, "仇敌部门")
				desc = "获取 " + rival_div_name + " 情报\n并与仇敌关系变为中立"
			BargainEffect.FORM_TRUST_ANY_GAIN_INTEL:
				var t_name = target if target != "" else "随机成员"
				var t_m = gm.members.get(t_name)
				var t_div_name := "未知部门"
				if t_m:
					t_div_name = gm.DIVISION_NAMES.get(t_m.division, "自由人") if t_m.division != gm.Division.NONE else "自由人"
				desc = "与 " + t_name + " 达成信任 (若有仇敌则冰释前嫌)\n并获取 " + t_div_name + " 情报"
			BargainEffect.DROP_RANDOM_ITEM: desc = "掉落道具：\n" + (target if target != "" else "随机物品")
			BargainEffect.REMOVE_FROM_SYNDICATE: desc = "将自己永远从不朽辛迪加中除名\n（由替补补位）"
			BargainEffect.RECRUIT_FREE_AGENT: desc = "招募自由人 " + (target if target != "" else "随机") + " 加入 " + div_name + "\n并结为信任关系"
			BargainEffect.REMOVE_ALL_RIVALRIES_IN_DIV: desc = "移除 " + div_name + " 全员的所有仇敌死敌关系"
			BargainEffect.DESTROY_OWN_DIV_EQUIP: desc = "摧毁 " + div_name + " 所有成员的装备"
			BargainEffect.SWAP_DIVISION: desc = "与 " + (target if target != "" else "同星成员") + " 交换部门及职务"
			BargainEffect.COMPLETE_INTERROGATIONS: desc = "立即完成所有审讯\n囚犯释放并获得所有剩余情报"

		list.append({
			"id": effect_id,
			"name": get_bargain_effect_name(effect_id),
			"description": desc,
			"is_valid": is_valid,
			"target": target
		})
	return list

static func get_bargain_effect_name(effect_id: int) -> String:
	match effect_id:
		BargainEffect.GAIN_OWN_DIV_INTEL: return "获取自身情报"
		BargainEffect.GAIN_RIVAL_DIV_INTEL: return "获取仇敌情报"
		BargainEffect.FORM_TRUST_ANY_GAIN_INTEL: return "与随机成员结盟"
		BargainEffect.DROP_RANDOM_ITEM: return "掉落道具"
		BargainEffect.REMOVE_FROM_SYNDICATE: return "自身退出辛迪加"
		BargainEffect.RECRUIT_FREE_AGENT: return "招募自由人"
		BargainEffect.REMOVE_ALL_RIVALRIES_IN_DIV: return "清空部门红线"
		BargainEffect.DESTROY_OWN_DIV_EQUIP: return "摧毁部门装备"
		BargainEffect.SWAP_DIVISION: return "调换部门职务"
		BargainEffect.COMPLETE_INTERROGATIONS: return "释放全部囚犯"
	return "未知"
