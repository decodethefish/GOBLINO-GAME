function CollisionSystem(_game) constructor {

	game = _game;

	function get_solid_colliders() {

		return game.structures.get_solid_colliders();

	}

	function get_solid_colliders_in_rect(_x1, _y1, _x2, _y2) {

		return game.structures.get_solid_colliders_in_rect(
			_x1,
			_y1,
			_x2,
			_y2
		);

	}

	function get_active_stairs() {

		return game.structures.get_active_stairs();

	}

	function get_active_stairs_near_rect(_x1, _y1, _x2, _y2) {

		return game.structures.get_active_stairs_near_rect(
			_x1,
			_y1,
			_x2,
			_y2
		);

	}

	function get_structure_rect(_structure) {

		if (!is_struct(_structure))
			return undefined;

		var def = game.data.get_structure_def(_structure.build_id);

		if (!is_struct(def))
			return undefined;

		if (!def.solid)
			return undefined;

		var grid = game.world.get_grid_for_team(_structure.team);

		var raw = game.world.cell_to_world(
			grid,
			_structure.col,
			_structure.row
		);

		var pos = game.world.get_anchor_pos(raw, def);

		var sprite;

		if (self.is_stair_structure(_structure)) {

			sprite = (game.structures.get_structure_facing(_structure) > 0)
				? spr_obj_stair_col_left
				: spr_obj_stair_col_right;

		}
		else {

			sprite = def.collision_sprite;

		}

		var entity = {

			x: pos.x,
			y: pos.y,
			collision_sprite: sprite

		};

		return self.get_entity_rect(entity);

	}

	function get_entity_rect(_entity) {

		if (!is_struct(_entity))
			return undefined;

		if (!variable_struct_exists(_entity, "collision_sprite"))
			return undefined;

		return self.get_sprite_rect(
			_entity.collision_sprite,
			_entity.x,
			_entity.y
		);

	}

	function entity_on_ground(_entity) {

	    var grid = game.world.get_grid_for_team(_entity.team);
	    var floor_y = game.world.get_floor_y(grid);

	    if (_entity.y >= floor_y)
	        return true;

	    if (!is_undefined(self.get_stair_support_y(_entity, 4)))
	        return true;

	    var body = self.get_entity_rect(_entity);
		var ground_probe = 3;

		var colliders = self.get_solid_colliders_in_rect(
			body.x1,
			body.y2 - 1,
			body.x2,
			body.y2 + ground_probe
		);

		for (var i = 0; i < array_length(colliders); i++) {

			var r = colliders[i].rect;

			var top_is_under_feet =
				r.y1 >= body.y2 - 1 &&
				r.y1 <= body.y2 + ground_probe;

			if (!top_is_under_feet)
				continue;

			var horizontal_overlap =
				body.x1 < r.x2 &&
				body.x2 > r.x1;

			if (horizontal_overlap)
				return true;
		}

		return false;

	}

	function get_stair_contact_y(_entity, _tolerance) {

		var body = self.get_entity_rect(_entity);

		var probe_xs = [
			body.x1,
			_entity.x,
			body.x2 - 1
		];

		var best_y = undefined;

		for (var i = 0; i < array_length(probe_xs); i++) {

			var surfaces = self.get_stair_surfaces_at_x(probe_xs[i]);

			for (var j = 0; j < array_length(surfaces); j++) {

				var surface_y = surfaces[j];
				var delta = _entity.y - surface_y;

				if (delta > _tolerance || delta < -_tolerance)
					continue;

				if (is_undefined(best_y) || surface_y < best_y)
					best_y = surface_y;
			}
		}

		return best_y;
	}
	
	function get_stair_support_y(_entity, _tolerance) {

		var body = self.get_entity_rect(_entity);

		var probe_xs = [
			body.x1,
			_entity.x,
			body.x2 - 1
		];

		var best_y = undefined;

		for (var i = 0; i < array_length(probe_xs); i++) {

			var surfaces = self.get_stair_surfaces_at_x(probe_xs[i]);

			for (var j = 0; j < array_length(surfaces); j++) {

				var surface_y = surfaces[j];
				var delta = _entity.y - surface_y;

				if (delta < 0 || delta > _tolerance)
					continue;

				if (is_undefined(best_y) || surface_y < best_y)
					best_y = surface_y;
			}
		}


		return best_y;
	}

	function resolve_stair_contact(_entity, _tolerance) {

		var surface_y = self.get_stair_contact_y(_entity, _tolerance);

		if (is_undefined(surface_y))
			return false;

		var candidate = {

			x: _entity.x,
			y: surface_y,
			collision_sprite: _entity.collision_sprite

		};

		var rect = self.get_entity_rect(candidate);

		if (self.rect_hits_solid(
			rect.x1,
			rect.y1,
			rect.x2,
			rect.y2
		)) {
			return false;
		}

		_entity.y = surface_y;
		_entity.vsp = 0;
		_entity.grounded = true;

		return true;
	}

	function get_stair_landing_y(_entity, _previous_y, _tolerance) {

		var body = self.get_entity_rect(_entity);

		var probe_xs = [
			body.x1,
			_entity.x,
			body.x2 - 1
		];

		var best_y = undefined;

		for (var i = 0; i < array_length(probe_xs); i++) {

			var surfaces = self.get_stair_surfaces_at_x(probe_xs[i]);

			for (var j = 0; j < array_length(surfaces); j++) {

				var surface_y = surfaces[j];

				if (_previous_y > surface_y)
					continue;

				if (_entity.y < surface_y)
					continue;

				var delta = _entity.y - surface_y;

				if (delta > _tolerance)
					continue;

				if (is_undefined(best_y) || surface_y < best_y)
					best_y = surface_y;
			}
		}

		return best_y;

	}

	function resolve_stair_landing(_entity, _previous_y, _tolerance) {

		var surface_y = self.get_stair_landing_y(
			_entity,
			_previous_y,
			_tolerance
		);

		if (is_undefined(surface_y))
			return false;

		var rect = self.get_entity_rect({
			x: _entity.x,
			y: surface_y,
			collision_sprite: _entity.collision_sprite
		});

		if (self.rect_hits_solid(
			rect.x1,
			rect.y1,
			rect.x2,
			rect.y2
		)) {
			return false;
		}

		_entity.y = surface_y;
		_entity.vsp = 0;
		_entity.grounded = true;

		return true;

	}

	function stair_side_blocks_entity(_entity, _structure_data, _direction) {

		var r = self.get_structure_rect(_structure_data);

		if (!is_struct(r))
			return false;

		var side_x = (_direction > 0)
			? r.x1
			: r.x2;

		var surface_y = self.get_stair_surface_y(
			_structure_data,
			side_x
		);

		if (is_undefined(surface_y))
			return false;

		return _entity.y > surface_y + 4;

	}

	function get_sprite_rect(_sprite, _x, _y) {

		if (is_undefined(_sprite))
			return undefined;

		var xoff = sprite_get_xoffset(_sprite);
		var yoff = sprite_get_yoffset(_sprite);

		return {

			x1: _x + sprite_get_bbox_left(_sprite) - xoff,
			y1: _y + sprite_get_bbox_top(_sprite) - yoff,
			x2: _x + sprite_get_bbox_right(_sprite) - xoff + 1,
			y2: _y + sprite_get_bbox_bottom(_sprite) - yoff + 1,

		};

	}

	function rect_hits_solid(_x1, _y1, _x2, _y2) {

		return game.structures.rect_hits_solid(
			_x1,
			_y1,
			_x2,
			_y2
		);

	}

	function get_stair_surface_y(_structure, _world_x) {

		return game.structures.get_stair_surface_y(
			_structure,
			_world_x
		);

	}

	function get_stair_surfaces_at_x(_world_x) {

		return game.structures.get_stair_surfaces_at_x(
			_world_x
		);

	}
		
	function is_stair_structure(_structure) {

		return game.structures.is_stair_structure(
			_structure
		);

	}

	function try_step_up_entity(_entity, _target_x) {

		if (!_entity.grounded) return false;

		var target = self.get_entity_rect({
			x: _target_x,
			y: _entity.y,
			collision_sprite: _entity.collision_sprite
		});

		var best_y = undefined;
		var max_step_up = 18;
		var colliders = self.get_solid_colliders_in_rect(
			target.x1,
			target.y1,
			target.x2,
			target.y2
		);

		for (var i = 0; i < array_length(colliders); i++) {

			var r = colliders[i].rect;
			if (!is_struct(r)) continue;

			var overlaps =
				target.x1 < r.x2 &&
				target.x2 > r.x1 &&
				target.y1 < r.y2 &&
				target.y2 > r.y1;

			if (!overlaps) continue;

			var step_amount = _entity.y - r.y1;

			if (step_amount < -2 || step_amount > max_step_up)
				continue;

			if (is_undefined(best_y) || r.y1 < best_y)
				best_y = r.y1;
		}

		if (is_undefined(best_y))
			return false;

		var candidate_rect = self.get_entity_rect({
			x: _target_x,
			y: best_y,
			collision_sprite: _entity.collision_sprite
	});

	if (self.rect_hits_solid(
		candidate_rect.x1,
		candidate_rect.y1,
		candidate_rect.x2,
		candidate_rect.y2
	)) {
		return false;
	}

	_entity.x = _target_x;
	_entity.y = best_y;
	_entity.vsp = 0;
	_entity.grounded = true;

	return true;
}

	function move_entity_x(_entity, _amount) {

		if (_amount == 0) return;

		var start = self.get_entity_rect(_entity);

		var target_x = _entity.x + _amount;

		var target = self.get_entity_rect({
			x: target_x,
			y: _entity.y,
			collision_sprite: _entity.collision_sprite
		});

		var colliders = self.get_solid_colliders_in_rect(
			min(start.x1, target.x1),
			start.y1,
			max(start.x2, target.x2),
			start.y2
		);

		if (_amount > 0) {

			var hit_x = undefined;
			var hit_is_stair_side = false;

			for (var i = 0; i < array_length(colliders); i++) {

				var r = colliders[i].rect;

				var vertical_overlap =
					start.y1 < r.y2 &&
					start.y2 > r.y1;

				var in_path =
					r.x1 >= start.x2 &&
					r.x1 <= target.x2;

				if (!vertical_overlap || !in_path)
					continue;

				if (is_undefined(hit_x) || r.x1 < hit_x) {
					hit_x = r.x1;
					hit_is_stair_side = false;
				}
			}

			var stairs_right = self.get_active_stairs_near_rect(
				min(start.x1, target.x1),
				start.y1,
				max(start.x2, target.x2),
				start.y2
			);

			for (var i = 0; i < array_length(stairs_right); i++) {

				var s = stairs_right[i];

				if (!self.stair_side_blocks_entity(_entity, s, 1)) continue;

				var r = self.get_structure_rect(s);

				if (!is_struct(r)) continue;

				var vertical_overlap =
					start.y1 < r.y2 &&
					start.y2 > r.y1;

				var in_path =
					r.x1 >= start.x2 &&
					r.x1 <= target.x2;

				if (!vertical_overlap || !in_path)
					continue;

				if (is_undefined(hit_x) || r.x1 < hit_x) {
					hit_x = r.x1;
					hit_is_stair_side = true;
				}
			}

			if (!is_undefined(hit_x)) {

				if (!hit_is_stair_side &&
					self.try_step_up_entity(_entity, target_x))
					return;

				var right_offset = start.x2 - _entity.x;

				_entity.x = hit_x - right_offset;
				_entity.hsp = 0;

				return;
			}

		}
		else {

			var hit_x = undefined;
			var hit_is_stair_side = false;

			for (var i = 0; i < array_length(colliders); i++) {

				var r = colliders[i].rect;

				var vertical_overlap =
					start.y1 < r.y2 &&
					start.y2 > r.y1;

				var in_path =
					r.x2 <= start.x1 &&
					r.x2 >= target.x1;

				if (!vertical_overlap || !in_path)
					continue;

				if (is_undefined(hit_x) || r.x2 > hit_x) {
					hit_x = r.x2;
					hit_is_stair_side = false;
				}
			}

			var stairs_left = self.get_active_stairs_near_rect(
				min(start.x1, target.x1),
				start.y1,
				max(start.x2, target.x2),
				start.y2
			);

			for (var i = 0; i < array_length(stairs_left); i++) {

				var s = stairs_left[i];

				if (!self.stair_side_blocks_entity(_entity, s, -1)) continue;

				var r = self.get_structure_rect(s);

				if (!is_struct(r)) continue;

				var vertical_overlap =
					start.y1 < r.y2 &&
					start.y2 > r.y1;

				var in_path =
					r.x2 <= start.x1 &&
					r.x2 >= target.x1;

				if (!vertical_overlap || !in_path)
					continue;

				if (is_undefined(hit_x) || r.x2 > hit_x) {
					hit_x = r.x2;
					hit_is_stair_side = true;
				}
			}

			if (!is_undefined(hit_x)) {

				if (!hit_is_stair_side &&
					self.try_step_up_entity(_entity, target_x))
					return;

				var left_offset = start.x1 - _entity.x;

				_entity.x = hit_x - left_offset;
				_entity.hsp = 0;

				return;
			}

		}

		_entity.x = target_x;

	}

	function move_entity_y(_entity, _amount) {
		if (_amount == 0) return;

		var start = self.get_entity_rect(_entity);
		var target_y = _entity.y + _amount;
		var target = self.get_entity_rect({
			x: _entity.x,
			y: target_y,
			collision_sprite: _entity.collision_sprite
		});
		var colliders = self.get_solid_colliders_in_rect(
			start.x1,
			min(start.y1, target.y1),
			start.x2,
			max(start.y2, target.y2)
		);

		if (_amount > 0) {
			var hit_y = undefined;

			for (var i = 0; i < array_length(colliders); i++) {

				var r = colliders[i].rect;

				var horizontal_overlap =
					start.x1 < r.x2 &&
					start.x2 > r.x1;

				var in_path =
					r.y1 >= start.y2 &&
					r.y1 <= target.y2;

				if (!horizontal_overlap || !in_path)
					continue;

				if (is_undefined(hit_y) || r.y1 < hit_y)
					hit_y = r.y1;
			}

			if (!is_undefined(hit_y)) {

				var bottom_offset = start.y2 - _entity.y;

				_entity.y = hit_y - bottom_offset;
				_entity.vsp = 0;
				_entity.grounded = true;

				return;
			}

		}
		else {

			var hit_y = undefined;

			// Colisión con sólidos
			for (var i = 0; i < array_length(colliders); i++) {

				var r = colliders[i].rect;

				var horizontal_overlap =
					start.x1 < r.x2 &&
					start.x2 > r.x1;

				var in_path =
					r.y2 <= start.y1 &&
					r.y2 >= target.y1;

				if (!horizontal_overlap || !in_path)
					continue;

				if (is_undefined(hit_y) || r.y2 > hit_y)
					hit_y = r.y2;
			}

			// Colisión con la parte inferior de las escaleras
			var stairs_up = self.get_active_stairs_near_rect(
				start.x1,
				min(start.y1, target.y1),
				start.x2,
				max(start.y2, target.y2)
			);

			for (var i = 0; i < array_length(stairs_up); i++) {

				var s = stairs_up[i];

				var r = self.get_structure_rect(s);

				if (!is_struct(r)) continue;
				
				var horizontal_overlap =
					start.x1 < r.x2 &&
					start.x2 > r.x1;
				var in_path =
					r.y2 <= start.y1 &&
					r.y2 >= target.y1;

				if (!horizontal_overlap || !in_path)
					continue;

				if (is_undefined(hit_y) || r.y2 > hit_y)
					hit_y = r.y2;
			}
			
			if (!is_undefined(hit_y)) {

				var top_offset = start.y1 - _entity.y;

				_entity.y = hit_y - top_offset;
				_entity.vsp = 0;

				return;
			}
		}
		_entity.y = target_y;
	}
		
	function rects_overlap(_x1, _y1, _x2, _y2, _ox1, _oy1, _ox2, _oy2) {
		return _x1 < _ox2 && _x2 > _ox1 && _y1 < _oy2 && _y2 > _oy1;
	}
}
