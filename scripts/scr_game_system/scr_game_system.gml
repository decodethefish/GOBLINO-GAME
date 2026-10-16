function GameSystem() constructor {
	state = FortinState.LOBBY;
	round_index = 1;
	budget = 0;
	build_timer_max = 120 * room_speed;
	build_timer = build_timer_max;
	battle_winner = undefined;
	ready_players = [];
	
	config = new FortinConfig();
	data = new FortinData();

	world = new WorldSystem(self);
	network = new NetworkSystem(self);
	budget = new BudgetSystem(self);
	build = new BuildSystem(self);
	structures = new StructureSystem(self);
	collision = new CollisionSystem(self);
	troops = new TroopSystem(self);
	battle = new BattleSystem(self);
	paths = new PathSystem(self);
	projectiles = new ProjectileSystem(self);
	players = new PlayerSystem(self);
	camera = new CameraSystem(self);
	ui = new UISystem(self);
	debuffs = new DebuffSystem(self);

	function start_lobby() {
		state = FortinState.LOBBY;
	};

	function start_team_select() {
		state = FortinState.TEAM_SELECT;
	};

	function start_build() {
		state = FortinState.BUILD;

		build_timer_max = 120 * room_speed;
		build_timer = build_timer_max;
		
		budget.reset();

		world.reset_build_grids();
		
		troops.clear_troops();
		build.reset();
		structures.reset();
		troops.reset();
		battle.reset();
		projectiles.reset();
		players.reset();
	}
		
	function start_battle() {
		state = FortinState.BATTLE;

		battle.start();
	}

	function request_start_battle() {
		if (state != FortinState.BUILD) return false;
		if (network.is_connected && !network.is_host) return false;

		if (network.is_host) {
			network.broadcast_start_battle();
		}

		self.start_battle();
		return true;
	}

	function update_build_timer() {
		if (state != FortinState.BUILD) return;

		build_timer = max(0, build_timer - 1);

		if (build_timer <= 0) {
			self.request_start_battle();
		}
	}
		
	function start_results(_winner_team) {
		state = FortinState.RESULTS;
		battle_winner = _winner_team;
		ready_players = array_create(config.max_players, false);
	};

	function mark_ready(_player_id) {
		if (_player_id < 0 || _player_id >= array_length(ready_players)) return false;
		ready_players[_player_id] = true;
		return true;
	}

	function all_ready() {
		for (var i = 0; i < array_length(players.players); i++) {
			var p = players.players[i];
			if (!is_struct(p)) continue;
			if (!p.active) continue;
			if (!ready_players[i]) return false;
		}
		return true;
	}

	function update() {
		network.update();
		ui.update();

		if (keyboard_check_pressed(vk_f1)) start_lobby();
		if (keyboard_check_pressed(vk_f2)) start_build();
		if (keyboard_check_pressed(vk_f3)) request_start_battle();
		if (keyboard_check_pressed(vk_f4)) start_results();

		self.update_build_timer();

		build.update();
		players.update();
		structures.update();
		troops.update();
		battle.update();
		projectiles.update();
		camera.update();
	};

	function draw_world() {
		world.draw_world();
		build.draw_world();
		structures.draw_world();
		troops.draw_world();
		build.draw_world_overlay();
		projectiles.draw_world();
		if (state == FortinState.BUILD
		|| state == FortinState.BATTLE) {
			players.draw_world();
		}
		structures.draw_health_bars();
		troops.draw_health_bars();
		players.draw_health_bars();
		players.draw_debug_hitboxes();
	}

	function draw_gui() {
		ui.draw_gui();
		draw_text(20, 300, string(fps_real));
	};

	function destroy() {
		network.destroy();
		build.destroy();
		structures.destroy();
		troops.destroy();
		battle.destroy();
		projectiles.destroy();
		camera.destroy();
	}

	start_lobby();
}
