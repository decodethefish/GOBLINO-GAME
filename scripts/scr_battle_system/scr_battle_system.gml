function BattleSystem(_game) constructor {

	game = _game;

	battle_timer_max = 100 * room_speed;
	battle_timer = battle_timer_max;

	function start() {

		var defender_from_x = game.world.defender_grid.x;
		var defender_from_y = game.world.defender_grid.y;
		var goblin_from_x = game.world.goblin_grid.x;
		var goblin_from_y = game.world.goblin_grid.y;

		game.world.use_battle_layout();
		game.players.move_players_between_layouts(
			defender_from_x,
			defender_from_y,
			goblin_from_x,
			goblin_from_y
		);

		game.build.reset();

		self.convert_all_troops();

		game.players.reset_combat_stats();

		game.camera.reset_to_grid();

		battle_timer = battle_timer_max;

	}

	function reset() {

		battle_timer = battle_timer_max;

	}

	function convert_all_troops() {

		for (var i = 0; i < array_length(game.structures.items); i++) {

			var structure = game.structures.items[i];

			if (!is_struct(structure)) continue;
			if (!structure.active) continue;

			self.convert_structure(structure);

		}

	}

	function convert_structure(_structure) {
		var def = game.data.get_structure_def(_structure.build_id);
		if (!is_struct(def)) return;
		if (def.type != ConstructionType.SOLDIER) return;

		game.troops.spawn_from_structure(_structure);
		_structure.active = false;
	}

	function team_has_living_units(_team) {

		for (var i = 0; i < array_length(game.troops.items); i++) {
			var troop = game.troops.items[i];
			if (!is_struct(troop)) continue;
			if (!troop.active) continue;
			if (troop.team == _team) return true;
		}

		for (var i = 0; i < array_length(game.players.players); i++) {
			var p = game.players.players[i];
			if (!is_struct(p)) continue;
			if (!p.active || !p.alive) continue;
			if (p.team == _team) return true;
		}

		return false;

	}

	function end_battle(_winner_team) {

		game.budget.increase_percent(0.3);

		if (game.network.is_connected) {
			game.network.broadcast_battle_end(
				_winner_team,
				game.budget.defender_base_budget,
				game.budget.goblin_base_budget
			);
		}

		game.start_results(_winner_team);

	}

	function update() {

		if (game.state != FortinState.BATTLE) return;

		battle_timer = max(0, battle_timer - 1);
		game.debuffs.update();

		// Solo el host decide el resultado — las tropas y estructuras
		// aun no sincronizan su HP por red, asi que confiar en cada
		// cliente por igual podria hacer que declaren ganadores distintos.
		if (game.network.is_connected && !game.network.is_host) return;

		var vault = game.world.get_vault();

		if (vault.hp <= 0) {
			self.end_battle(FortinTeam.GOBLINS);
			return;
		}

		if (!self.team_has_living_units(FortinTeam.GOBLINS)) {
			self.end_battle(FortinTeam.DEFENDERS);
			return;
		}

		if (battle_timer <= 0) {
			self.end_battle(FortinTeam.DEFENDERS);
			return;
		}

	}

	function finish() {

	}

	function destroy() {

	}

}