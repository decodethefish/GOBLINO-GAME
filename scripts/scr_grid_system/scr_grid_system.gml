function BuildGridView(_build) constructor {
	build = _build;
	game = build.game;
	config = game.config;

	function draw_rect_outline(_x1, _y1, _x2, _y2, _width) {
		draw_line_width(_x1, _y1, _x2, _y1, _width);
		draw_line_width(_x2, _y1, _x2, _y2, _width);
		draw_line_width(_x2, _y2, _x1, _y2, _width);
		draw_line_width(_x1, _y2, _x1, _y1, _width);
	};

	function draw_background() {
		draw_clear(config.color_background);
	};

	function draw_grid() {
		var grid = build.get_view_grid();
		var left = grid.x;
		var top = grid.y;
		var right = grid.x + grid.cols * config.cell;
		var bottom = grid.y + grid.rows * config.cell;
	
		draw_set_alpha(1);
		draw_set_color(config.color_grid);

		for (var col = 0; col <= grid.cols; col++) {
			var xx = left + col * config.cell;
			draw_line_width(xx, top, xx, bottom, config.grid_line_width);
		}

		for (var row = 0; row <= grid.rows; row++) {
			var yy = top + row * config.cell;
			draw_line_width(left, yy, right, yy, config.grid_line_width);
		}
	};

	function draw_vault() {
		if (game.state == FortinState.BUILD) {
			var local_team = game.players.get_player_team(game.config.local_player_id);
			if (local_team != FortinTeam.DEFENDERS) return;
		}
		else if (game.state != FortinState.BATTLE) {
			return;
		}

		var vault = game.world.get_vault();
		var pos = game.world.get_vault_world_position();
		var target_w = vault.width * config.cell;
		var target_h = vault.height * config.cell;
		var scale_x = target_w / sprite_get_width(spr_obj_vault);
		var scale_y = target_h / sprite_get_height(spr_obj_vault);

		draw_set_alpha(1);
		draw_set_color(c_white);
		draw_sprite_ext(
			spr_obj_vault,
			0,
			pos.x,
			pos.y,
			scale_x,
			scale_y,
			0,
			c_white,
			1
		);
	};

	function draw_preview() {
	    if (game.state != FortinState.BUILD) return;

	    if (build.selected_tool != BuildTool.WALL
	        && build.selected_tool != BuildTool.STAIR
	        && build.selected_tool != BuildTool.TOWER
	        && build.selected_tool != BuildTool.SOLDIER
	        && build.selected_tool != BuildTool.SNIPER
	        && build.selected_tool != BuildTool.ENGINEER
	        && build.selected_tool != BuildTool.VENOM
	        && build.selected_tool != BuildTool.SPIKES) return;

	    if (!build.hover_valid) return;

	    var preview_build_id = build.get_selected_build_id();
	    var structure_def = game.data.get_structure_def(preview_build_id);

	    if (!is_struct(structure_def)) return;

	    var placement_valid = build.preview_can_place_selected_tool();
	    var in_range = build.near_local_player(build.hover_col, build.hover_row);

	    var preview_col = build.hover_col;
	    var preview_row = build.hover_row;
	    var build_data = undefined;

	    if (build.selected_tool == BuildTool.STAIR) {
	        build_data = build.make_structure_build_data(build.hover_stair_facing, 1);
	    }

	    if (build.selected_tool == BuildTool.TOWER) {
	        preview_col = build.tower_preview_col;
	        preview_row = build.tower_preview_row;
	        build_data = build.make_structure_build_data(1, build.tower_preview_height_segments);
	    }

	    var pos = build.cell_to_world(preview_col, preview_row);

	    draw_set_alpha(in_range ? 0.80 : 0.45);

	    if (placement_valid) {
	        draw_set_color(c_white);
	    } else {
	        draw_set_color(c_red);
	    }

	    self.draw_structure_preview(structure_def, pos.x, pos.y, build_data);

	    draw_set_alpha(1);
	    draw_set_color(c_white);
	}
		
	function draw_structure_preview(_structure_def, _x, _y, _build_data = undefined) {
		var height_segments = build.get_build_data_height_segments(_build_data);
		var facing = 1;
		var alpha = draw_get_alpha();

		if (is_struct(_build_data) && variable_struct_exists(_build_data, "facing")) {
			facing = _build_data.facing;
		}

		var body_scale = { x: 1, y: 1 };

		if (_structure_def.type == ConstructionType.TOWER) {

			body_scale = game.structures.get_structure_fit_scale(
				_structure_def.visual_sprite,
				_structure_def.size_x * config.cell,
				config.cell * 2
			);

			for (var segment = 0; segment < height_segments; segment++) {
				draw_sprite_ext(
					_structure_def.visual_sprite, 0,
					_x, _y - segment * config.cell * 2,
					body_scale.x, body_scale.y, 0, c_white, alpha
				);
			}
		}
		else if (_structure_def.type == ConstructionType.LADDER) {

			var spr = (facing > 0)
				? spr_obj_stair_left
				: spr_obj_stair_right;

			var fit = game.structures.get_structure_fit_scale(
				spr,
				_structure_def.size_x * config.cell,
				_structure_def.size_y * config.cell
			);

			draw_sprite_ext(spr, 0, _x, _y, fit.x, fit.y, 0, c_white, alpha);
		}
		else {

			var spr = is_undefined(_structure_def.preview_sprite)
				? _structure_def.visual_sprite
				: _structure_def.preview_sprite;

			if (_structure_def.type == ConstructionType.TRAP) {
				game.structures.draw_trap_sprite(undefined, { x: _x, y: _y }, _structure_def, alpha);
			}
			else if (_structure_def.type == ConstructionType.SOLDIER) {
				draw_sprite_ext(spr, 0, _x, _y, 0.25, 0.25, 0, c_white, alpha);
			}
			else {
				var fit = game.structures.get_structure_fit_scale(
					spr,
					_structure_def.size_x * config.cell,
					_structure_def.size_y * config.cell
				);

				draw_sprite_ext(spr, 0, _x, _y, fit.x, fit.y, 0, c_white, alpha);
			}
		}

		if (!is_undefined(_structure_def.top_visual_sprite)) {
			draw_sprite_ext(
				_structure_def.top_visual_sprite, 0,
				_x + _structure_def.top_offset_x * config.cell,
				_y + (-height_segments * 2 + 1) * config.cell,
				body_scale.x, body_scale.y, 0, c_white, alpha
			);
		}
	}
		
	function draw_pending_wall() {
		if (!build.pending_wall_active) return;
		if (build.selected_tool != BuildTool.WALL) return;

		var structure_def = game.data.get_structure_def(build.selected_build_id);
		if (!is_struct(structure_def)) return;

		var blink = 0.20 + 0.65 * ((sin(current_time / 120) + 1) * 0.5);
		var fit = game.structures.get_structure_fit_scale(
			structure_def.visual_sprite,
			structure_def.size_x * config.cell,
			structure_def.size_y * config.cell
		);

		for (var i = 0; i < array_length(build.pending_wall_cells); i++) {
			var cell = build.pending_wall_cells[i];
			var pos = build.cell_to_world(cell.col, cell.row);
			draw_sprite_ext(structure_def.visual_sprite, 0, pos.x, pos.y, fit.x, fit.y, 0, c_white, blink);
		}
	};
		
	function draw_pending_stair() {
		if (!build.pending_stair_active) return;
		if (build.selected_tool != BuildTool.STAIR) return;

		var structure_def = game.data.get_structure_def(build.selected_build_id);
		if (!is_struct(structure_def)) return;

		var blink = 0.20 + 0.65 * ((sin(current_time / 120) + 1) * 0.5);

		var spr = (build.pending_stair_facing > 0)
			? spr_obj_stair_left
			: spr_obj_stair_right;

		var fit = game.structures.get_structure_fit_scale(
			spr,
			structure_def.size_x * config.cell,
			structure_def.size_y * config.cell
		);

		for (var i = 0; i < array_length(build.pending_stair_cells); i++) {
			var cell = build.pending_stair_cells[i];
			var pos = build.cell_to_world(cell.col, cell.row);

			draw_sprite_ext(spr, 0, pos.x, pos.y, fit.x, fit.y, 0, c_white, blink);
		}
	}

	function draw_pending_tower() {
		if (!build.pending_tower_active) return;
		if (build.selected_tool != BuildTool.TOWER) return;

		var structure_def = game.data.get_structure_def("TA1");
		if (!is_struct(structure_def)) return;

		var blink = 0.20 + 0.65 * ((sin(current_time / 120) + 1) * 0.5);
		var pos = build.cell_to_world(build.pending_tower_col, build.pending_tower_row);
		var build_data = build.make_structure_build_data(1, build.pending_tower_height_segments);

		draw_set_alpha(blink);
		draw_set_color(c_white);
		self.draw_structure_preview(structure_def, pos.x, pos.y, build_data);

		draw_set_alpha(1);
	}

	function draw_pending_delete() {
		if (!build.pending_delete_active) return;
		if (build.selected_tool != BuildTool.DELETE) return;

		for (var i = 0; i < array_length(build.pending_delete_cells); i++) {
			var cell = build.pending_delete_cells[i];
			var pos = build.cell_to_world(cell.col, cell.row);

			draw_set_alpha(0.38);
			draw_set_color(c_red);
			draw_rectangle(pos.x, pos.y, pos.x + config.cell, pos.y + config.cell, false);

			draw_set_alpha(0.85);
			draw_set_color(c_red);
			self.draw_rect_outline(pos.x, pos.y, pos.x + config.cell, pos.y + config.cell, 3);
		}

		draw_set_alpha(1);
		draw_set_color(c_white);
	}

	function draw_player_range() {
		if (game.state != FortinState.BUILD) return;

		if (build.selected_tool != BuildTool.WALL
			&& build.selected_tool != BuildTool.STAIR
			&& build.selected_tool != BuildTool.TOWER
			&& build.selected_tool != BuildTool.SOLDIER
			&& build.selected_tool != BuildTool.SNIPER
			&& build.selected_tool != BuildTool.ENGINEER
			&& build.selected_tool != BuildTool.VENOM
			&& build.selected_tool != BuildTool.SPIKES) return;

		var p = game.players.get_local_player();
		if (is_undefined(p)) return;

		var pc = game.world.player_build_cell(p);

		draw_set_alpha(0.18);
		draw_set_color(c_white);

		for (var col = pc.col - 1; col <= pc.col + 1; col++) {
			for (var row = pc.row - 1; row <= pc.row + 1; row++) {
				if (!build.in_bounds(col, row)) continue;

				var pos = build.cell_to_world(col, row);
				draw_rectangle(pos.x, pos.y, pos.x + config.cell, pos.y + config.cell, false);
			}
		}

		draw_set_alpha(1);
		draw_set_color(c_white);
	}

	function draw() {
		self.draw_background();
		self.draw_grid();
		self.draw_vault();
		self.draw_player_range();
		self.draw_preview();
		self.draw_pending_wall();
		self.draw_pending_stair();
		self.draw_pending_tower();

		draw_set_alpha(1);
		draw_set_color(c_white);
	}
		
	function draw_invalid_cells() {
		if (game.state != FortinState.BUILD) return;
	    if (build.selected_tool == BuildTool.NONE) return;

	    var grid = build.get_active_grid();

	    draw_set_alpha(0.10);
	    draw_set_color(c_red);

	    for (var row = 0; row < grid.rows; row++) {
	        for (var col = 0; col < grid.cols; col++) {

	            if (!build.can_place_structure(
	                build.get_selected_build_id(),
	                col,
	                row
	            )) {
	                var pos = build.cell_to_world(col, row);

	                draw_rectangle(
	                    pos.x,
	                    pos.y,
	                    pos.x + config.cell,
	                    pos.y + config.cell,
	                    false
	                );
	            }
	        }
	    }

	    draw_set_alpha(1);
	    draw_set_color(c_white);
	}
	
	function draw_overlay() {
		self.draw_invalid_cells();
		self.draw_pending_delete();

		draw_set_alpha(1);
		draw_set_color(c_white);
	}
}
