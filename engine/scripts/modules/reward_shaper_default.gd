extends "res://engine/scripts/modules/reward_shaper.gd"

class_name RewardShaperDefault



func reset(manager) -> void:

	if manager == null:

		return

	manager.last_alive = {1: true, 2: true}



func compute(manager, obs_p1: Dictionary, obs_p2: Dictionary, step_delta: float) -> Dictionary:

	if manager == null:

		return {"1": 0.0, "2": 0.0}

	var alive_p1: bool = manager._is_alive(obs_p1)

	var alive_p2: bool = manager._is_alive(obs_p2)

	var reward_p1: float = manager._get_bot_reward(1, "time_without_kill", manager.reward_time_without_kill, "step") * step_delta

	var reward_p2: float = manager._get_bot_reward(2, "time_without_kill", manager.reward_time_without_kill, "step") * step_delta

	if alive_p1:

		reward_p1 += manager._get_bot_reward(1, "time_alive", manager.reward_time_alive, "alive") * step_delta

	if alive_p2:

		reward_p2 += manager._get_bot_reward(2, "time_alive", manager.reward_time_alive, "alive") * step_delta

	if manager.last_alive.get(1, true) and not alive_p1:

		reward_p1 += manager._get_bot_reward(1, "death", manager.reward_death)

		reward_p2 += manager._get_bot_reward(2, "kill", manager.reward_kill)

		manager.round_deaths[1] = int(manager.round_deaths.get(1, 0)) + 1

		manager.round_kills[2] = int(manager.round_kills.get(2, 0)) + 1

	if manager.last_alive.get(2, true) and not alive_p2:

		reward_p2 += manager._get_bot_reward(2, "death", manager.reward_death)

		reward_p1 += manager._get_bot_reward(1, "kill", manager.reward_kill)

		manager.round_deaths[2] = int(manager.round_deaths.get(2, 0)) + 1

		manager.round_kills[1] = int(manager.round_kills.get(1, 0)) + 1

	manager.last_alive[1] = alive_p1

	manager.last_alive[2] = alive_p2

	return {"1": reward_p1, "2": reward_p2}

