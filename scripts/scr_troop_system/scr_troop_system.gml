function TroopSystem(_game) constructor {

	game = _game;

	items = [];
	
	by_sid = {};
	snapshot_timer = 0;
	last_vault_hp = -2;
	
	function reset() {

		items = [];
		by_sid = {};
		snapshot_timer = 0;
		last_vault_hp = -2;
		
	}

	function create_troop_from_structure(_structure) {

		var structure_def = game.data.get_structure_def(_structure.build_id);

		if (!is_struct(structure_def))
			return undefined;

		var troop_def = game.data.get_unit_def(structure_def.unit_id);

		if (!is_struct(troop_def))
			return undefined;

		var grid = game.world.get_grid_for_team(_structure.team);

		var raw_pos = game.world.cell_to_world(
			grid,
			_structure.col,
			_structure.row
		);

		var pos = game.world.get_anchor_pos(raw_pos, structure_def);

		var inst = instance_create_layer(
			pos.x,
			pos.y,
			"Troops",
			obj_troop
		);

		inst.troop = undefined;

		var troop = {

			unit_id: troop_def.unit_id,
			build_id: _structure.build_id,
			structure_id: _structure.structure_id,
			movement_type: troop_def.movement_type,
			owner_id: _structure.owner_id,
			team: _structure.team,
			col: _structure.col,
			row: _structure.row,
			
			x: pos.x,
			y: pos.y,
			hsp: 0,
			vsp: 0,
			grounded: false,
			facing: _structure.facing,
			inst: inst,
			hp: troop_def.hp,
			max_hp: troop_def.hp,
			health_bar_timer: 0,
			think_timer: irandom_range(0, 25),		
			move_speed: troop_def.move_speed + random_range(-0.05, 0.05),
			move_acceleration: troop_def.move_speed * 0.04,
			move_deceleration: troop_def.move_speed * 0.08,

			attack_damage: troop_def.attack_damage,
			attack_range: troop_def.attack_range + irandom_range(-8, 8),
			attack_cooldown: troop_def.attack_cooldown,
			attack_timer: 0,
			target: undefined,

			path_valid: false,
			path_dir: 0,
			path_jump: false,
			move_dir: 0,
			jump_cd: 0,

			idle_sprite: troop_def.idle_sprite,
			image_index: 0,
			image_speed: 0.5,
			base_image_speed: 0.5,
	
			walk_sprite: troop_def.walk_sprite,
			attack_sprite: troop_def.attack_sprite,
			current_sprite: troop_def.idle_sprite,
			animation_mode: "NORMAL",
			collision_sprite: troop_def.collision_sprite,
	
			state: TroopState.THINK,
			active: true,
			
			net_dead_sent: false,
			net_x: pos.x,
			net_y: pos.y,
		};

		inst.troop = troop;

		return troop;

	}

	function spawn_from_structure(_structure) {

		var troop = self.create_troop_from_structure(_structure);

		if (!is_struct(troop))
			return undefined;

		array_push(items, troop);
		by_sid[$ string(troop.structure_id)] = troop;
		
		return troop;

	}

	function update_authority() {
		game.paths.update();
		
		for (var i = 0; i < array_length(items); i++) {

			var troop = items[i];

			if (!is_struct(troop)) continue;
			if (!troop.active) continue;

			if (variable_struct_exists(troop, "health_bar_timer")) {
				troop.health_bar_timer = max(0, troop.health_bar_timer - 1);
			}

			// Gravedad
			troop.grounded = game.collision.entity_on_ground(troop);

			var was_on_stair =
				!is_undefined(game.collision.get_stair_support_y(troop, 4));

			if (troop.grounded && troop.vsp > 0)
				troop.vsp = 0;

			troop.vsp = min(
				troop.vsp + game.config.troop_gravity,
				game.config.troop_max_fall
			);

			var previous_y = troop.y;

			game.collision.move_entity_y(troop, troop.vsp);

			var grid = game.world.get_grid_for_team(troop.team);
			var floor_y = game.world.get_floor_y(grid);

			if (troop.y >= floor_y) {

				troop.y = floor_y;
				troop.vsp = 0;
				troop.grounded = true;

			}

			if (troop.vsp >= 0) {

				if (was_on_stair) {

					var stair_tolerance =
						game.config.cell
						+ abs(troop.hsp)
						+ max(0, troop.vsp);

					game.collision.resolve_stair_contact(
						troop,
						stair_tolerance
					);

				}
				else {

					var stair_landing_tolerance =
						max(4, max(0, troop.vsp) + 1);

					game.collision.resolve_stair_landing(
						troop,
						previous_y,
						stair_landing_tolerance
					);

				}

			}

			// IA
			switch (troop.state) {

				case TroopState.THINK:
					self.think(troop);
				break;

				case TroopState.MOVE_TO_TARGET:
					self.move_to_target(troop);
				break;

				case TroopState.ATTACK:
					self.attack_target(troop);
				break;

				case TroopState.DEAD:
				break;

			}

			self.update_animation(troop);

			// Sincronizar instancia
			if (instance_exists(troop.inst)) {
				troop.inst.x = troop.x;
				troop.inst.y = troop.y;
			}

		}

	}
		
	function is_authority() {
		return !game.network.is_connected || game.network.is_host;
	}

	function update() {
		if (self.is_authority()) {
			self.update_authority();
			self.send_snapshot();
		}
		else {
			self.update_remote();
		}
	}

	function get_troop_by_sid(_sid) {
		return by_sid[$ string(_sid)];
	}

	function kill_troop(_troop) {
		_troop.hp = 0;
		_troop.active = false;
		_troop.state = TroopState.DEAD;

		if (instance_exists(_troop.inst)) {
			instance_destroy(_troop.inst);
		}
	}

	function send_snapshot() {
		if (!game.network.is_connected) return;

		snapshot_timer--;
		if (snapshot_timer > 0) return;
		snapshot_timer = 3;

		var list = [];

		for (var i = 0; i < array_length(items); i++) {
			var t = items[i];

			if (!is_struct(t)) continue;

			if (!t.active) {
				if (t.net_dead_sent) continue;
				t.net_dead_sent = true; // la muerte se manda una sola vez
			}

			array_push(list, [
				t.structure_id,
				round(t.x * 10) / 10,
				round(t.y * 10) / 10,
				round(t.hsp * 100) / 100,
				t.facing,
				t.hp,
				t.state
			]);
		}

		var damaged = game.structures.drain_net_dirty();
		var vault = game.world.get_vault();
		var vault_hp = is_struct(vault) ? vault.hp : -1;

		if (array_length(list) == 0 && array_length(damaged) == 0 && vault_hp == last_vault_hp) return;

		last_vault_hp = vault_hp;
		game.network.broadcast_troop_snapshot(list, damaged, vault_hp);
	}

	function apply_snapshot(_data) {
		for (var i = 0; i < array_length(_data.t); i++) {
			var e = _data.t[i];
			var t = self.get_troop_by_sid(e[0]);

			if (!is_struct(t)) continue;
			if (!t.active) continue;

			if (e[5] < t.hp) t.health_bar_timer = room_speed * 2;
			t.hp = e[5];

			if (t.hp <= 0) {
				self.kill_troop(t);
				continue;
			}

			t.net_x = e[1];
			t.net_y = e[2];
			t.hsp = e[3];
			t.facing = e[4];
			t.state = e[6];
		}

		for (var j = 0; j < array_length(_data.s); j++) {
			var d = _data.s[j];
			var s = game.structures.get_structure(d[0]);

			if (!is_struct(s) || !s.active) continue;

			if (d[1] < s.hp) s.health_bar_timer = room_speed * 2;
			s.hp = d[1];
		}

		var vault = game.world.get_vault();

		if (is_struct(vault) && _data.v >= 0) {
			var was_alive = vault.hp > 0;
			vault.hp = _data.v;

			if (was_alive && vault.hp <= 0) game.structures.invalidate_collision_cache();
		}
	}

	function update_remote() {
		for (var i = 0; i < array_length(items); i++) {
			var t = items[i];

			if (!is_struct(t)) continue;
			if (!t.active) continue;

			if (point_distance(t.x, t.y, t.net_x, t.net_y) > 128) {
				t.x = t.net_x;
				t.y = t.net_y;
			}
			else {
				t.x = lerp(t.x, t.net_x, 0.35);
				t.y = lerp(t.y, t.net_y, 0.35);
			}

			if (t.health_bar_timer > 0) t.health_bar_timer--;

			self.update_animation(t);

			if (instance_exists(t.inst)) {
				t.inst.x = t.x;
				t.inst.y = t.y;
			}
		}
	}
		
	function think(_troop) {

		_troop.think_timer--;

		if (_troop.think_timer <= 0) {
			_troop.state = TroopState.MOVE_TO_TARGET;
		}

	}
	
	function move_to_target(_troop) {

		var target = self.get_attack_target(_troop);

		if (!is_struct(target)) {
			_troop.hsp = self.move_towards(
				_troop.hsp,
				0,
				_troop.move_deceleration
			);
			game.collision.move_entity_x(_troop, _troop.hsp);
			return;
		}

		_troop.target = target;

		var in_range = self.target_in_range(_troop, target);
		var dx = target.point.x - _troop.x;

		// Rumbo (solo en suelo): campo de flujo, o recto al objetivo si no hay ruta.
		// En el aire se conserva el rumbo que llevaba.
		if (_troop.grounded) {
			if (_troop.path_valid) {
				_troop.move_dir = _troop.path_dir;
			}
			else if (abs(dx) > 0.1) {
				_troop.move_dir = sign(dx);
			}
		}

		if (in_range && _troop.grounded) {
			if (abs(dx) > 0.1) _troop.facing = sign(dx);
		}
		else if (_troop.move_dir != 0) {
			_troop.facing = _troop.move_dir;
		}

		// Salto
		if (_troop.jump_cd > 0) _troop.jump_cd--;

		var jumped = false;

		if (_troop.grounded
			&& _troop.vsp >= 0
			&& _troop.jump_cd <= 0
			&& _troop.path_valid
			&& _troop.path_jump) {

			_troop.vsp = -game.config.troop_jump_speed;
			_troop.jump_cd = 20;
			jumped = true;

		}

		// Velocidad horizontal
		if (jumped || !_troop.grounded) {

			// En el aire no hay aceleracion: se mantiene el rumbo a velocidad completa.
			_troop.hsp = _troop.move_dir * _troop.move_speed;

		}
		else {

			var target_speed = in_range ? 0 : _troop.move_dir * _troop.move_speed;

			var accel = (target_speed == 0)
				? _troop.move_deceleration
				: _troop.move_acceleration;

			_troop.hsp = self.move_towards(
				_troop.hsp,
				target_speed,
				accel
			);

		}

		game.collision.move_entity_x(_troop, _troop.hsp);

		if (_troop.grounded && !jumped && in_range && abs(_troop.hsp) <= 0.001) {

			_troop.hsp = 0;
			_troop.attack_timer = 0;
			_troop.state = TroopState.ATTACK;

		}

	}

	function attack_target(_troop) {
		var target = self.get_attack_target(_troop);

		if (!is_struct(target) || !self.target_in_range(_troop, target)) {
			_troop.target = undefined;
			_troop.state = TroopState.MOVE_TO_TARGET;
			return;
		}

		_troop.target = target;
		_troop.hsp = self.move_towards(
			_troop.hsp,
			0,
			_troop.move_deceleration
		);

		var dx = target.point.x - _troop.x;
		if (abs(dx) > 0.1)
			_troop.facing = sign(dx);

		if (_troop.attack_timer > 0) {
			_troop.attack_timer--;
			return;
		}

		self.damage_target(target, _troop.attack_damage);
		_troop.attack_timer = _troop.attack_cooldown;
	}

	function get_attack_target(_troop) {

		var enemy_team = (_troop.team == FortinTeam.GOBLINS)
			? FortinTeam.DEFENDERS
			: FortinTeam.GOBLINS;
		var vault_target = self.get_vault_target(_troop, enemy_team);

		_troop.path_valid = false;

		if (is_struct(vault_target) && self.target_in_range(_troop, vault_target)) {
			return vault_target;
		}

		// El campo de flujo decide (solo terrestres)
		if (_troop.movement_type == TroopMovementType.GROUND && game.paths.is_ready()) {

			var step = game.paths.get_step(_troop);

			if (step.valid) {

				_troop.path_valid = true;
				_troop.path_dir = step.dir;
				_troop.path_jump = step.jump;

				if (step.sid >= 0) {

					var wall = game.structures.get_structure(step.sid);

					if (is_struct(wall) && wall.active) {

						var wall_rect = game.structures.get_structure_target_rect(wall);

						if (is_struct(wall_rect)) {
							return self.make_target("STRUCTURE", wall, wall_rect, _troop);
						}

					}

				}

				return vault_target;

			}

		}

		// Fallback: comportamiento anterior (sin campo listo, sin ruta, o tropa aerea)
		var blocker_target = self.get_path_blocker_target(_troop, enemy_team, vault_target);

		if (is_struct(blocker_target)) {
			return blocker_target;
		}

		return vault_target;

	}

	function get_vault_target(_troop, _enemy_team) {
		if (_enemy_team != FortinTeam.DEFENDERS) return undefined;

		var vault = game.world.get_vault();

		if (is_struct(vault) && vault.hp > 0) {

			var grid = game.world.get_grid_for_team(vault.team);
			var pos = game.world.cell_to_world(grid, vault.col, vault.row);

			var rect = {
				x1: pos.x,
				y1: pos.y,
				x2: pos.x + vault.width * game.config.cell,
				y2: pos.y + vault.height * game.config.cell,
			};

			return self.make_target("VAULT", vault, rect, _troop);

		}

		return undefined;
	}

	function get_path_blocker_target(_troop, _enemy_team, _main_target) {
		if (!is_struct(_main_target)) return undefined;

		var body = game.collision.get_entity_rect(_troop);
		if (!is_struct(body)) return undefined;

		var path_dir = (_main_target.point.x >= _troop.x) ? 1 : -1;
		var path_x1 = (path_dir > 0) ? body.x2 : _main_target.rect.x2;
		var path_x2 = (path_dir > 0) ? _main_target.rect.x1 : body.x1;

		if (path_x1 > path_x2) {
			var swap_x = path_x1;
			path_x1 = path_x2;
			path_x2 = swap_x;
		}

		var best_target = undefined;
		var best_distance = undefined;
		var vertical_margin = 3;

		for (var i = 0; i < array_length(game.structures.items); i++) {
			var structure = game.structures.items[i];

			if (!is_struct(structure)) continue;
			if (!structure.active) continue;
			if (structure.team != _enemy_team) continue;
			if (!variable_struct_exists(structure, "hp")) continue;
			if (structure.hp <= 0) continue;
			if (!game.structures.is_solid_structure(structure)) continue;

			var rect = game.structures.get_structure_target_rect(structure);
			if (!is_struct(rect)) continue;

			var blocks_path =
				rect.x1 < path_x2 &&
				rect.x2 > path_x1 &&
				rect.y1 < body.y2 + vertical_margin &&
				rect.y2 > body.y1 - vertical_margin;

			if (!blocks_path) continue;

			if (self.can_walk_stair_in_direction(structure, path_dir)) {
				continue;
			}

			var distance = abs(((rect.x1 + rect.x2) * 0.5) - _troop.x);

			if (is_undefined(best_distance) || distance < best_distance) {
				best_distance = distance;
				best_target = self.make_target("STRUCTURE", structure, rect, _troop);
			}
		}

		return best_target;

	}

	function can_walk_stair_in_direction(_structure, _path_dir) {
		if (!game.structures.is_stair_structure(_structure)) return false;

		var stair_facing = game.structures.get_structure_facing(_structure);
		var climb_direction = -stair_facing;

		return sign(_path_dir) == climb_direction;
	}

	function make_target(_type, _owner, _rect, _troop) {
		return {
			type: _type,
			owner: _owner,
			rect: _rect,
			point: {
				x: clamp(_troop.x, _rect.x1, _rect.x2),
				y: clamp(_troop.y, _rect.y1, _rect.y2),
			},
		};
	}

	function target_in_range(_troop, _target) {
		return self.distance_to_target_rect(_troop, _target.rect) <= _troop.attack_range;
	}

	function distance_to_target_rect(_troop, _rect) {
		var body = game.collision.get_entity_rect(_troop);
		if (!is_struct(body)) return point_distance(_troop.x, _troop.y, _rect.x1, _rect.y1);

		var dx = 0;
		var dy = 0;

		if (body.x2 < _rect.x1) dx = _rect.x1 - body.x2;
		else if (body.x1 > _rect.x2) dx = body.x1 - _rect.x2;

		if (body.y2 < _rect.y1) dy = _rect.y1 - body.y2;
		else if (body.y1 > _rect.y2) dy = body.y1 - _rect.y2;

		return point_distance(0, 0, dx, dy);

	}

	function damage_target(_target, _amount) {
		if (_amount <= 0) return false;
		if (!is_struct(_target)) return false;

		if (_target.type == "STRUCTURE") {
			if (!is_struct(_target.owner)) return false;
			return game.structures.damage_structure(_target.owner.structure_id, _amount);
		}

		if (_target.type == "VAULT") {
			if (!is_struct(_target.owner)) return false;

			_target.owner.hp = max(0, _target.owner.hp - _amount);
			if (_target.owner.hp <= 0) {
				game.structures.invalidate_collision_cache();
			}
			return true;
		}

		return false;

	}

	function get_normal_sprite(_troop) {
		if (abs(_troop.hsp) > 0.01)
			return _troop.walk_sprite;

		return _troop.idle_sprite;
	}

	function update_animation(_troop) {
		var can_attack_animate =
			variable_struct_exists(_troop, "attack_sprite") &&
			!is_undefined(_troop.attack_sprite);

		var wants_attack_animation =
			can_attack_animate &&
			_troop.state == TroopState.ATTACK;

		if (wants_attack_animation) {
			if (_troop.animation_mode != "ATTACK") {
				_troop.animation_mode = "ATTACK";
				_troop.current_sprite = _troop.attack_sprite;
				_troop.image_index = 0;
			}
		}
		else if (_troop.animation_mode != "NORMAL") {
			_troop.animation_mode = "NORMAL";
			_troop.current_sprite = self.get_normal_sprite(_troop);
			_troop.image_index = 0;
		}

		var anim_speed = _troop.base_image_speed;

		if (_troop.animation_mode == "ATTACK") {
			_troop.current_sprite = _troop.attack_sprite;
		}
		else {
			var normal_sprite = self.get_normal_sprite(_troop);

			if (_troop.current_sprite != normal_sprite) {
				_troop.current_sprite = normal_sprite;
				_troop.image_index = 0;
			}
		}

		var frames = sprite_get_number(_troop.current_sprite);
		if (frames <= 0) return;

		_troop.image_speed = anim_speed;
		_troop.image_index += anim_speed;

		if (_troop.image_index >= frames) {
			_troop.image_index -= frames;
		}
	}

	function move_towards(_value, _target, _step) {

		if (_value < _target)
			return min(_value + _step, _target);

		if (_value > _target)
			return max(_value - _step, _target);

		return _value;

	}
	
	function draw_world() {
		game.paths.draw_debug();
	}

	function draw_troop_health_bar(_troop) {
		if (!is_struct(_troop)) return;
		if (!variable_struct_exists(_troop, "hp")) return;
		if (!variable_struct_exists(_troop, "max_hp")) return;
		if (!variable_struct_exists(_troop, "health_bar_timer")) return;
		if (_troop.health_bar_timer <= 0) return;
		if (_troop.max_hp <= 0) return;

		var rect = game.collision.get_entity_rect(_troop);
		if (!is_struct(rect)) return;

		var bar_w = max(24, min(46, rect.x2 - rect.x1 + 10));
		var bar_h = 4;
		var bar_x = rect.x1 + ((rect.x2 - rect.x1) - bar_w) * 0.5;
		var bar_y = rect.y1 - 9;
		var pct = clamp(_troop.hp / _troop.max_hp, 0, 1);

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
			var troop = items[i];

			if (!is_struct(troop)) continue;
			if (!troop.active) continue;

			self.draw_troop_health_bar(troop);
		}
	}

	function damage_troop(_troop, _amount) {
		if (!is_struct(_troop)) return false;
		if (!_troop.active) return false;
		if (!variable_struct_exists(_troop, "hp")) return false;

		// Cliente: solo avisa. El host calcula el daño y lo devuelve en el snapshot.
		if (!self.is_authority()) {
			game.network.send_to_host({
				msg: FortinNetMsg.DAMAGE_TROOP,
				sid: _troop.structure_id,
			});
			return true;
		}

		_troop.hp = max(0, _troop.hp - _amount);
		_troop.health_bar_timer = room_speed * 2;

		if (_troop.hp <= 0) self.kill_troop(_troop);

		return true;
	}

	function destroy() {

		for (var i = 0; i < array_length(items); i++) {

			var troop = items[i];

			if (!is_struct(troop)) continue;

			if (instance_exists(troop.inst)) {
				instance_destroy(troop.inst);
			}

		}

		reset();

	}
	
	function count() {

		return array_length(items);

	}
		
	function clear_troops() {

		for (var i = 0; i < array_length(items); i++) {

			var troop = items[i];

			if (!is_struct(troop)) continue;

			if (instance_exists(troop.inst)) {
				instance_destroy(troop.inst);
			}
		}

		items = [];
		by_sid = {};
		snapshot_timer = 0;
		last_vault_hp = -2;

	}
}
