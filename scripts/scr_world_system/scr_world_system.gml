function WorldSystem(_game) constructor {
	
	game = _game;
	config = game.config;
	
	is_peeking = false;
	
	defender_grid = {
		
		team: FortinTeam.DEFENDERS,
		x: config.build_x,
		y: config.build_y,
		cols: config.build_cols,
		rows: config.build_rows,
		occupancy: array_create(config.build_cols * config.build_rows, undefined),
	};
	
	goblin_grid = {
		team: FortinTeam.GOBLINS,
		x: config.build_x + config.build_w + config.grid_gap,
		y: config.build_y,
		cols: config.build_cols,
		rows: config.build_rows,
		occupancy: array_create(config.build_cols * config.build_rows, undefined),
	};

	battle_grid = {
		team: -1,
		x: config.build_x,
		y: config.build_y,
		cols: config.build_cols * 2,
		rows: config.build_rows,
		occupancy: array_create(config.build_cols * 2 * config.build_rows, undefined),
	};

	vault = {
		col: 0,
		row: config.build_rows - 3,

		width: 3,
		height: 3,

		hp: 1000,
		max_hp: 1000,

		team: FortinTeam.DEFENDERS,
	};

	function use_build_layout() {
		defender_grid.x = config.build_x;
		defender_grid.y = config.build_y;

		goblin_grid.x = config.build_x + config.build_w + config.grid_gap;
		goblin_grid.y = config.build_y;

		battle_grid.x = defender_grid.x;
		battle_grid.y = defender_grid.y;

		if (variable_struct_exists(game, "structures") && is_struct(game.structures)) {
			game.structures.invalidate_collision_cache();
		}
	}

	function use_battle_layout() {
	    var battle_x = (config.screen_w - config.build_w * 2) * 0.5;

	    defender_grid.x = battle_x;
	    defender_grid.y = config.build_y;

	    goblin_grid.x = defender_grid.x + config.build_w;
	    goblin_grid.y = config.build_y;

	    battle_grid.x = defender_grid.x;
	    battle_grid.y = defender_grid.y;
	    battle_grid.cols = config.build_cols * 2;
	    battle_grid.rows = config.build_rows;

	    battle_grid.occupancy = array_create(
	        battle_grid.cols * battle_grid.rows,
	        undefined
	    );

	    if (variable_struct_exists(game, "structures") && is_struct(game.structures)) {
	        game.structures.invalidate_collision_cache();
	    }
	}
	
	function get_grid_for_team(_team) {
		return (_team == FortinTeam.GOBLINS) ? goblin_grid : defender_grid;
	};
	
	function get_active_grid() {
		if (game.state == FortinState.BATTLE) return battle_grid;

	    var local_team = game.players.get_player_team(config.local_player_id);
	    return self.get_grid_for_team(local_team);
	}

	function reset_build_grids() {

		defender_grid.occupancy = array_create(
			config.build_cols * config.build_rows,
			undefined
		);

		goblin_grid.occupancy = array_create(
			config.build_cols * config.build_rows,
			undefined
		);

		self.reset_vault(); // <-- nueva

		self.use_build_layout();

	};
		
	function toggle_peek() {
	    if (game.state != FortinState.BUILD) return false;

	    is_peeking = !is_peeking;

	    if (is_peeking && variable_struct_exists(game, "build") && is_struct(game.build)) {
	        game.build.select_tool(BuildTool.NONE);
	    }

	    return is_peeking;
	}

	function get_view_grid() {
	    if (game.state == FortinState.BATTLE) return battle_grid;

	    var local_team = game.players.get_player_team(config.local_player_id);

	    if (is_peeking) {
	        var enemy_team = (local_team == FortinTeam.GOBLINS)
	            ? FortinTeam.DEFENDERS
	            : FortinTeam.GOBLINS;

	        return self.get_grid_for_team(enemy_team);
	    }

	    return self.get_grid_for_team(local_team);
	}

	function cell_to_world(_grid, _col, _row) {
		return {
			x: _grid.x + _col * config.cell,
			y: _grid.y + _row * config.cell,
		};
	};

	function get_vault() {
		return vault;
	}

	function reset_vault() {
		vault.hp = vault.max_hp;
	}

	function vault_cell_occupied(_grid, _col, _row) {

		if (_grid.team != FortinTeam.DEFENDERS)
			return false;

		return (
			_col >= vault.col &&
			_col < vault.col + vault.width &&
			_row >= vault.row &&
			_row < vault.row + vault.height
		);

	}

	function get_vault_world_position() {

		return self.cell_to_world(
			defender_grid,
			vault.col,
			vault.row
		);

	}

	function get_vault_attack_point() {

		var vault = self.get_vault();
		var pos = self.get_vault_world_position();

		return {

			x: pos.x,
			y: pos.y + vault.height * config.cell * 0.5,

		};

	}

	function get_anchor_pos(_pos, _structure_def) {
		var ax = variable_struct_exists(_structure_def, "anchor_x") ? _structure_def.anchor_x : 0;
		var ay = variable_struct_exists(_structure_def, "anchor_y") ? _structure_def.anchor_y : 0;

		return {
			x: _pos.x + ax * config.cell,
			y: _pos.y + ay * config.cell,
		};
	}
		
	function world_to_cell(_grid, _x, _y) {
		return {
			col: floor((_x - _grid.x) / config.cell),
			row: floor((_y - _grid.y) / config.cell),
		};
	};

	function in_bounds(_grid, _col, _row) {
		return _col >= 0 && _row >= 0 && _col < _grid.cols && _row < _grid.rows;
	};

	function get_floor_y(_grid) {
		return _grid.y + _grid.rows * config.cell;
	};

	function get_left(_grid) {
		return _grid.x;
	};

	function get_right(_grid) {
		return _grid.x + _grid.cols * config.cell;
	};

	function get_bounds(_grid) {
		return {
			x1: _grid.x,
			y1: _grid.y,
			x2: _grid.x + _grid.cols * config.cell,
			y2: _grid.y + _grid.rows * config.cell,
		};
	};

	function get_player_spawn(_team, _slot) {
		var grid = self.get_grid_for_team(_team);
		return {
			x: grid.x + config.cell * (2 + _slot) + config.cell * 0.5,
			y: self.get_floor_y(grid),
		};
	};

	function player_to_cell(_player) {
		var grid = self.get_grid_for_team(_player.team);

		var col = floor((_player.x - grid.x) / config.cell);
		var row = floor((_player.y - grid.y) / config.cell);

		if (row >= grid.rows) row = grid.rows - 1;

		return {
			col: clamp(col, 0, grid.cols - 1),
			row: clamp(row, 0, grid.rows - 1),
		};
	};

	function player_build_cell(_player) {
		var grid = self.get_grid_for_team(_player.team);

		var col = floor((_player.x - grid.x) / config.cell);
		var player_mid_y = _player.y
			+ ((sprite_get_bbox_top(spr_player) + sprite_get_bbox_bottom(spr_player) + 1) * 0.5)
			- sprite_get_yoffset(spr_player);

		var row = floor((player_mid_y - grid.y) / config.cell);
		
		return {
			col: clamp(col, 0, grid.cols - 1),
			row: clamp(row, 0, grid.rows - 1),
		};
	};

	function draw_world() {
		
		var pos = self.get_vault_world_position();

		draw_sprite(
			spr_obj_vault,
			0,
			pos.x,
			pos.y
		);

	}	

}
