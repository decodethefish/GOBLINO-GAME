function StructureSystem(_game) constructor {
	game = _game;
	items = [];
	next_structure_id = 0;
	solid_colliders_cache = [];
	active_stairs_cache = [];
	solid_collider_buckets = {};
	active_stair_buckets = {};
	solid_collider_query_id = 0;
	active_stair_query_id = 0;
	solid_colliders_dirty = true;
	net_dirty = [];

	function invalidate_collision_cache() {
		solid_colliders_dirty = true;

		if (variable_struct_exists(game, "paths") && is_struct(game.paths)) {
			game.paths.mark_dirty();
		}
	}

	function reset () {
		for (var i = 0; i < array_length(items); i++) {
			var structure_data = items[i];

			if (!is_struct(structure_data)) continue;
			if (instance_exists(structure_data.inst)) {
				instance_destroy(structure_data.inst);
			}
		}

		items = [];
		next_structure_id = 0;
		self.invalidate_collision_cache();
	};

	function has_structure(_structure_id) {
		if (_structure_id < 0) return false;
		if (_structure_id >= array_length(items)) return false;
		return is_struct(items[_structure_id]);
	};

	function is_troop_structure(_structure) {

		if (!is_struct(_structure)) return false;

		var def = game.data.get_structure_def(_structure.build_id);

		if (!is_struct(def)) return false;

		return def.type == ConstructionType.SOLDIER;

	}

	function update_troop_marker(_structure) {

		if (!instance_exists(_structure.inst)) return;

		var def = game.data.get_structure_def(_structure.build_id);

		var inst = _structure.inst;
		var anim_speed = 0.5;

		inst.image_index += anim_speed;

		var frames = sprite_get_number(def.visual_sprite);

		if (inst.image_index >= frames) {
			inst.image_index -= frames;
		}

	}

	function trap_overlaps(_e, _rect) {
		var body = game.collision.get_entity_rect(_e);
		if (!is_struct(body)) return false;

		return game.collision.rects_overlap(body.x1, body.y1, body.x2, body.y2, _rect.x1, _rect.y1, _rect.x2, _rect.y2);
	}

	function trap_track_entity(_e, _structure, _rect, _trap) {
		if (!variable_struct_exists(_e, "trap_inside")) _e.trap_inside = {};

		var key = string(_structure.structure_id);

		if (self.trap_overlaps(_e, _rect)) {
			_e.trap_inside[$ key] = true;
			return true;
		}

		if (variable_struct_exists(_e.trap_inside, key)) {
			variable_struct_remove(_e.trap_inside, key);

			// SALIÓ de la trampa: aquí se activa el debuff
			if (!is_undefined(_trap.debuff)) game.debuffs.apply(_e, _trap.debuff);
		}

		return false;
	}

	function update_trap(_structure, _def) {
		if (game.state != FortinState.BATTLE) return;

		var rect = self.get_structure_target_rect(_structure);
		if (!is_struct(rect)) return;

		// El timer solo controla el daño por contacto. La detección corre SIEMPRE,
		// si no se perdería la salida mientras la trampa está en cooldown.
		var can_hit = (_structure.trap_timer <= 0);
		if (!can_hit) _structure.trap_timer--;

		var hit = false;

		// Jugador: solo el local (damage_player ya replica por red)
		var p = game.players.get_local_player();
		if (is_struct(p) && p.active && p.alive) {
			if (self.trap_track_entity(p, _structure, rect, _def.trap) && can_hit) {
				game.debuffs.damage(p, _def.trap.damage);
				hit = true;
			}
		}
		
		var troop_count = game.troops.is_authority() ? array_length(game.troops.items) : 0;

		for (var i = 0; i < troop_count; i++) {
			var t = game.troops.items[i];
			if (!is_struct(t)) continue;
			if (!t.active) continue;

			if (self.trap_track_entity(t, _structure, rect, _def.trap) && can_hit) {
				game.debuffs.damage(t, _def.trap.damage);
				hit = true;
			}
		}

		if (hit) _structure.trap_timer = _def.trap.tick;
	}

	function draw_trap_sprite(_structure, _position, _def) {
		var cell = game.config.cell;
		var sc = game.config.trap_visual_scale;
		var spr = _def.visual_sprite;
		var w = sprite_get_width(spr) * sc;
		var h = sprite_get_height(spr) * sc;

		draw_sprite_ext(spr, 0,
			_position.x + (cell - w) * 0.5 + sprite_get_xoffset(spr) * sc,
			_position.y + cell - h + sprite_get_yoffset(spr) * sc,
			sc, sc, 0, c_white, 1);

		if (game.config.debug_show_hitboxes) {
			var r = self.get_structure_target_rect(_structure);
			if (is_struct(r)) {
				draw_set_color(c_red);
				draw_rectangle(r.x1, r.y1, r.x2, r.y2, true);
				draw_set_color(c_white);
			}
		}
	}
		
	function drain_net_dirty() {
		var out = [];
		var seen = {};

		for (var i = 0; i < array_length(net_dirty); i++) {
			var sid = net_dirty[i];
			var key = string(sid);

			if (variable_struct_exists(seen, key)) continue;
			seen[$ key] = true;

			var s = self.get_structure(sid);
			if (!is_struct(s) || !s.active) continue;

			array_push(out, [s.structure_id, s.hp]);
		}

		net_dirty = [];
		return out;
	}
		
	function draw_troop_marker(_structure, _position, _structure_def) {

		draw_sprite_ext(
			_structure_def.visual_sprite,
			floor(_structure.inst.image_index),
			_position.x,
			_position.y,
			0.25,
			0.25,
			0,
			c_white,
			1
		);

	}

	function draw_structure_sprite(_structure, _position, _structure_def) {

		var cell = game.config.cell;
		var spr = _structure_def.visual_sprite;
		
		if (_structure_def.type == ConstructionType.TRAP) {
			self.draw_trap_sprite(_structure, _position, _structure_def);
			return;
		}
		
		if (self.is_stair_structure(_structure)) {
			spr = (self.get_structure_facing(_structure) > 0)
				? spr_obj_stair_left
				: spr_obj_stair_right;
		}
		else if (_structure_def.type == ConstructionType.WALL) {
			spr = self.get_wall_visual_sprite(_structure);
		}

		// Torres: cada segmento ocupa 2 celdas de alto (igual que el preview)
		if (_structure_def.type == ConstructionType.TOWER) {

			var segments = self.get_structure_height_segments(_structure);
			var seg_fit = self.get_structure_fit_scale(spr, _structure_def.size_x * cell, cell * 2);

			for (var i = 0; i < segments; i++) {
				draw_sprite_ext(
					spr, 0,
					_position.x, _position.y - i * cell * 2,
					seg_fit.x, seg_fit.y, 0, c_white, 1
				);
			}

			if (!is_undefined(_structure_def.top_visual_sprite)) {
				// El remate no tiene footprint propio en celdas (es decorativo):
				// usa la MISMA escala del cuerpo, no una caja calculada aparte.
				draw_sprite_ext(
					_structure_def.top_visual_sprite, 0,
					_position.x + _structure_def.top_offset_x * cell,
					_position.y - (segments - 1) * cell * 2 + _structure_def.top_offset_y * cell,
					seg_fit.x, seg_fit.y, 0, c_white, 1
				);
			}

			return;
		}

		// Resto: se ajusta exactamente a su huella (size_x x size_y celdas)
		var fit = self.get_structure_fit_scale(spr, _structure_def.size_x * cell, _structure_def.size_y * cell);

		draw_sprite_ext(
			spr, 0,
			_position.x, _position.y,
			fit.x, fit.y, 0, c_white, 1
		);
	}

	function update() {

		for (var i = 0; i < array_length(items); i++) {

			var structure = items[i];

			if (!is_struct(structure)) continue;
			if (!structure.active) continue;

			if (variable_struct_exists(structure, "health_bar_timer")) {
				structure.health_bar_timer = max(0, structure.health_bar_timer - 1);
			}

			if (!instance_exists(structure.inst)) continue;

			var structure_def = game.data.get_structure_def(structure.build_id);
			
			if (structure_def.type == ConstructionType.TRAP) {
				self.update_trap(structure, structure_def);
				continue;
			}			
			
			if (!self.is_troop_structure(structure)) continue;

			self.update_troop_marker(structure);
		}
	};

	function is_stair_structure(_structure_data) {
		if (!is_struct(_structure_data)) return false;

		var structure_def = game.data.get_structure_def(_structure_data.build_id);
		if (!is_struct(structure_def)) return false;

		return structure_def.type == ConstructionType.LADDER;
	}
		
	function get_wall_stack_neighbor(_structure, _row_offset) {
		var target_row = _structure.row + _row_offset;

		for (var i = 0; i < array_length(items); i++) {
			var s = items[i];

			if (!is_struct(s)) continue;
			if (!s.active) continue;
			if (s.team != _structure.team) continue;
			if (s.col != _structure.col) continue;
			if (s.row != target_row) continue;

			var def = game.data.get_structure_def(s.build_id);
			if (!is_struct(def)) continue;
			if (def.type != ConstructionType.WALL) continue;

			return s;
		}

		return undefined;
	}

	function get_wall_visual_sprite(_structure) {
		// row+1 = celda de abajo (piso), row-1 = celda de arriba
		var has_below = is_struct(self.get_wall_stack_neighbor(_structure, 1));
		var has_above = is_struct(self.get_wall_stack_neighbor(_structure, -1));

		if (!has_below) return spr_obj_wall_1; // base de la pila
		if (!has_above) return spr_obj_wall_3; // remate superior
		return spr_obj_wall_2; // relleno
	}
		
	function get_structure_fit_scale(_sprite, _target_w, _target_h) {
		if (is_undefined(_sprite)) return { x: 1, y: 1 };

		var sw = sprite_get_width(_sprite);
		var sh = sprite_get_height(_sprite);

		if (sw <= 0 || sh <= 0) return { x: 1, y: 1 };

		return { x: _target_w / sw, y: _target_h / sh };
	}		
	
	function is_solid_structure(_structure_data) {
		if (!is_struct(_structure_data)) return false;

		var structure_def = game.data.get_structure_def(_structure_data.build_id);
		if (!is_struct(structure_def)) return false;

		return structure_def.solid;
	}

	function get_structure_facing(_structure_data) {
		if (!is_struct(_structure_data)) return 1;
		if (!variable_struct_exists(_structure_data, "facing")) return 1;

		return _structure_data.facing < 0 ? -1 : 1;
	}

	function get_structure_height_segments(_structure_data) {
		if (!is_struct(_structure_data)) return 1;
		if (!variable_struct_exists(_structure_data, "height_segments")) return 1;

		return max(1, floor(_structure_data.height_segments));
	}

	function get_structure_target_rect(_structure_data) {
		if (!is_struct(_structure_data)) return undefined;

		var solid_rect = self.get_structure_rect(_structure_data);
		if (is_struct(solid_rect)) return solid_rect;

		var structure_def = game.data.get_structure_def(_structure_data.build_id);
		if (!is_struct(structure_def)) return undefined;

		if (structure_def.type == ConstructionType.TRAP && !is_undefined(structure_def.collision_sprite)) {
			var cell = game.config.cell;
			var csp = structure_def.collision_sprite;
			var cw = sprite_get_bbox_right(csp) - sprite_get_bbox_left(csp) + 1;
			var ch = sprite_get_bbox_bottom(csp) - sprite_get_bbox_top(csp) + 1;
			var tgrid = game.world.get_grid_for_team(_structure_data.team);
			var tpos = game.world.cell_to_world(tgrid, _structure_data.col, _structure_data.row);

			return {
				x1: tpos.x + (cell - cw) * 0.5,
				y1: tpos.y + cell - ch,
				x2: tpos.x + (cell + cw) * 0.5,
				y2: tpos.y + cell,
			};
		}

		var grid = game.world.get_grid_for_team(_structure_data.team);
		var min_col = _structure_data.col;
		var max_col = _structure_data.col;
		var min_row = _structure_data.row;
		var max_row = _structure_data.row;

		if (is_array(structure_def.occupied_offsets)
		&& array_length(structure_def.occupied_offsets) > 0) {
			min_col = _structure_data.col + structure_def.occupied_offsets[0].dx;
			max_col = min_col;
			min_row = _structure_data.row + structure_def.occupied_offsets[0].dy;
			max_row = min_row;

			for (var i = 1; i < array_length(structure_def.occupied_offsets); i++) {
				var offset = structure_def.occupied_offsets[i];
				min_col = min(min_col, _structure_data.col + offset.dx);
				max_col = max(max_col, _structure_data.col + offset.dx);
				min_row = min(min_row, _structure_data.row + offset.dy);
				max_row = max(max_row, _structure_data.row + offset.dy);
			}
		}
		else {
			max_col = _structure_data.col + structure_def.size_x - 1;
			max_row = _structure_data.row + structure_def.size_y - 1;
		}

		var pos1 = game.world.cell_to_world(grid, min_col, min_row);
		var pos2 = game.world.cell_to_world(grid, max_col + 1, max_row + 1);

		return {
			x1: pos1.x,
			y1: pos1.y,
			x2: pos2.x,
			y2: pos2.y,
		};
	}

	function draw_structure_health_bar(_structure) {
		if (!is_struct(_structure)) return;
		if (!variable_struct_exists(_structure, "hp")) return;
		if (!variable_struct_exists(_structure, "max_hp")) return;
		if (!variable_struct_exists(_structure, "health_bar_timer")) return;
		if (_structure.health_bar_timer <= 0) return;
		if (_structure.max_hp <= 0) return;

		var rect = self.get_structure_target_rect(_structure);
		if (!is_struct(rect)) return;

		var bar_w = max(28, min(64, rect.x2 - rect.x1));
		var bar_h = 5;
		var bar_x = rect.x1 + ((rect.x2 - rect.x1) - bar_w) * 0.5;
		var bar_y = rect.y1 - 10;
		var pct = clamp(_structure.hp / _structure.max_hp, 0, 1);

		draw_set_color(c_black);
		draw_rectangle(bar_x - 1, bar_y - 1, bar_x + bar_w + 1, bar_y + bar_h + 1, false);
		draw_set_color(c_red);
		draw_rectangle(bar_x, bar_y, bar_x + bar_w, bar_y + bar_h, false);
		draw_set_color(c_lime);
		draw_rectangle(bar_x, bar_y, bar_x + bar_w * pct, bar_y + bar_h, false);
		draw_set_color(c_white);
	}

	function draw_health_bars() {
		for (var i = 0; i < array_length(items); i++) {
			var structure_data = items[i];

			if (!is_struct(structure_data)) continue;
			if (!structure_data.active) continue;

			self.draw_structure_health_bar(structure_data);
		}
	}

	function get_stair_surface_y(_structure_data, _x) {
	if (!self.is_stair_structure(_structure_data)) return undefined;

	var r = self.get_structure_rect(_structure_data);
	if (!is_struct(r)) return undefined;
	if (_x < r.x1 || _x > r.x2) return undefined;

	var width = max(1, r.x2 - r.x1);
	var t = clamp((_x - r.x1) / width, 0, 1);

	var facing = self.get_structure_facing(_structure_data);

	if (facing > 0) {
		// ╲
		return lerp(r.y1, r.y2, t);
	}
	else {
		// ╱
		return lerp(r.y2, r.y1, t);
	}
}
		
	function get_stair_surfaces_at_x(_x) {
	    var surfaces = [];
	    var stairs = self.get_active_stairs_in_rect(_x, 0, _x + 1, 1);

	    for (var i = 0; i < array_length(stairs); i++) {
	        var s = stairs[i];

	        var surface_y = self.get_stair_surface_y(s, _x);
	        if (is_undefined(surface_y)) continue;

	        array_push(surfaces, surface_y);
	    }

	    return surfaces;
	}
	
	function get_structure_rect(_structure_data) {
	var structure_def = game.data.get_structure_def(_structure_data.build_id);
	if (!is_struct(structure_def)) return undefined;
	if (!structure_def.solid) return undefined;

	var grid = game.world.get_grid_for_team(_structure_data.team);
	var pos = game.world.cell_to_world(grid, _structure_data.col, _structure_data.row);

	var col_sprite;

	if (self.is_stair_structure(_structure_data)) {
		var facing = self.get_structure_facing(_structure_data);

		col_sprite = (facing > 0)
			? spr_obj_stair_col_left
			: spr_obj_stair_col_right;
	}
	else {
		col_sprite = structure_def.collision_sprite;
	}

	if (is_undefined(col_sprite)) return undefined;

	return {
		x1: pos.x + sprite_get_bbox_left(col_sprite),
		y1: pos.y + sprite_get_bbox_top(col_sprite),
		x2: pos.x + sprite_get_bbox_right(col_sprite) + 1,
		y2: pos.y + sprite_get_bbox_bottom(col_sprite) + 1,
	};
};

	function get_bucket_key(_col, _row) {
		return string(_col) + "_" + string(_row);
	}

	function add_collider_to_spatial_index(_collider_index, _rect) {
		var cell = game.config.cell;
		var col1 = floor(_rect.x1 / cell);
		var row1 = floor(_rect.y1 / cell);
		var col2 = floor((_rect.x2 - 1) / cell);
		var row2 = floor((_rect.y2 - 1) / cell);

		for (var yy = row1; yy <= row2; yy++) {
			for (var xx = col1; xx <= col2; xx++) {
				var key = self.get_bucket_key(xx, yy);
				var bucket = [];

				if (variable_struct_exists(solid_collider_buckets, key)) {
					bucket = variable_struct_get(solid_collider_buckets, key);
				}

				array_push(bucket, _collider_index);
				variable_struct_set(solid_collider_buckets, key, bucket);
			}
		}
	}

	function add_stair_to_spatial_index(_stair) {
		var rect = self.get_structure_rect(_stair);

		if (!is_struct(rect)) return;

		var cell = game.config.cell;
		var col1 = floor(rect.x1 / cell);
		var col2 = floor((rect.x2 - 1) / cell);

		for (var xx = col1; xx <= col2; xx++) {
			var key = string(xx);
			var bucket = [];

			if (variable_struct_exists(active_stair_buckets, key)) {
				bucket = variable_struct_get(active_stair_buckets, key);
			}

			array_push(bucket, _stair);
			variable_struct_set(active_stair_buckets, key, bucket);
		}
	}

	function get_solid_colliders_in_rect(_x1, _y1, _x2, _y2) {
		if (solid_colliders_dirty) {
			self.get_solid_colliders();
		}

		var result = [];
		var cell = game.config.cell;
		var col1 = floor(_x1 / cell);
		var row1 = floor(_y1 / cell);
		var col2 = floor((_x2 - 1) / cell);
		var row2 = floor((_y2 - 1) / cell);

		solid_collider_query_id += 1;

		for (var yy = row1; yy <= row2; yy++) {
			for (var xx = col1; xx <= col2; xx++) {
				var key = self.get_bucket_key(xx, yy);

				if (!variable_struct_exists(solid_collider_buckets, key)) continue;

				var bucket = variable_struct_get(solid_collider_buckets, key);

				for (var i = 0; i < array_length(bucket); i++) {
					var collider = solid_colliders_cache[bucket[i]];

					if (!is_struct(collider)) continue;
					if (collider.query_id == solid_collider_query_id) continue;

					collider.query_id = solid_collider_query_id;
					array_push(result, collider);
				}
			}
		}

		return result;
	}

	function get_active_stairs_in_rect(_x1, _y1, _x2, _y2) {
		if (solid_colliders_dirty) {
			self.get_solid_colliders();
		}

		var result = [];
		var cell = game.config.cell;
		var col1 = floor(_x1 / cell);
		var col2 = floor((_x2 - 1) / cell);

		active_stair_query_id += 1;

		for (var xx = col1; xx <= col2; xx++) {
			var key = string(xx);

			if (!variable_struct_exists(active_stair_buckets, key)) continue;

			var bucket = variable_struct_get(active_stair_buckets, key);

			for (var i = 0; i < array_length(bucket); i++) {
				var stair = bucket[i];

				if (!is_struct(stair)) continue;
				if (variable_struct_exists(stair, "stair_query_id")
				&& stair.stair_query_id == active_stair_query_id) {
					continue;
				}

				stair.stair_query_id = active_stair_query_id;
				array_push(result, stair);
			}
		}

		return result;
	}

	function get_solid_colliders() {

		if (!solid_colliders_dirty) {
			return solid_colliders_cache;
		}

		var colliders = [];
		var stairs = [];
		solid_collider_buckets = {};
		active_stair_buckets = {};

		// Estructuras sólidas
		for (var i = 0; i < array_length(items); i++) {

			var structure = items[i];

			if (!is_struct(structure)) continue;
			if (!structure.active) continue;
			if (!self.is_solid_structure(structure)) continue;
			if (self.is_stair_structure(structure)) {
				array_push(stairs, structure);
				self.add_stair_to_spatial_index(structure);
				continue;
			}

			var rect = self.get_structure_rect(structure);

			if (!is_struct(rect)) continue;

			var collider = {
				type: "STRUCTURE",
				owner: structure,
				rect: rect,
				query_id: 0
			};

			array_push(colliders, collider);
			self.add_collider_to_spatial_index(array_length(colliders) - 1, rect);
		}

		// Caja fuerte
		var vault = game.world.get_vault();
		if (is_struct(vault) && vault.hp > 0) {

			var grid = game.world.get_grid_for_team(vault.team);
			var pos = game.world.cell_to_world(grid, vault.col, vault.row);

			var vault_collider = {

				type: "VAULT",

				owner: vault,

				rect: {
					x1: pos.x,
					y1: pos.y,
					x2: pos.x + vault.width * game.config.cell,
					y2: pos.y + vault.height * game.config.cell
				},

				query_id: 0
			};

			array_push(colliders, vault_collider);
			self.add_collider_to_spatial_index(array_length(colliders) - 1, vault_collider.rect);

		}

		solid_colliders_cache = colliders;
		active_stairs_cache = stairs;
		solid_colliders_dirty = false;

		return solid_colliders_cache;

	}

	function get_active_stairs() {

		if (solid_colliders_dirty) {
			self.get_solid_colliders();
		}

		return active_stairs_cache;

	}

	function get_active_stairs_near_rect(_x1, _y1, _x2, _y2) {

		return self.get_active_stairs_in_rect(_x1, _y1, _x2, _y2);

	}

	function rect_hits_solid(_x1, _y1, _x2, _y2) {
		var colliders = self.get_solid_colliders_in_rect(_x1, _y1, _x2, _y2);

		for (var i = 0; i < array_length(colliders); i++) {
			var r = colliders[i].rect;
			if (!is_struct(r)) continue;

			if (game.collision.rects_overlap(_x1, _y1, _x2, _y2, r.x1, r.y1, r.x2, r.y2)) {
				return true;
			}
		}
		return false;
	};

	function get_solid_rect_hit(_x1, _y1, _x2, _y2) {
		var colliders = self.get_solid_colliders_in_rect(_x1, _y1, _x2, _y2);

		for (var i = 0; i < array_length(colliders); i++) {
			var r = colliders[i].rect;
			if (!is_struct(r)) continue;

			if (game.collision.rects_overlap(_x1, _y1, _x2, _y2, r.x1, r.y1, r.x2, r.y2)) {
				return r;
			}
		}
		return undefined;
	};

	function draw_world() {

		for (var i = 0; i < array_length(items); i++) {

			var structure_data = items[i];

			if (!is_struct(structure_data)) continue;
			if (!structure_data.active) continue;

			var structure_def = game.data.get_structure_def(structure_data.build_id);

			if (!is_struct(structure_def)) continue;

			var grid = game.world.get_grid_for_team(structure_data.team);
			var raw_pos = game.world.cell_to_world(
				grid,
				structure_data.col,
				structure_data.row
			);

			var pos = game.world.get_anchor_pos(raw_pos, structure_def);

			if (self.is_troop_structure(structure_data)) {

				// Durante la batalla las tropas ya las dibuja obj_troop.
				if (game.state != FortinState.BATTLE) {

					self.draw_troop_marker(
						structure_data,
						pos,
						structure_def
					);

				}

			}
			else {

				self.draw_structure_sprite(
					structure_data,
					pos,
					structure_def
				);

			}

		}

	}

	function get_structure(_structure_id) {
		if (_structure_id < 0) return undefined;
		if (_structure_id >= array_length(items)) return undefined;

		return items[_structure_id];
	};

	function get_structure_at_cell(_col, _row) {
		for (var i = 0; i < array_length(items); i++) {
			var structure_data = items[i];

			if (!is_struct(structure_data)) continue;
			if (!structure_data.active) continue;
			if (structure_data.col != _col) continue;
			if (structure_data.row != _row) continue;

			return structure_data;
		}

		return undefined;
	};

	function can_player_destroy_structure(_structure_id, _player_id) {
		var structure_data = self.get_structure(_structure_id);

		if (!is_struct(structure_data)) return false;
		if (!structure_data.active) return false;

		return structure_data.owner_id == _player_id;
	};

	function destroy_structure(_structure_id) {
		var structure_data = self.get_structure(_structure_id);

		if (!is_struct(structure_data)) return false;
		if (!structure_data.active) return false;

		structure_data.active = false;

		if (instance_exists(structure_data.inst)) {
			instance_destroy(structure_data.inst);
		}

		game.build.release_structure_cells(structure_data);
		items[_structure_id] = undefined;
		self.invalidate_collision_cache();

		return true;
	};

	function damage_structure(_structure_id, _amount) {
		var structure_data = self.get_structure(_structure_id);

		if (!is_struct(structure_data)) return false;
		if (!structure_data.active) return false;
		if (!variable_struct_exists(structure_data, "hp")) return false;

		var is_host_net = game.network.is_connected && game.network.is_host;

		// Cliente: solo avisa. El host aplica el daño.
		if (game.network.is_connected && !game.network.is_host) {
			game.network.send_to_host({
				msg: FortinNetMsg.DAMAGE_STRUCTURE,
				structure_id: _structure_id,
			});
			return true;
		}

		structure_data.hp = max(0, structure_data.hp - _amount);
		structure_data.health_bar_timer = room_speed * 2;

		if (structure_data.hp <= 0) {
			var destroyed = self.destroy_structure(_structure_id);

			if (destroyed && is_host_net) game.network.broadcast_structure_delete(_structure_id);

			return destroyed;
		}

		if (is_host_net) array_push(net_dirty, _structure_id);

		return true;
	}

	function create_structure(_structure_id, _build_id, _col, _row, _owner_id, _build_data = undefined) {
		var structure_def = game.data.get_structure_def(_build_id);
		if (!is_struct(structure_def)) return undefined;

		var structure_id = _structure_id;

		if (structure_id < 0) {
			structure_id = next_structure_id;
			next_structure_id += 1;
		}
		else {
			next_structure_id = max(next_structure_id, structure_id + 1);
		}

		if (self.has_structure(structure_id)) return items[structure_id];

		var team = game.players.get_player_team(_owner_id);
		var grid = game.world.get_grid_for_team(team);
		var raw_pos = game.world.cell_to_world(grid, _col, _row);
		var pos = game.world.get_anchor_pos(raw_pos, structure_def);
		var inst = instance_create_layer(pos.x, pos.y, "Instances", obj_structure);

		inst.visible = false;
		inst.structure_id = structure_id;
		inst.structure_build_id = _build_id;
		inst.owner_id = _owner_id;
		inst.grid_col = _col;
		inst.grid_row = _row;
		inst.sprite_index = structure_def.visual_sprite;
		inst.image_speed = 0;
		inst.image_index = 0;

		var facing = 1;
		var height_segments = 1;
		
		if (is_struct(_build_data)) {
			if (variable_struct_exists(_build_data, "facing")) {
				facing = _build_data.facing < 0 ? -1 : 1;
			}

			if (variable_struct_exists(_build_data, "height_segments")) {
				height_segments = max(1, floor(_build_data.height_segments));
			}
		}
		
		
		var old_len = array_length(items);

		if (structure_id >= old_len) {
			array_resize(items, structure_id + 1);

			for (var i = old_len; i < structure_id; i++) {
				items[i] = undefined;
			}
		}

		var structure_data = {
			structure_id: structure_id,
			build_id: _build_id,
			team: team,
			col: _col,
			row: _row,
			owner_id: _owner_id,
			facing: facing,
			height_segments: height_segments,
			hp: structure_def.hp,
			max_hp: structure_def.hp,
			health_bar_timer: 0,
			trap_timer: 0,
			active: true,
			inst: inst,
		};

		items[structure_id] = structure_data;
		self.invalidate_collision_cache();

		return structure_data;
	};

	function destroy() {
		self.reset();
	};

}
