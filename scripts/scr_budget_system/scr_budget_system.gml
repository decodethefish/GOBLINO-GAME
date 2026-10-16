function BudgetSystem(_game) constructor {
	game = _game;
	config = game.config;

	defender_budget = 0;
	goblin_budget = 0;

	defender_base_budget = config.defender_start_budget;
	goblin_base_budget = config.goblin_start_budget;

	function reset() {
		defender_budget = defender_base_budget;
		goblin_budget = goblin_base_budget;
		
		show_debug_message("BUDGET reset() -> defender_base=" + string(defender_base_budget) + " goblin_base=" + string(goblin_base_budget));
		
	}

	function get_budget(_team) {
		switch (_team) {
			case FortinTeam.DEFENDERS:
				return defender_budget;

			case FortinTeam.GOBLINS:
				return goblin_budget;
		}

		return 0;
	}

	function can_afford(_team, _amount) {
		return self.get_budget(_team) >= _amount;
	}

	function spend(_team, _amount) {
		if (!self.can_afford(_team, _amount)) {
			return false;
		}

		switch (_team) {
			case FortinTeam.DEFENDERS:
				defender_budget -= _amount;
				break;

			case FortinTeam.GOBLINS:
				goblin_budget -= _amount;
				break;
		}

		return true;
	}

	function add(_team, _amount) {
		switch (_team) {
			case FortinTeam.DEFENDERS:
				defender_budget += _amount;
				break;

			case FortinTeam.GOBLINS:
				goblin_budget += _amount;
				break;
		}
	}

	function increase_percent(_percent) {
		defender_base_budget = round(defender_base_budget * (1 + _percent));
		goblin_base_budget = round(goblin_base_budget * (1 + _percent));
		
		show_debug_message("BUDGET increase_percent() DESPUES -> defender_base=" + string(defender_base_budget) + " goblin_base=" + string(goblin_base_budget));
		
	}

	reset();
}