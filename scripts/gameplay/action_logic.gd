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
	GAIN_OTHER_DIV_INTEL,
	USURP
}

static func _roll_betray_effect(gm, member, other) -> int:
	var pool: Array[int] = []
	var is_sup_sub = _is_hierarchy_pair(member, other, gm.Division.NONE)
	var diff_div = (member.division != other.division) and (member.division != gm.Division.NONE) and (other.division != gm.Division.NONE)
	
	if is_sup_sub and not member.is_leader:
		pool.append(BetrayEffect.USURP)
		pool.append(BetrayEffect.REMOVE_FROM_SYNDICATE)
		pool.append(BetrayEffect.STEAL_RANK)
		pool.append(BetrayEffect.INCREASE_INTEL_MAKE_RIVALRY)
	else:
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
	REMOVE_FROM_SYNDICATE,
	REMOVE_ALL_RIVALRIES_IN_DIV,
	DESTROY_OWN_DIV_EQUIP,
	SWAP_DIVISION,
	COMPLETE_INTERROGATIONS,
	DROP_LEGENDARY,
	DROP_CURRENCY,
	DROP_VEILED,
	DROP_MAP,
	DROP_SCARAB
}

static func _roll_bargain_effect(gm, member) -> int:
	var pool: Array[int] = []
	pool.append(BargainEffect.GAIN_OWN_DIV_INTEL)
	pool.append(BargainEffect.GAIN_RIVAL_DIV_INTEL)
	pool.append(BargainEffect.REMOVE_FROM_SYNDICATE)
	pool.append(BargainEffect.DESTROY_OWN_DIV_EQUIP)
	pool.append(BargainEffect.DROP_LEGENDARY)
	pool.append(BargainEffect.DROP_CURRENCY)
	pool.append(BargainEffect.DROP_VEILED)
	pool.append(BargainEffect.DROP_MAP)
	pool.append(BargainEffect.DROP_SCARAB)
	
	var can_form_trust = false
	var same_rank_same_pos_diff_div = false
	var has_any_rivalry_in_div = false
	
	var effective_div = member.division
	if effective_div == gm.Division.NONE:
		effective_div = gm.current_encounter.get("division", gm.Division.NONE)
	
	for mname in gm.members:
		var m = gm.members[mname]
		if not m.is_on_board or m.member_name == member.member_name: continue
		if m.is_revealed:
			var rel = gm.get_relationship_between(member.member_name, mname)
			if rel == null or rel.type != gm.RelationType.TRUST:
				can_form_trust = true
		if m.rank == member.rank and m.is_leader == member.is_leader and member.rank > 0 and m.division != member.division and m.division != gm.Division.NONE and m.is_revealed and not m.is_imprisoned:
			same_rank_same_pos_diff_div = true
			
	if can_form_trust: pool.append(BargainEffect.FORM_TRUST_ANY_GAIN_INTEL)
	if same_rank_same_pos_diff_div: pool.append(BargainEffect.SWAP_DIVISION)
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
			if cm.is_on_board and not cm.is_imprisoned and cm.is_leader == member.is_leader and cm.rank == member.rank and cm.division != member.division and cm.division != gm.Division.NONE and cm.is_revealed:
				valid_targets.append(cm)
		if valid_targets.size() > 0:
			member.cached_bargain_target = valid_targets[randi() % valid_targets.size()].member_name
	elif chosen == BargainEffect.FORM_TRUST_ANY_GAIN_INTEL:
		var valid_targets = []
		for k in gm.members:
			var cm = gm.members[k]
			if cm.is_on_board and cm.member_name != member.member_name and cm.is_revealed:
				var rel = gm.get_relationship_between(member.member_name, cm.member_name)
				if rel == null or rel.type != gm.RelationType.TRUST:
					valid_targets.append(cm)
		if valid_targets.size() > 0:
			member.cached_bargain_target = valid_targets[randi() % valid_targets.size()].member_name

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
			var is_leader = member.is_leader
			var intel_points = 1
			if member.division == gm.Division.NONE:
				intel_points = 1
			elif is_leader:
				intel_points = member.rank * 3
			else:
				intel_points = member.rank * 2
			intel_points = max(1, intel_points)
			return name + "被囚禁" + str(gm.PRISON_DURATION) + "回合。+" + str(intel_points) + div_name + "情报每回合。释放后等级-1"
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
				BetrayEffect.INCREASE_INTEL_MAKE_RIVALRY: return "+6" + div_name + "情报。" + name + "和" + target_name + "变成敌对"
				BetrayEffect.STEAL_RANK: 
					var t_rank = target.rank if target else 0
					return "为" + name + "+" + str(t_rank) + "等级。" + target_name + "失去所有等级。" + name + "和" + target_name + "变成敌对"
				BetrayEffect.REMOVE_FROM_SYNDICATE: return target_name + "已从不朽辛迪加中被除名"
				BetrayEffect.RAISE_OWN_DIV_LOWER_OTHER_DIV: return div_name + "成员等级+1。" + target_div_name + "成员等级-1"
				BetrayEffect.DESTROY_OTHER_DIV_EQUIP: return "摧毁" + target_div_name + "成员装备"
				BetrayEffect.GAIN_OTHER_DIV_INTEL: return "+20" + target_div_name + "情报"
				BetrayEffect.USURP: return name + "变为" + div_name + "的首领。" + name + "和" + target_name + "变成敌对"
			return "背叛 " + target_name
		gm.ActionType.BARGAIN:
			var effect = member.cached_bargain_effect
			match effect:
				BargainEffect.GAIN_OWN_DIV_INTEL: return "+6" + div_name + "情报"
				BargainEffect.GAIN_RIVAL_DIV_INTEL: return "+16" + div_name + "情报"
				BargainEffect.FORM_TRUST_ANY_GAIN_INTEL:
					var t_m = gm.members.get(member.cached_bargain_target)
					if t_m == null:
						return "与随机成员结盟"
					var t_name = t_m.member_name
					var t_div_name = gm.DIVISION_NAMES.get(t_m.division, "自由人") if t_m.division != gm.Division.NONE else "自由人"
					if t_m.division == gm.Division.NONE:
						return t_name + "去往" + div_name + "。" + name + "和" + t_name + "变为信任"
					else:
						var rel = gm.get_relationship_between(member.member_name, t_name)
						if rel and rel.type == gm.RelationType.RIVALRY:
							return name + "和" + t_name + "变为中立。+4" + t_div_name + "情报"
						else:
							return name + "和" + t_name + "变为信任。+4" + t_div_name + "情报"
				BargainEffect.REMOVE_FROM_SYNDICATE: return name + "已从不朽辛迪加中被除名"
				BargainEffect.REMOVE_ALL_RIVALRIES_IN_DIV: return "移除" + div_name + "成员的所有死敌"
				BargainEffect.DESTROY_OWN_DIV_EQUIP: return "摧毁" + div_name + "成员的所有装备"
				BargainEffect.SWAP_DIVISION: 
					var t_m = gm.members.get(member.cached_bargain_target)
					if t_m == null:
						return "与同星级同职务成员互换部门"
					var t_div_name = gm.DIVISION_NAMES.get(t_m.division, "无") if t_m.division != gm.Division.NONE else "无"
					return name + "去往" + t_div_name + "。" + t_m.member_name + "去往" + div_name
				BargainEffect.COMPLETE_INTERROGATIONS:
					var total_intel = 0
					for qname in gm.prison_queue:
						var prisoner = gm.members.get(qname)
						if prisoner:
							var turns = maxi(prisoner.prison_turns_left, 0)
							var pt = prisoner.prison_intel_per_turn_points
							total_intel += (turns * pt)
					return "所有的囚犯都被释放了。+" + str(total_intel) + "情报"
				BargainEffect.DROP_LEGENDARY: return "丢下一个传奇道具"
				BargainEffect.DROP_CURRENCY: return "丢下一些通货物品"
				BargainEffect.DROP_VEILED: return "掉落一些加密物品"
				BargainEffect.DROP_MAP: return "丢下一张地图"
				BargainEffect.DROP_SCARAB: return "掉落一些圣甲虫"
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

	var was_leader = m.is_leader
	if m.is_leader: _leader_step_down(gm, m, result)

	m.is_imprisoned = true
	m.prison_turns_left = gm.PRISON_DURATION
	m.prison_rank_snapshot = clampi(m.rank, 0, 3)
	
	var intel_points = 1
	if m.division == gm.Division.NONE:
		intel_points = 1
	elif was_leader:
		intel_points = m.prison_rank_snapshot * 3
	else:
		intel_points = m.prison_rank_snapshot * 2
	intel_points = max(1, intel_points)
	
	m.prison_intel_per_turn_points = intel_points
	m.prison_intel_division = gm.current_encounter.get("division", gm.Division.NONE)
	gm.prison_queue.append(m.member_name)

	var div_name = gm.DIVISION_NAMES.get(m.prison_intel_division, "无") if m.prison_intel_division != gm.Division.NONE else "无"
	result.effects.append(m.member_name + "被囚禁" + str(gm.PRISON_DURATION) + "回合。+" + str(intel_points) + div_name + "情报每回合。释放后等级-1")
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
	var was_free_agent: bool = (m.rank == 0 and m.division == gm.Division.NONE)

	if m.rank < 3:
		m.rank += 1
		result.effects.append(m.member_name + " 升至 " + str(m.rank) + " 星")
	else:
		result.effects.append(m.member_name + " 已是最高等级（无升星效果）")

	if was_free_agent:
		var enc_div: int = gm.current_encounter.get("division", gm.Division.NONE)
		var slot_count: int = gm.get_division_slot_count(enc_div)
		if enc_div != gm.Division.NONE and slot_count < gm.MAX_MEMBERS_PER_DIVISION:
			m.division = enc_div
			result.effects.append(m.member_name + " 加入 " + gm.DIVISION_NAMES.get(enc_div, ""))
		else:
			m.rank = 0
			if result.effects.size() > 0:
				result.effects.pop_back()
			result.effects.append(m.member_name + " 试图加入，但部门已满（仍为0星自由人）")

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
				gm._add_intel_points_to_division(m.division, 6)
			gm._set_relationship_type(m.member_name, target.member_name, gm.RelationType.RIVALRY)
			result.effects.append("+6" + div_name + "情报。" + m.member_name + "和" + target.member_name + "变成敌对")
			
		BetrayEffect.STEAL_RANK:
			var target_rank = target.rank
			m.rank = mini(3, m.rank + target_rank)
			target.rank = 0
			if target.is_leader: 
				_leader_step_down(gm, target, result)
			target.division = gm.Division.NONE
			gm._set_relationship_type(m.member_name, target.member_name, gm.RelationType.RIVALRY)
			result.effects.append("为" + m.member_name + "+" + str(target_rank) + "等级。" + target.member_name + "失去所有等级。" + m.member_name + "和" + target.member_name + "变成敌对")
			
		BetrayEffect.REMOVE_FROM_SYNDICATE:
			_kick_member_and_replace(gm, target, result)
			
		BetrayEffect.RAISE_OWN_DIV_LOWER_OTHER_DIV:
			if m.division != gm.Division.NONE:
				var m_divs = gm.get_division_members(m.division)
				for md in m_divs: md.rank = mini(3, md.rank + 1)
				var leader_m = gm.get_division_leader(m.division)
				if leader_m: leader_m.rank = mini(3, leader_m.rank + 1)
			if target.division != gm.Division.NONE:
				var t_divs = gm.get_division_members(target.division)
				var leader_t = gm.get_division_leader(target.division)
				var to_demote = []
				to_demote.append_array(t_divs)
				if leader_t: to_demote.append(leader_t)
				for td in to_demote: 
					var old_rank = td.rank
					td.rank = maxi(0, td.rank - 1)
					if td.rank < old_rank and td.is_leader:
						_leader_step_down(gm, td, result)
					if td.rank == 0: 
						td.division = gm.Division.NONE
			gm._remove_relationship(m.member_name, target.member_name)
			result.effects.append(div_name + "成员等级+1。" + target_div_name + "成员等级-1")
				
		BetrayEffect.DESTROY_OTHER_DIV_EQUIP:
			if target.division != gm.Division.NONE:
				var t_divs = gm.get_division_members(target.division)
				var leader_t = gm.get_division_leader(target.division)
				var to_destroy = []
				to_destroy.append_array(t_divs)
				if leader_t: to_destroy.append(leader_t)
				for td in to_destroy: td.equipment_count = 0
			gm._remove_relationship(m.member_name, target.member_name)
			result.effects.append("摧毁" + target_div_name + "成员装备")
				
		BetrayEffect.GAIN_OTHER_DIV_INTEL:
			if target.division != gm.Division.NONE:
				gm._add_intel_points_to_division(target.division, 20)
			gm._remove_relationship(m.member_name, target.member_name)
			result.effects.append("+20" + target_div_name + "情报")

		BetrayEffect.USURP:
			m.is_leader = true
			target.is_leader = false
			gm._set_relationship_type(m.member_name, target.member_name, gm.RelationType.RIVALRY)
			result.effects.append(m.member_name + "变为" + div_name + "的首领。" + m.member_name + "和" + target.member_name + "变成敌对")

static func _do_bargain(gm, m, result: Dictionary):
	var effect = m.cached_bargain_effect
	var effective_div = m.division
	if effective_div == gm.Division.NONE:
		effective_div = gm.current_encounter.get("division", gm.Division.NONE)
	var div_name = gm.DIVISION_NAMES.get(effective_div, "无")
	
	match effect:
		BargainEffect.GAIN_OWN_DIV_INTEL:
			if effective_div != gm.Division.NONE:
				gm._add_intel_points_to_division(effective_div, 6)
				result.effects.append("+6" + div_name + "情报")
				
		BargainEffect.GAIN_RIVAL_DIV_INTEL:
			if effective_div != gm.Division.NONE:
				gm._add_intel_points_to_division(effective_div, 16)
				result.effects.append("+16" + div_name + "情报")
					
		BargainEffect.FORM_TRUST_ANY_GAIN_INTEL:
			var t = gm.members.get(m.cached_bargain_target)
			if t:
				var t_name = t.member_name
				var t_div_name = gm.DIVISION_NAMES.get(t.division, "自由人") if t.division != gm.Division.NONE else "自由人"
				
				if t.division == gm.Division.NONE:
					t.rank = 1
					t.division = effective_div
					var rel = gm.get_relationship_between(m.member_name, t_name)
					if rel and rel.type == gm.RelationType.RIVALRY:
						gm._remove_relationship(m.member_name, t_name)
					else:
						gm._set_relationship_type(m.member_name, t_name, gm.RelationType.TRUST)
					result.effects.append(t_name + "去往" + div_name + "。" + m.member_name + "和" + t_name + "变为信任")
				else:
					var rel = gm.get_relationship_between(m.member_name, t_name)
					if rel and rel.type == gm.RelationType.RIVALRY:
						gm._remove_relationship(m.member_name, t_name)
						result.effects.append(m.member_name + "和" + t_name + "变为中立。+4" + t_div_name + "情报")
					else:
						gm._set_relationship_type(m.member_name, t_name, gm.RelationType.TRUST)
						result.effects.append(m.member_name + "和" + t_name + "变为信任。+4" + t_div_name + "情报")
					if t.division != gm.Division.NONE:
						gm._add_intel_points_to_division(t.division, 4)
					
		BargainEffect.REMOVE_FROM_SYNDICATE:
			_kick_member_and_replace(gm, m, result)
					
		BargainEffect.REMOVE_ALL_RIVALRIES_IN_DIV:
			if effective_div != gm.Division.NONE:
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
				result.effects.append("移除" + div_name + "成员的所有死敌")
				
		BargainEffect.DESTROY_OWN_DIV_EQUIP:
			if effective_div != gm.Division.NONE:
				var m_divs = gm.get_division_members(effective_div)
				var leader_m = gm.get_division_leader(effective_div)
				var all_own = []
				all_own.append_array(m_divs)
				if leader_m: all_own.append(leader_m)
				for md in all_own: md.equipment_count = 0
				result.effects.append("摧毁" + div_name + "成员的所有装备")
				
		BargainEffect.SWAP_DIVISION:
			var t = gm.members.get(m.cached_bargain_target)
			if t:
				var old_div = m.division
				var old_leader = m.is_leader
				m.division = t.division
				m.is_leader = t.is_leader
				t.division = old_div
				t.is_leader = old_leader
				var old_div_name = gm.DIVISION_NAMES.get(old_div, "无")
				var t_div_name = gm.DIVISION_NAMES.get(m.division, "无")
				result.effects.append(m.member_name + "去往" + t_div_name + "。" + t.member_name + "去往" + old_div_name)
				
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
			if released_any: result.effects.append("所有的囚犯都被释放了。+" + str(total_added) + "情报")
			else: result.effects.append("当前无囚犯，无效果")

		BargainEffect.DROP_LEGENDARY: result.effects.append("丢下一个传奇道具")
		BargainEffect.DROP_CURRENCY: result.effects.append("丢下一些通货物品")
		BargainEffect.DROP_VEILED: result.effects.append("掉落一些加密物品")
		BargainEffect.DROP_MAP: result.effects.append("丢下一张地图")
		BargainEffect.DROP_SCARAB: result.effects.append("掉落一些圣甲虫")

	if effect == -1:
		if effective_div != gm.Division.NONE:
			gm._add_intel_points_to_division(effective_div, 6)
			result.effects.append("+6" + div_name + "情报")
		else:
			result.effects.append("无部门可获得情报")

static func _kick_member_and_replace(gm, m, result: Dictionary):
	var kicked_name: String = m.member_name
	var orig_div: int = m.division
	
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
	
	var to_remove: Array = []
	for rel in gm.relationships:
		if rel.member_a == kicked_name or rel.member_b == kicked_name:
			to_remove.append(rel)
	for rel in to_remove:
		gm.relationships.erase(rel)
	
	var enc_members = gm.current_encounter.get("members", [])
	var processed_list = gm.current_encounter.get("processed", [])
	for em in enc_members:
		if em.member_name == kicked_name and not (kicked_name in processed_list):
			processed_list.append(kicked_name)
			break
	
	result.effects.append(kicked_name + "已从不朽辛迪加中被除名")

	if not (kicked_name in gm.bench_pool):
		gm.bench_pool.append(kicked_name)

	# ===== 从替补席（bench_pool）中挑选新成员作为自由人补位上场（未翻牌，不提示身份） =====
	var candidate_name: String = ""
	for b_name in gm.bench_pool:
		if b_name != kicked_name:
			candidate_name = b_name
			break

	if candidate_name != "":
		gm.bench_pool.erase(candidate_name)
		var new_m = gm.members.get(candidate_name)
		if new_m:
			new_m.is_on_board = true
			new_m.is_revealed = false         # 未被翻牌的状态
			new_m.rank = 0                    # 0星自由人
			new_m.division = gm.Division.NONE # 默认为自由人
			new_m.is_leader = false
			new_m.is_imprisoned = false
			new_m.equipment_count = 0

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
		BetrayEffect.GAIN_OTHER_DIV_INTEL,
		BetrayEffect.USURP
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
		elif effect_id == BetrayEffect.USURP:
			is_valid = is_sup_sub and not member.is_leader
			
		var desc := ""
		if is_valid:
			match effect_id:
				BetrayEffect.INCREASE_INTEL_MAKE_RIVALRY: desc = "+6" + div_name + "情报。" + member.member_name + "和" + target_name + "变成敌对"
				BetrayEffect.STEAL_RANK: 
					var t_rank = target.rank if target else 0
					desc = "为" + member.member_name + "+" + str(t_rank) + "等级。" + target_name + "失去所有等级。" + member.member_name + "和" + target_name + "变成敌对"
				BetrayEffect.REMOVE_FROM_SYNDICATE: desc = target_name + "已从不朽辛迪加中被除名"
				BetrayEffect.RAISE_OWN_DIV_LOWER_OTHER_DIV: desc = div_name + "成员等级+1。" + target_div_name + "成员等级-1"
				BetrayEffect.DESTROY_OTHER_DIV_EQUIP: desc = "摧毁" + target_div_name + "成员装备"
				BetrayEffect.GAIN_OTHER_DIV_INTEL: desc = "+20" + target_div_name + "情报"
				BetrayEffect.USURP: desc = member.member_name + "变为" + div_name + "的首领。" + member.member_name + "和" + target_name + "变成敌对"

		list.append({
			"id": effect_id,
			"name": get_betray_effect_name(effect_id),
			"description": desc,
			"is_valid": is_valid
		})
	return list

static func get_betray_effect_name(effect_id: int) -> String:
	match effect_id:
		BetrayEffect.INCREASE_INTEL_MAKE_RIVALRY: return "窃取情报"
		BetrayEffect.STEAL_RANK: return "窃取阶级"
		BetrayEffect.REMOVE_FROM_SYNDICATE: return "逐出组织"
		BetrayEffect.RAISE_OWN_DIV_LOWER_OTHER_DIV: return "打压宿敌"
		BetrayEffect.DESTROY_OTHER_DIV_EQUIP: return "摧毁敌对部门装备"
		BetrayEffect.GAIN_OTHER_DIV_INTEL: return "获取对方部门情报"
		BetrayEffect.USURP: return "篡位"
	return "未知"

static func get_bargain_effects_status(gm, member) -> Array:
	var effective_div = member.division
	if effective_div == gm.Division.NONE:
		effective_div = gm.current_encounter.get("division", gm.Division.NONE)
	
	var div_name = gm.DIVISION_NAMES.get(effective_div, "无")
	var name = member.member_name
	
	var board_count = 0
	var valid_swap_targets = []
	var has_any_rivalry_in_div = false
	
	for mname in gm.members:
		var m = gm.members[mname]
		if not m.is_on_board or m.member_name == member.member_name: continue
		if m.is_revealed: board_count += 1
		if m.rank == member.rank and m.is_leader == member.is_leader and member.rank > 0 and m.division != member.division and m.division != gm.Division.NONE and m.is_revealed and not m.is_imprisoned:
			valid_swap_targets.append(m)

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
		BargainEffect.REMOVE_FROM_SYNDICATE,
		BargainEffect.REMOVE_ALL_RIVALRIES_IN_DIV,
		BargainEffect.DESTROY_OWN_DIV_EQUIP,
		BargainEffect.SWAP_DIVISION,
		BargainEffect.COMPLETE_INTERROGATIONS,
		BargainEffect.DROP_LEGENDARY,
		BargainEffect.DROP_CURRENCY,
		BargainEffect.DROP_VEILED,
		BargainEffect.DROP_MAP,
		BargainEffect.DROP_SCARAB
	]

	for effect_id in bargain_effects:
		var is_valid := false
		var target := ""
		
		match effect_id:
			BargainEffect.GAIN_OWN_DIV_INTEL, BargainEffect.GAIN_RIVAL_DIV_INTEL, BargainEffect.DROP_LEGENDARY, BargainEffect.DROP_CURRENCY, BargainEffect.DROP_VEILED, BargainEffect.DROP_MAP, BargainEffect.DROP_SCARAB, BargainEffect.REMOVE_FROM_SYNDICATE, BargainEffect.DESTROY_OWN_DIV_EQUIP:
				is_valid = true
			BargainEffect.FORM_TRUST_ANY_GAIN_INTEL:
				is_valid = board_count > 0
				if is_valid:
					var valid_targets = []
					for k in gm.members:
						var cm = gm.members[k]
						if cm.is_on_board and cm.member_name != member.member_name and cm.is_revealed:
							var rel = gm.get_relationship_between(member.member_name, cm.member_name)
							if rel == null or rel.type != gm.RelationType.TRUST:
								valid_targets.append(cm)
					if valid_targets.size() > 0:
						target = valid_targets.pick_random().member_name
			BargainEffect.SWAP_DIVISION:
				is_valid = valid_swap_targets.size() > 0
				if is_valid:
					target = valid_swap_targets.pick_random().member_name
			BargainEffect.COMPLETE_INTERROGATIONS:
				is_valid = gm.prison_queue.size() > 0
			BargainEffect.REMOVE_ALL_RIVALRIES_IN_DIV:
				is_valid = has_any_rivalry_in_div
				
		var desc := ""
		if is_valid:
			match effect_id:
				BargainEffect.GAIN_OWN_DIV_INTEL: desc = "+6" + div_name + "情报"
				BargainEffect.GAIN_RIVAL_DIV_INTEL: desc = "+16" + div_name + "情报"
				BargainEffect.FORM_TRUST_ANY_GAIN_INTEL:
					var t_name = target if target != "" else "随机成员"
					var t_m = gm.members.get(t_name)
					if t_m == null:
						desc = "与随机成员结盟"
					else:
						var t_div_name = gm.DIVISION_NAMES.get(t_m.division, "自由人") if t_m.division != gm.Division.NONE else "自由人"
						if t_m.division == gm.Division.NONE:
							desc = t_name + "去往" + div_name + "。" + name + "和" + t_name + "变为信任"
						else:
							var rel = gm.get_relationship_between(member.member_name, t_name)
							if rel and rel.type == gm.RelationType.RIVALRY:
								desc = name + "和" + t_name + "变为中立。+4" + t_div_name + "情报"
							else:
								desc = name + "和" + t_name + "变为信任。+4" + t_div_name + "情报"
				BargainEffect.DROP_LEGENDARY: desc = "丢下一个传奇道具"
				BargainEffect.DROP_CURRENCY: desc = "丢下一些通货物品"
				BargainEffect.DROP_VEILED: desc = "掉落一些加密物品"
				BargainEffect.DROP_MAP: desc = "丢下一张地图"
				BargainEffect.DROP_SCARAB: desc = "掉落一些圣甲虫"
				BargainEffect.REMOVE_FROM_SYNDICATE: desc = name + "已从不朽辛迪加中被除名"
				BargainEffect.REMOVE_ALL_RIVALRIES_IN_DIV: desc = "移除" + div_name + "成员的所有死敌"
				BargainEffect.DESTROY_OWN_DIV_EQUIP: desc = "摧毁" + div_name + "成员的所有装备"
				BargainEffect.SWAP_DIVISION:
					var t_m = gm.members.get(target)
					if t_m == null:
						desc = "与同星级同职务成员互换部门"
					else:
						var t_div_name = gm.DIVISION_NAMES.get(t_m.division, "无") if t_m.division != gm.Division.NONE else "无"
						desc = name + "去往" + t_div_name + "。" + t_m.member_name + "去往" + div_name
				BargainEffect.COMPLETE_INTERROGATIONS:
					var total_intel = 0
					for qname in gm.prison_queue:
						var prisoner = gm.members.get(qname)
						if prisoner:
							var turns = maxi(prisoner.prison_turns_left, 0)
							var pt = prisoner.prison_intel_per_turn_points
							total_intel += (turns * pt)
					desc = "所有的囚犯都被释放了。+" + str(total_intel) + "情报"

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
		BargainEffect.GAIN_OWN_DIV_INTEL: return "获取情报"
		BargainEffect.GAIN_RIVAL_DIV_INTEL: return "获取大量情报"
		BargainEffect.FORM_TRUST_ANY_GAIN_INTEL: return "结盟"
		BargainEffect.REMOVE_FROM_SYNDICATE: return "退出组织"
		BargainEffect.REMOVE_ALL_RIVALRIES_IN_DIV: return "化解部门恩怨"
		BargainEffect.DESTROY_OWN_DIV_EQUIP: return "摧毁部门装备"
		BargainEffect.SWAP_DIVISION: return "调动职位"
		BargainEffect.COMPLETE_INTERROGATIONS: return "劫狱"
		BargainEffect.DROP_LEGENDARY: return "获取传奇"
		BargainEffect.DROP_CURRENCY: return "获取通货"
		BargainEffect.DROP_VEILED: return "获取隐匿"
		BargainEffect.DROP_MAP: return "获取地图"
		BargainEffect.DROP_SCARAB: return "获取甲虫"
	return "未知"
