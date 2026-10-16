function BuildSystem(_game) constructor {
	selected_tool = BuildTool.NONE;
	selected_build_id = "MA1";
	grid = [];
	preview_valid = false;
	game = _game;
	config = game.config;
	view = new BuildGridView(self);

	hover_col = -1;
	hover_row = -1;
	hover_valid = false;
	
	pending_wall_active = false;
	pending_wall_col = -1;
	pending_wall_start_row = -1;
	pending_wall_cells = [];

	pending_delete_active = false;
	pending_delete_start_col = -1;
	pending_delete_start_row = -1;
	pending_delete_cells = [];
	
	pending_stair_active = false;
	pending_stair_col = -1;
	pending_stair_row = -1;
	pending_stair_cells = [];
	hover_stair_facing = 1;
	pending_stair_facing = 1;	
	
	
	pending_tower_active = false;
	pending_tower_col = -1;
	pending_tower_row = -1;
	pending_tower_height_segments = 1;
	tower_preview_col = -1;
	tower_preview_row = -1;
	tower_preview_height_segments = 1;

	function reset() {
		hover_col = -1;
		hover_row = -1;
		hover_valid = false;
		preview_valid = false;

		pending_wall_active = false;
		pending_wall_col = -1;
		pending_wall_start_row = -1;
		pending_wall_cells = [];

		pending_delete_active = false;
		pending_delete_start_col = -1;
		pending_delete_start_row = -1;
		pending_delete_cells = [];
		
		pending_stair_active = false;
		pending_stair_col = -1;
		pending_stair_row = -1;
		pending_stair_cells = [];
		hover_stair_facing = 1;
		pending_stair_facing = 1;

		pending_tower_active = false;
		pending_tower_col = -1;
		pending_tower_row = -1;
		pending_tower_height_segments = 1;
		tower_preview_col = -1;
		tower_preview_row = -1;
		tower_preview_height_segments = 1;
	};

	function get_active_grid() {
		return game.world.get_active_grid();
	};

	function get_grid_for_player(_player_id) {

	var team = game.players.get_player_team(_player_id);

	return game.world.get_grid_for_team(team);

}

	function in_bounds(_col, _row) {
		return game.world.in_bounds(self.get_active_grid(), _col, _row);
	};

	function world_to_cell(_x, _y) {
		return game.world.world_to_cell(self.get_active_grid(), _x, _y);
	};

	function cell_to_world(_col, _row) {
		return game.world.cell_to_world(self.get_active_grid(), _col, _row);
	};

	function grid_index(_col, _row, _grid = undefined) {
	    var grid = is_undefined(_grid) ? self.get_active_grid() : _grid;
	    return _row * grid.cols + _col;
	};

	function cell_free(_col, _row, _grid = undefined) {
	    if (!game.world.in_bounds(is_undefined(_grid) ? self.get_active_grid() : _grid, _col, _row)) return false;

	    var grid = is_undefined(_grid) ? self.get_active_grid() : _grid;

	    if (game.world.vault_cell_occupied(grid, _col, _row))
	        return false;

	    return is_undefined(
	        grid.occupancy[self.grid_index(_col, _row, grid)]
	    );
	}

	function make_structure_build_data(_facing = 1, _height_segments = 1) {
		return {
			facing: _facing,
			height_segments: _height_segments,
		};
	}

	function get_build_data_height_segments(_build_data) {
		if (!is_struct(_build_data)) return 1;
		if (!variable_struct_exists(_build_data, "height_segments")) return 1;

		return max(1, floor(_build_data.height_segments));
	}

	function get_structure_occupied_offsets(_structure_def, _build_data) {
		if (_structure_def.type != ConstructionType.TOWER) return _structure_def.occupied_offsets;

		var height_segments = self.get_build_data_height_segments(_build_data);
		var offsets = [];
		var top_row = -height_segments * 2 + 1;

		for (var dx = 0; dx < 2; dx++) {
			for (var dy = top_row; dy <= 1; dy++) {
				array_push(offsets, {
					dx: dx,
					dy: dy,
				});
			}
		}

		return offsets;
	}

	function can_place_structure(_build_id, _col, _row, _build_data = undefined, _owner_id = undefined) {
    var structure_def = game.data.get_structure_def(_build_id);
    if (!is_struct(structure_def)) return false;

    if (!is_undefined(_owner_id)) {
        var owner_team = game.players.get_player_team(_owner_id);
        if (owner_team != structure_def.allowed_team) return false;
    }

    var grid = is_undefined(_owner_id)
        ? self.get_active_grid()
        : self.get_grid_for_player(_owner_id);
		
	// Restricción de filas para tropas
	if (structure_def.type == ConstructionType.SOLDIER) {
		var troop_def = game.data.get_unit_def(structure_def.unit_id);

		if (is_struct(troop_def)) {
			var max_row = config.build_rows - 1;

			if (troop_def.movement_type == TroopMovementType.GROUND) {
				// Tropas terrestres: solo las 3 filas inferiores
				if (_row < max_row - 2) return false;
			}
			else if (troop_def.movement_type == TroopMovementType.AIR) {
				// Tropas aéreas: solo las 4 filas superiores
				if (_row > 9) return false;
			}
		}
	}

	if (structure_def.type == ConstructionType.TRAP) {
		if (!self.trap_has_support(grid, _col, _row)) return false;
	}

    var occupied_offsets = self.get_structure_occupied_offsets(structure_def, _build_data);

    for (var i = 0; i < array_length(occupied_offsets); i++) {
        var offset = occupied_offsets[i];
        var cell_col = _col + offset.dx;
        var cell_row = _row + offset.dy;

        if (!self.cell_free(cell_col, cell_row, grid)) return false;
    }

    return true;
}

	function claim_structure_cells(_structure) {
	if (!is_struct(_structure)) return false;

	var structure_def = game.data.get_structure_def(_structure.build_id);
	if (!is_struct(structure_def)) return false;

	var grid = self.get_grid_for_player(_structure.owner_id);

	var occupied_offsets = self.get_structure_occupied_offsets(structure_def, _structure);

	for (var i = 0; i < array_length(occupied_offsets); i++) {
		var offset = occupied_offsets[i];

		self.claim_cell(
			grid,
			_structure.col + offset.dx,
			_structure.row + offset.dy,
			_structure.structure_id
		);
	}

	return true;
}

	function release_structure_cells(_structure) {
	if (!is_struct(_structure)) return false;

	var structure_def = game.data.get_structure_def(_structure.build_id);
	if (!is_struct(structure_def)) return false;

	var grid = self.get_grid_for_player(_structure.owner_id);

	var occupied_offsets = self.get_structure_occupied_offsets(structure_def, _structure);

	for (var i = 0; i < array_length(occupied_offsets); i++) {
		var offset = occupied_offsets[i];

		self.release_cell(
			grid,
			_structure.col + offset.dx,
			_structure.row + offset.dy
		);
	}

	return true;
}

	function get_cell_structure_id(_grid, _col, _row) {
	    if (!game.world.in_bounds(_grid, _col, _row))
	        return undefined;

	    return _grid.occupancy[
	        self.grid_index(_col, _row, _grid)
	    ];
	}

	function trap_has_support(_grid, _col, _row) {
		if (_row >= config.build_rows - 1) return true;

		var sid = self.get_cell_structure_id(_grid, _col, _row + 1);
		if (is_undefined(sid)) return false;

		var below = game.structures.get_structure(sid);
		if (!is_struct(below)) return false;

		var def = game.data.get_structure_def(below.build_id);
		return is_struct(def) && def.type == ConstructionType.WALL;
	}

	function is_single_place_tool(_tool) {
		return _tool == BuildTool.SOLDIER || _tool == BuildTool.SNIPER || _tool == BuildTool.ENGINEER
			|| _tool == BuildTool.VENOM || _tool == BuildTool.SPIKES;
	}

	function near_local_player(_col, _row) {
		var p = game.players.get_local_player();
		if (is_undefined(p)) return false;

		var pc = game.world.player_build_cell(p);
		return abs(_col - pc.col) <= 1 && abs(_row - pc.row) <= 1;
	};

	function claim_cell(_grid, _col, _row, _structure_id) {
	    _grid.occupancy[
	        self.grid_index(_col, _row, _grid)
	    ] = _structure_id;
	}

	function release_cell(_grid, _col, _row) {
	    if (!game.world.in_bounds(_grid, _col, _row))
	        return false;

	    _grid.occupancy[
	        self.grid_index(_col, _row, _grid)
	    ] = undefined;

	    return true;
	}

	function update() {
		if (game.state != FortinState.BUILD) return;

	    if (game.world.is_peeking) {
	        hover_valid = false;
	        preview_valid = false;
	        return;
	    }

		var build_cell = self.world_to_cell(mouse_x, mouse_y);

		hover_col = build_cell.col;
		hover_row = build_cell.row;
		hover_valid = self.in_bounds(hover_col, hover_row);
		
		if (hover_valid) {
		    var cell_pos = self.cell_to_world(hover_col, hover_row);
		    var local_x = mouse_x - cell_pos.x;

		    hover_stair_facing = (local_x < config.cell * 0.5) ? 1 : -1;
		}		
		
		if (pending_delete_active) {
			if (mouse_check_button_pressed(mb_right)) {
				self.cancel_pending_delete();
				preview_valid = false;
				return;
			}

			self.update_pending_delete_cells();

			if (mouse_check_button_released(mb_left)) {
				self.confirm_pending_delete();
			}

			preview_valid = false;
			return;
		}
			
		if (pending_stair_active) {
			self.update_pending_stair_cells();

			if (mouse_check_button_released(mb_left)) {
				self.confirm_pending_stair();
			}

			preview_valid = false;
			return;
		}

		if (pending_tower_active) {
			self.update_pending_tower();

			if (mouse_check_button_released(mb_left)) {
				self.confirm_pending_tower();
			}

			preview_valid = false;
			return;
		}
		
		if (pending_wall_active) {
			self.update_pending_wall_cells();

			if (mouse_check_button_released(mb_left)) {
				self.confirm_pending_wall();
			}

			preview_valid = false;
			return;
		}

		self.update_tower_preview();

		preview_valid = hover_valid
		    && (
		        selected_tool == BuildTool.WALL
		        || selected_tool == BuildTool.STAIR
		        || selected_tool == BuildTool.TOWER
		        || self.is_single_place_tool(selected_tool)
		    );

		if (mouse_check_button_pressed(mb_left) && !game.ui.mouse_consumed) {
			if (selected_tool == BuildTool.WALL && preview_valid) {
				self.begin_pending_wall(hover_col, hover_row);
			}

			if (selected_tool == BuildTool.DELETE && hover_valid) {
				self.begin_pending_delete(hover_col, hover_row);
			}
			
			if (selected_tool == BuildTool.STAIR && preview_valid) {
				self.begin_pending_stair(hover_col, hover_row);
			}

			if (selected_tool == BuildTool.TOWER && preview_valid) {
				self.begin_pending_tower(tower_preview_col, tower_preview_row);
			}

			if (self.is_single_place_tool(selected_tool) && preview_valid) {
				self.place_structure_request(self.get_selected_build_id(), hover_col, hover_row, true);
			}
		}
	};

	function get_view_grid() {
	    return game.world.get_view_grid();
	}

	function  draw_world() {
		view.draw();
	};
	
	function draw_world_overlay() {
		view.draw_overlay();
	}

	function select_tool(_tool) {
		selected_tool = _tool;

		pending_wall_active = false;
		pending_wall_cells = [];

		pending_delete_active = false;
		pending_delete_cells = [];

		preview_valid = false;
		
		pending_stair_active = false;
		pending_stair_cells = [];

		pending_tower_active = false;
		pending_tower_height_segments = 1;
	};

	function get_selected_build_id() {
		if (selected_tool == BuildTool.STAIR) return "SA1";
		if (selected_tool == BuildTool.TOWER) return "TA1";
		if (selected_tool == BuildTool.SOLDIER) return "GS1";
		if (selected_tool == BuildTool.SNIPER) return "GS2";
		if (selected_tool == BuildTool.ENGINEER) return "GS3";
		if (selected_tool == BuildTool.VENOM) return "VA1";
		if (selected_tool == BuildTool.SPIKES) return "PA1";

		return selected_build_id;
	}

	function preview_can_place_selected_tool() {
	    if (!self.near_local_player(hover_col, hover_row)) return false;

	    if (selected_tool == BuildTool.TOWER) {
	        var tower_data = self.make_structure_build_data(1, tower_preview_height_segments);
	        return self.can_place_structure("TA1", tower_preview_col, tower_preview_row, tower_data);
	    }

	    return self.can_place_structure(self.get_selected_build_id(), hover_col, hover_row);
	}

	function begin_pending_wall(_col, _row) {
		if (!self.cell_free(_col, _row)) return false;
		if (!self.near_local_player(_col, _row)) return false;

		pending_wall_active = true;
		pending_wall_col = _col;
		pending_wall_start_row = _row;
		pending_wall_cells = [];

		self.update_pending_wall_cells();

		return true;
	};

	function get_pending_wall_target_cell() {
		var grid_data = self.get_active_grid();

		var raw_col = floor((mouse_x - grid_data.x) / config.cell);
		var raw_row = floor((mouse_y - grid_data.y) / config.cell);

		return {
			col: clamp(raw_col, 0, grid_data.cols - 1),
			row: clamp(raw_row, 0, grid_data.rows - 1),
		};
	};

	function get_pending_wall_direction(_dx, _dy) {
		var sx = sign(_dx);
		var sy = sign(_dy);
		var adx = abs(_dx);
		var ady = abs(_dy);

		if (adx == 0 && ady == 0) {
			return { x: 0, y: 0, length: 0 };
		}

		if (adx >= ady) {
			return { x: sx, y: 0, length: adx };
		}

		return { x: 0, y: sy, length: ady };
	};

	function update_pending_wall_cells() {
		pending_wall_cells = [];

		if (!pending_wall_active) return;

		var target = self.get_pending_wall_target_cell();
		var dx = target.col - pending_wall_col;
		var dy = target.row - pending_wall_start_row;
		var ddirection = self.get_pending_wall_direction(dx, dy);

		for (var i = 0; i <= ddirection.length; i++) {
			var col = pending_wall_col + ddirection.x * i;
			var row = pending_wall_start_row + ddirection.y * i;

			if (!self.in_bounds(col, row)) break;
			if (!self.cell_free(col, row)) break;

			array_push(pending_wall_cells, {
				col: col,
				row: row,
			});
		}
	};

	function confirm_pending_wall() {
		if (!pending_wall_active) return false;

		var cells = pending_wall_cells;

		pending_wall_active = false;
		pending_wall_col = -1;
		pending_wall_start_row = -1;
		pending_wall_cells = [];

		for (var i = 0; i < array_length(cells); i++) {
			var cell = cells[i];
			self.place_wall_request(cell.col, cell.row, false);
		}

		return true;
	};

	function begin_pending_stair(_col, _row) {
		if (!self.cell_free(_col, _row)) return false;
		if (!self.near_local_player(_col, _row)) return false;
		
		pending_stair_facing = hover_stair_facing;
		pending_stair_active = true;
		pending_stair_col = _col;
		pending_stair_row = _row;
		pending_stair_cells = [];

		self.update_pending_stair_cells();

		return true;
	}

	function get_pending_stair_direction(_dx, _dy) {
	var adx = abs(_dx);
	var ady = abs(_dy);

	if (adx == 0 && ady == 0) {
		return {
			x: 0,
			y: 0,
			length: 0,
		};
	}

	var length = max(adx, ady);

	// El mouse decide si vamos hacia arriba o hacia abajo.
	var vertical = (_dy < 0) ? -1 : 1;

	var step_x;
	var step_y;

	if (pending_stair_facing > 0) {
		// ╲
		step_x = vertical;
		step_y = vertical;
	}
	else {
		// ╱
		step_x = -vertical;
		step_y = vertical;
	}

	return {
		x: step_x,
		y: step_y,
		length: length,
	};
}

	function update_pending_stair_cells() {
	pending_stair_cells = [];

	if (!pending_stair_active) return;

	var target = self.get_pending_wall_target_cell();

	var dx = target.col - pending_stair_col;
	var dy = target.row - pending_stair_row;

	var dir = self.get_pending_stair_direction(dx, dy);

	for (var i = 0; i <= dir.length; i++) {

		var col = pending_stair_col + dir.x * i;
		var row = pending_stair_row + dir.y * i;

		if (!self.in_bounds(col, row)) break;
		if (!self.cell_free(col, row)) break;

		array_push(pending_stair_cells, {
			col: col,
			row: row,
		});
	}
}

	function confirm_pending_stair() {
		if (!pending_stair_active) return false;

		var cells = pending_stair_cells;

		pending_stair_active = false;
		pending_stair_col = -1;
		pending_stair_row = -1;
		pending_stair_cells = [];

		for (var i = 0; i < array_length(cells); i++) {
			var cell = cells[i];
			self.place_structure_request(
			    "SA1",
			    cell.col,
			    cell.row,
			    false,
			    self.make_structure_build_data(pending_stair_facing, 1)
			);
		}

		return true;
	}

	function get_tower_anchor_for_cell(_col, _row) {
		var grid_data = self.get_active_grid();

		return {
			col: clamp(_col, 0, grid_data.cols - 2),
			row: clamp(_row, 0, grid_data.rows - 2),
		};
	}

	function update_tower_preview() {
		if (selected_tool != BuildTool.TOWER || !hover_valid) {
			tower_preview_col = -1;
			tower_preview_row = -1;
			tower_preview_height_segments = 1;
			return;
		}

		var anchor = self.get_tower_anchor_for_cell(hover_col, hover_row);
		tower_preview_col = anchor.col;
		tower_preview_row = anchor.row;
		tower_preview_height_segments = 1;
	}

	function begin_pending_tower(_col, _row) {
		var build_data = self.make_structure_build_data(1, 1);
		if (!self.can_place_structure("TA1", _col, _row, build_data)) return false;
		if (!self.near_local_player(hover_col, hover_row)) return false;

		pending_tower_active = true;
		pending_tower_col = _col;
		pending_tower_row = _row;
		pending_tower_height_segments = 1;

		self.update_pending_tower();

		return true;
	}

	function update_pending_tower() {
		if (!pending_tower_active) return;

		var target = self.get_pending_wall_target_cell();
		var target_top_row = min(target.row, pending_tower_row - 1);
		var requested_segments = max(1, ceil((pending_tower_row - target_top_row + 1) / 2));

		pending_tower_height_segments = 1;
		
		for (var segments = 1; segments <= requested_segments; segments++) {
			var build_data = self.make_structure_build_data(1, segments);
			if (!self.can_place_structure("TA1", pending_tower_col, pending_tower_row, build_data)) break;

			pending_tower_height_segments = segments;
		}
		

		
	}

	function confirm_pending_tower() {
		if (!pending_tower_active) return false;

		var col = pending_tower_col;
		var row = pending_tower_row;
		var height_segments = pending_tower_height_segments;

		pending_tower_active = false;
		pending_tower_col = -1;
		pending_tower_row = -1;
		pending_tower_height_segments = 1;

		return self.place_structure_request(
			"TA1",
			col,
			row,
			false,
			self.make_structure_build_data(1, height_segments)
		);
		
	}

	function begin_pending_delete(_col, _row) {
		if (!self.in_bounds(_col, _row)) return false;

		pending_delete_active = true;
		pending_delete_start_col = _col;
		pending_delete_start_row = _row;
		pending_delete_cells = [];

		self.update_pending_delete_cells();

		return true;
	};

	function update_pending_delete_cells() {
		pending_delete_cells = [];

		if (!pending_delete_active) return;

		var target = self.get_pending_wall_target_cell();

		var c1 = min(pending_delete_start_col, target.col);
		var c2 = max(pending_delete_start_col, target.col);
		var r1 = min(pending_delete_start_row, target.row);
		var r2 = max(pending_delete_start_row, target.row);

		for (var col = c1; col <= c2; col++) {
			for (var row = r1; row <= r2; row++) {
				if (!self.in_bounds(col, row)) continue;

				array_push(pending_delete_cells, {
					col: col,
					row: row,
				});
			}
		}
	};

	function cancel_pending_delete() {
		pending_delete_active = false;
		pending_delete_start_col = -1;
		pending_delete_start_row = -1;
		pending_delete_cells = [];

		return true;
	};

	function confirm_pending_delete() {
		if (!pending_delete_active) return false;

		var cells = pending_delete_cells;

		pending_delete_active = false;
		pending_delete_start_col = -1;
		pending_delete_start_row = -1;
		pending_delete_cells = [];

		var structure_ids = [];

		for (var i = 0; i < array_length(cells); i++) {
			var cell = cells[i];
			var structure_id = self.get_cell_structure_id(self.get_active_grid(), cell.col, cell.row);

			if (is_undefined(structure_id)) continue;

			var already_added = false;

			for (var j = 0; j < array_length(structure_ids); j++) {
				if (structure_ids[j] == structure_id) {
					already_added = true;
					break;
				}
			}

			if (!already_added) {
				array_push(structure_ids, structure_id);
			}
		}

		for (var k = 0; k < array_length(structure_ids); k++) {
			global.Game.network.request_delete_structure(structure_ids[k]);
		}

		return true;
	};

	function place_wall_request(_col, _row, _require_near_player = true) {
		return self.place_structure_request(selected_build_id, _col, _row, _require_near_player);
	}
	
	function place_structure_request(_build_id, _col, _row, _require_near_player = true, _build_data = undefined) {
		if (!self.can_place_structure(_build_id, _col, _row, _build_data)) return false;
		if (_require_near_player && !self.near_local_player(_col, _row)) return false;

		return global.Game.network.request_build_structure(_build_id, _col, _row, _build_data);
	}
	
	function place_structure_from_network(_structure_id, _build_id, _col, _row, _owner_id, _build_data = undefined) {
    if (global.Game.structures.has_structure(_structure_id)) return global.Game.structures.get_structure(_structure_id);
    if (!self.can_place_structure(_build_id, _col, _row, _build_data, _owner_id)) return false;

    var structure = global.Game.structures.create_structure(_structure_id, _build_id, _col, _row, _owner_id, _build_data);
    if (!is_struct(structure)) return false;

    self.claim_structure_cells(structure);
    return structure;
};

	function delete_structure_from_network(_structure_id, _player_id) {
		if (!global.Game.structures.can_player_destroy_structure(_structure_id, _player_id)) return false;

		return global.Game.structures.destroy_structure(_structure_id);
	};

	function host_place_structure(_build_id, _col, _row, _owner_id, _build_data = undefined) {

	var structure_def = game.data.get_structure_def(_build_id);
	if (!is_struct(structure_def)) return false;

	var team = game.players.get_player_team(_owner_id);
	if (team != structure_def.allowed_team) return false;

	if (!game.budget.can_afford(team, structure_def.price)) {
		return false;
	}
	
	var structure = self.place_structure_from_network(
		-1,
		_build_id,
		_col,
		_row,
		_owner_id,
		_build_data
	);

	if (!is_struct(structure)) return false;

	game.budget.spend(team, structure_def.price);
	game.network.broadcast_budget();
	game.network.broadcast_structure(structure);

	return true;
}

	function host_delete_structure(_structure_id, _owner_id) {

	var structure = game.structures.get_structure(_structure_id);
	if (!is_struct(structure)) return false;

	var structure_def = game.data.get_structure_def(structure.build_id);
	if (!is_struct(structure_def)) return false;

	var team = game.players.get_player_team(_owner_id);

	if (!self.delete_structure_from_network(_structure_id, _owner_id)) {
		return false;
	}

	game.budget.add(team, structure_def.price);
	game.network.broadcast_budget();
	game.network.broadcast_structure_delete(_structure_id);

	return true;
}

	function destroy() {
		// Vacio por ahora.
	};

	reset();
}
