function PlayerSystem(_game) constructor {
	game = _game;
	config = game.config;

	players = [];

	function make_player(_player_id, _team, _active) {
		var spawn = game.world.get_player_spawn(_team, _player_id);

		return {
			player_id: _player_id,
			team: _team,
			active: _active,
			x: spawn.x,
			y: spawn.y,
			hsp: 0,
			vsp: 0,
			build_hsp: 0,
			build_vsp: 0,
			grounded: false,
			facing: 1,
			image_index: 0,
			anim_state: "idle",
			collision_sprite: spr_player,
			moving: false,
			jump_phase: 0,       // 0 = sin animacion de salto, 1 = despegue, 2 = aire, 3 = aterrizaje
			trans_reverse: false, // si la transicion caminar<->idle se reproduce invertida
			fly_lean_angle: 0,    // inclinación visual actual en build (inercia al volar)
			fly_lean_velocity: 0, // velocidad angular del resorte de inclinación
			 
			// buffer
			jump_buffer_timer: 0,
			attack_queued: false,
			coyote_timer: 0,
			input_grace_frames: 0,
			
			// combat
			attack_hit_flash_timer: 0,
			hp: config.player_max_hp,
			max_hp: config.player_max_hp,
			alive: true,
			attack_damage: config.player_attack_damage,
			attack_cooldown: config.player_attack_cooldown,
			attack_timer: 0,
			health_bar_timer: 0,
			attack_frame: 0,
			attack_hit_resolved: true,
			attack_hit_list: [],
			attack_hit_count: 0,
			
			// net
			net_x: spawn.x,
			net_y: spawn.y,
			net_init: false,
			net_atk_seq: 0,
			net_jmp_seq: 0,
			atk_seq: 0,
			jmp_seq: 0,
			net_hsp: 0,
			net_vsp: 0,
			net_age: 0,
		};
	}

	function reset() {
    var previous = players;
    players = [];

    for (var i = 0; i < config.max_players; i++) {
        var existing = (i < array_length(previous)) ? previous[i] : undefined;
        var team = is_struct(existing) ? existing.team : FortinTeam.DEFENDERS;
        var active = is_struct(existing) ? existing.active : false;

        players[i] = self.make_player(i, team, active);
    }
}

	function get_player(_player_id) {
		if (_player_id < 0 || _player_id >= array_length(players)) return undefined;
		return players[_player_id];
	}

	function get_local_player() {
		return self.get_player(config.local_player_id);
	}
		
	function get_player_team(_player_id) {

	var p = self.get_player(_player_id);

	if (!is_struct(p)) {
		return FortinTeam.DEFENDERS;
	}
	return p.team;
}
		
	function set_player_team(_player_id, _team) {

	var p = self.get_player(_player_id);
	if (!is_struct(p)) return false;

	p.team = _team;

	var spawn = game.world.get_player_spawn(_team, _player_id);

	p.x = spawn.x;
	p.y = spawn.y;

	return true;
}
		
	function set_player_active(_player_id, _active) {
		var p = self.get_player(_player_id);
		if (is_undefined(p)) return false;

		p.active = _active;
		return true;
	}

	function net_field(_d, _name, _default) {
		return variable_struct_exists(_d, _name) ? _d[$ _name] : _default;
	}

	function apply_player_state(_player_id, _d) {
		var p = self.get_player(_player_id);
		if (is_undefined(p)) return false;

		p.active = true;
		p.net_x = _d.x;
		p.net_y = _d.y;
		p.net_hsp = _d.hsp;
		p.net_vsp = _d.vsp;
		p.net_age = 0;
		p.hsp = _d.hsp;
		p.vsp = _d.vsp;
		p.grounded = _d.grounded;
		p.facing = _d.facing;
		p.moving = self.net_field(_d, "moving", false);
		p.fly_lean_angle = self.net_field(_d, "lean", 0);

		var atk = self.net_field(_d, "atk", 0);
		var jmp = self.net_field(_d, "jmp", 0);

		// Primer paquete: sin interpolar desde el spawn ni disparar animaciones viejas
		if (!p.net_init) {
			p.x = _d.x;
			p.y = _d.y;
			p.net_atk_seq = atk;
			p.net_jmp_seq = jmp;
			p.net_init = true;
			return true;
		}

		// Salto y ataque se disparan UNA vez por cada cambio de contador
		if (jmp != p.net_jmp_seq) {
			p.net_jmp_seq = jmp;
			p.jump_phase = 1;

			if (p.anim_state != "attack") {
				p.anim_state = "jump";
				p.image_index = 0;
			}
		}

		if (atk != p.net_atk_seq) {
			p.net_atk_seq = atk;
			p.anim_state = "attack";
			p.image_index = 0;
		}

		return true;
	}

	function get_player_rect(_x, _y) {

		var p = {
			x: _x,
			y: _y,
			collision_sprite: spr_player
		};

		return game.collision.get_entity_rect(p);

	}

	function get_player_collision_width(_x, _y) {
		var body = self.get_player_rect(_x, _y);
		return max(1, body.x2 - body.x1);
	}

	function get_stair_swept_landing_y(
		_p,
		_previous_x,
		_previous_y,
		_tolerance
	) {

		var body_now =
			self.get_player_rect(
				_p.x,
				_p.y
			);

		var probe_offsets = [
			body_now.x1 - _p.x,
			0,
			body_now.x2 - 1 - _p.x
		];

		var steps =
			max(
				2,
				ceil(
					max(
						abs(_p.x - _previous_x),
						abs(_p.y - _previous_y)
					) / 4
				)
			);

		var best_y = undefined;
		var best_delta = undefined;

		for (var step = 1; step <= steps; step++) {

			var t = step / steps;

			var scan_x =
				lerp(
					_previous_x,
					_p.x,
					t
				);

			var scan_y =
				lerp(
					_previous_y,
					_p.y,
					t
				);

			for (
				var i = 0;
				i < array_length(probe_offsets);
				i++
			) {

				var probe_x =
					scan_x + probe_offsets[i];

				var previous_probe_x =
					_previous_x + probe_offsets[i];

				for (
					var j = 0;
					j < array_length(game.structures.items);
					j++
				) {

					var s =
						game.structures.items[j];

					if (!is_struct(s))
						continue;

					if (!s.active)
						continue;

					if (!game.collision.is_stair_structure(s))
						continue;


					var surface_y =
						game.collision.get_stair_surface_y(
							s,
							probe_x
						);

					if (is_undefined(surface_y))
						continue;


					var previous_surface_y =
						game.collision.get_stair_surface_y(
							s,
							previous_probe_x
						);

					if (
						!is_undefined(previous_surface_y)
						&& _previous_y >
							previous_surface_y + _tolerance
					) {
						continue;
					}


					if (scan_y < surface_y)
						continue;


					var delta =
						scan_y - surface_y;

					if (delta > _tolerance)
						continue;


					// Elegimos la pendiente que está más cerca
					// de la posición actual del jugador.
					if (
						is_undefined(best_delta)
						|| delta < best_delta
					) {

						best_delta = delta;
						best_y = surface_y;
					}
				}
			}

			if (!is_undefined(best_y))
				return best_y;
		}

		return best_y;
	}

	function resolve_stair_swept_landing(_p, _previous_x, _previous_y, _tolerance) {
	    var surface_y = self.get_stair_swept_landing_y(_p, _previous_x, _previous_y, _tolerance);
	    if (is_undefined(surface_y)) return false;

	    var candidate_rect = self.get_player_rect(_p.x, surface_y);

	    if (game.collision.rect_hits_solid(
	        candidate_rect.x1, candidate_rect.y1,
	        candidate_rect.x2, candidate_rect.y2
	    )) {
	        return false;
	    }

	    _p.y = surface_y;
	    _p.vsp = 0;
	    _p.grounded = true;

	    return true;
	}
		
	function reset_combat_stats() {
		for (var i = 0; i < array_length(players); i++) {
			var p = players[i];
			if (!is_struct(p)) continue;

			p.hp = config.player_max_hp;
			p.debuffs = {};
			p.trap_inside = {};
			p.max_hp = config.player_max_hp;
			p.alive = true;
			p.attack_timer = 0;
			p.attack_queued = false;
			p.attack_frame = 0;
			p.attack_hit_resolved = true;
			p.jump_buffer_timer = 0;
			p.coyote_timer = 0;
			p.input_grace_frames = 2;
			
		}
	}

	function get_attack_hitbox_rect(_p) {
		var offset = config.player_attack_hitbox_offset * _p.facing;

		var hitbox_entity = {
			x: _p.x + offset,
			y: _p.y,
			collision_sprite: spr_entity_attack_hitbox
		};

		return game.collision.get_entity_rect(hitbox_entity);
	}
		
	function rect_distance_to_point(_rect, _px, _py) {
		var dx = 0;
		var dy = 0;

		if (_px < _rect.x1) dx = _rect.x1 - _px;
		else if (_px > _rect.x2) dx = _px - _rect.x2;

		if (_py < _rect.y1) dy = _rect.y1 - _py;
		else if (_py > _rect.y2) dy = _py - _rect.y2;

		return point_distance(0, 0, dx, dy);
	}
	
	function try_attack(_p) {
		if (!_p.alive) return;
		if (_p.attack_timer > 0) return;

		_p.attack_timer = _p.attack_cooldown;
		_p.anim_state = "attack";
		_p.image_index = 0;
		_p.attack_frame = 0;
		_p.attack_hit_resolved = false;
		_p.atk_seq += 1;
		_p.attack_hit_list = [];
		_p.attack_hit_count = 0;
	}

	function sort_targets_by_distance(_targets) {
		var n = array_length(_targets);
		for (var i = 1; i < n; i++) {
			var current = _targets[i];
			var j = i - 1;
			while (j >= 0 && _targets[j].distance > current.distance) {
				_targets[j + 1] = _targets[j];
				j--;
			}
			_targets[j + 1] = current;
		}
	}

	function resolve_attack_hits(_p) {
		var hitbox = self.get_attack_hitbox_rect(_p);
		if (!is_struct(hitbox)) return;

		var mx = mouse_x;
		var my = mouse_y;

		var enemy_team = (_p.team == FortinTeam.GOBLINS)
			? FortinTeam.DEFENDERS
			: FortinTeam.GOBLINS;

		var candidates = [];

		// Jugadores enemigos
		for (var i = 0; i < array_length(players); i++) {
			var target = players[i];
			if (!is_struct(target)) continue;
			if (!target.active || !target.alive) continue;
			if (target.team != enemy_team) continue;

			var t_rect = game.collision.get_sprite_rect(spr_entity_hurtbox, target.x, target.y);
			if (!game.collision.rects_overlap(
				hitbox.x1, hitbox.y1, hitbox.x2, hitbox.y2,
				t_rect.x1, t_rect.y1, t_rect.x2, t_rect.y2
			)) continue;

			array_push(candidates, {
				type: "PLAYER",
				ref: target,
				distance: self.rect_distance_to_point(t_rect, mx, my),
			});
		}

		// Tropas goblin enemigas
		for (var i = 0; i < array_length(game.troops.items); i++) {
			var troop = game.troops.items[i];
			if (!is_struct(troop)) continue;
			if (!troop.active) continue;
			if (troop.team != enemy_team) continue;

			var t_rect = game.collision.get_sprite_rect(spr_entity_hurtbox, troop.x, troop.y);
			if (!game.collision.rects_overlap(
				hitbox.x1, hitbox.y1, hitbox.x2, hitbox.y2,
				t_rect.x1, t_rect.y1, t_rect.x2, t_rect.y2
			)) continue;

			array_push(candidates, {
				type: "TROOP",
				ref: troop,
				distance: self.rect_distance_to_point(t_rect, mx, my),
			});
		}

		// Estructuras enemigas
		for (var i = 0; i < array_length(game.structures.items); i++) {
			var structure = game.structures.items[i];
			if (!is_struct(structure)) continue;
			if (!structure.active) continue;
			if (structure.team != enemy_team) continue;

			var s_rect = game.structures.get_structure_target_rect(structure);
			if (!is_struct(s_rect)) continue;
			if (!game.collision.rects_overlap(
				hitbox.x1, hitbox.y1, hitbox.x2, hitbox.y2,
				s_rect.x1, s_rect.y1, s_rect.x2, s_rect.y2
			)) continue;

			array_push(candidates, {
				type: "STRUCTURE",
				ref: structure,
				distance: self.rect_distance_to_point(s_rect, mx, my),
			});
		}

		self.sort_targets_by_distance(candidates);

		for (var i = 0; i < array_length(candidates); i++) {
			if (_p.attack_hit_count >= config.player_attack_max_targets) break;

			var c = candidates[i];

			// Ya lo golpeé en este mismo ataque
			if (array_contains(_p.attack_hit_list, c.ref)) continue;

			array_push(_p.attack_hit_list, c.ref);
			_p.attack_hit_count++;

			switch (c.type) {
				case "PLAYER":
					self.damage_player(c.ref, _p.attack_damage);
					break;

				case "TROOP":
					game.troops.damage_troop(c.ref, _p.attack_damage);
					break;

				case "STRUCTURE":
					game.structures.damage_structure(c.ref.structure_id, _p.attack_damage);
					break;
			}
		}
	}

	function damage_player(_p, _amount) {
		if (!_p.alive) return false;

		_p.hp = max(0, _p.hp - _amount);
		_p.health_bar_timer = room_speed * 2;

		if (_p.hp <= 0) {
			self.kill_player(_p);
		}

		game.network.send_player_damage(_p.player_id, _p.hp, _p.alive);

		return true;
	}

	function apply_player_damage(_player_id, _hp, _alive) {
		var p = self.get_player(_player_id);
		if (is_undefined(p)) return false;
		if (_hp < p.hp) p.health_bar_timer = room_speed * 2;

		p.hp = _hp;
		p.alive = _alive;

		if (!p.alive) {
			p.hsp = 0;
			p.vsp = 0;
		}

		return true;
	}

	function kill_player(_p) {
		_p.alive = false;
		_p.hp = 0;
		_p.hsp = 0;
		_p.vsp = 0;
		// TODO: BattleSystem debe chequear aquí condición de victoria del equipo
	}

	function draw_player_health_bar(_p) {
		if (!_p.active || !_p.alive) return;
		if (!variable_struct_exists(_p, "health_bar_timer")) return;
		if (_p.health_bar_timer <= 0) return;
		if (_p.max_hp <= 0) return;

		var rect = self.get_player_rect(_p.x, _p.y);
		if (!is_struct(rect)) return;

		var bar_w = max(24, min(46, rect.x2 - rect.x1 + 10));
		var bar_h = 4;
		var bar_x = rect.x1 + ((rect.x2 - rect.x1) - bar_w) * 0.5;
		var bar_y = rect.y1 - 9;
		var pct = clamp(_p.hp / _p.max_hp, 0, 1);

		draw_set_color(c_black);
		draw_rectangle(bar_x - 1, bar_y - 1, bar_x + bar_w + 1, bar_y + bar_h + 1, false);
		draw_set_color(c_red);
		draw_rectangle(bar_x, bar_y, bar_x + bar_w, bar_y + bar_h, false);
		draw_set_color(c_lime);
		draw_rectangle(bar_x, bar_y, bar_x + bar_w * pct, bar_y + bar_h, false);
		draw_set_color(c_white);
	}

	function draw_health_bars() {
		for (var i = 0; i < array_length(players); i++) {
			var p = players[i];
			if (!is_struct(p)) continue;

			self.draw_player_health_bar(p);
		}
	}

	function update_build() {

		var p = self.get_local_player();
		if (is_undefined(p) || !p.active) return;
		if (game.world.is_peeking) return;
		
		var grid = game.world.get_grid_for_team(p.team);


		// ---------------- INPUT ----------------

		var move_x =
			keyboard_check(ord("D"))
			- keyboard_check(ord("A"));

		var move_y =
			keyboard_check(ord("S"))
			- keyboard_check(ord("W"));

		var input_length = sqrt(
			move_x * move_x +
			move_y * move_y
		);

		if (input_length > 1) {
			move_x /= input_length;
			move_y /= input_length;
		}

		p.moving = (move_x != 0 || move_y != 0);

		if (move_x != 0)
			p.facing = sign(move_x);


		// ---------------- SMOOTHING ----------------

		var target_hsp =
			move_x * config.player_build_speed;

		var target_vsp =
			move_y * config.player_build_speed;


		if (move_x != 0) {

			p.build_hsp = lerp(
				p.build_hsp,
				target_hsp,
				config.player_build_accel
			);

		}
		else {

			p.build_hsp = lerp(
				p.build_hsp,
				0,
				config.player_build_friction
			);

			if (abs(p.build_hsp) < 0.05)
				p.build_hsp = 0;
		}


		if (move_y != 0) {

			p.build_vsp = lerp(
				p.build_vsp,
				target_vsp,
				config.player_build_accel
			);

		}
		else {

			p.build_vsp = lerp(
				p.build_vsp,
				0,
				config.player_build_friction
			);

			if (abs(p.build_vsp) < 0.05)
				p.build_vsp = 0;
		}

		// ---------------- INCLINACIÓN POR INERCIA (VUELO) ----------------
		//
		// Resorte amortiguado en vez de un lerp directo: el lerp
		// siempre frena suavemente hacia el objetivo sin pasarse,
		// lo cual se siente mecánico. Un resorte permite un leve
		// "overshoot" natural (como si tuviera peso real) antes de
		// asentarse, mucho más orgánico.
		//

		var max_lean_degrees = 15;
		var spring_stiffness = 0.045; // qué tan fuerte "tira" hacia el objetivo
		var spring_damping = 0.32;    // qué tanto frena el rebote (más alto = menos overshoot)

		var build_speed_ref = max(1, config.player_build_speed);
		var lean_strength_linear = clamp(
			abs(p.build_hsp) / build_speed_ref,
			0,
			1
		);

		// Curva de easing (ease-out cúbica): al principio del
		// movimiento el ángulo crece rápido, y se acerca al máximo
		// de forma progresiva en vez de lineal — se siente menos
		// "de golpe".
		var lean_strength = 1 - power(1 - lean_strength_linear, 3);

		var target_lean_angle =
			-sign(p.build_hsp) * lean_strength * max_lean_degrees;

		var angle_diff = target_lean_angle - p.fly_lean_angle;
		var spring_accel =
			angle_diff * spring_stiffness
			- p.fly_lean_velocity * spring_damping;

		p.fly_lean_velocity += spring_accel;
		p.fly_lean_angle += p.fly_lean_velocity;
		
		
		// ---------------- ¿YA ESTABA SOBRE UNA ESCALERA? ----------------
		//
		// Se calcula ANTES de mover, con tolerancia chica (igual que
		// en battle). Esto decide si usamos una tolerancia generosa
		// (seguir la pendiente mientras caminas por ella) o una
		// tolerancia chica (aterrizar / rozar de lado no te aspira).
		//

		var was_on_stair =
			!is_undefined(
				game.collision.get_stair_support_y(p, 4)
			);


		// ---------------- CUERPO TEMPORAL ----------------

		var body = {
			x: p.x,
			y: p.y,
			team: p.team,
			collision_sprite: p.collision_sprite,
			hsp: p.build_hsp,
			vsp: p.build_vsp,
			grounded: false
		};


		// ---------------- MOVIMIENTO X ----------------

		game.collision.move_entity_x(
			body,
			body.hsp
		);


		// ---------------- LÍMITES HORIZONTALES ----------------

		var player_rect = self.get_player_rect(
			body.x,
			body.y
		);

		var left_offset = player_rect.x1 - body.x;
		var right_offset = player_rect.x2 - body.x;

		body.x = clamp(
			body.x,
			game.world.get_left(grid) - left_offset,
			game.world.get_right(grid) - right_offset
		);


		// ---------------- MOVIMIENTO Y ----------------

		game.collision.move_entity_y(
			body,
			body.vsp
		);


		// ---------------- ESCALERAS ----------------

		var body_rect = self.get_player_rect(
		    body.x,
		    body.y
		);

		var probe_xs = [
			body_rect.x1,
			body.x,
			body_rect.x2 - 1
		];


		// ---------------- SUPERFICIE DE PENDIENTE MÁS CERCANA ----------------
		//
		// Por cada X de sondeo buscamos las escaleras físicas de esa
		// columna (pueden ser varias, apiladas a distinta altura) y
		// evaluamos cada una por separado: su superficie Y, y si el
		// jugador está bajo SU base. Todo esto por-escalera, nunca
		// como un veto global.
		//
		// Tolerancia generosa si ya venías sobre una escalera (para
		// seguir la pendiente al caminar), tolerancia chica si no
		// (para no "aspirarte" al rozar el lado o el piso normal).
		//

		var stair_surface_y = undefined;
		var best_delta = undefined;

		var tolerance_down = was_on_stair
			? config.cell + abs(body.hsp) + abs(body.vsp)
			: max(4, abs(body.vsp) + 4);

		for (var i = 0; i < array_length(probe_xs); i++) {

			var probe_x = probe_xs[i];

			var stairs_here = game.collision.get_active_stairs_near_rect(
				probe_x,
				0,
				probe_x + 1,
				1
			);

			for (var j = 0; j < array_length(stairs_here); j++) {

				var stair = stairs_here[j];

				var surface_y = game.collision.get_stair_surface_y(
					stair,
					probe_x
				);

				if (is_undefined(surface_y))
					continue;

				var stair_rect =
					game.collision.get_structure_rect(stair);

				if (!is_struct(stair_rect))
					continue;

				// Si el jugador está completamente debajo de la
				// base de ESTA escalera, su pendiente no debe
				// levitarlo desde abajo. Chequeo por-escalera.
				if (body_rect.y1 >= stair_rect.y2)
					continue;

				var delta = body_rect.y2 - surface_y;

				if (delta <= 0 || delta > tolerance_down)
					continue;

				if (
					is_undefined(best_delta)
					|| delta < best_delta
				) {
					best_delta = delta;
					stair_surface_y = surface_y;
				}
			}
		}


		// ---------------- SNAP A LA PENDIENTE ----------------

		if (!is_undefined(stair_surface_y)) {

			var stair_y =
				stair_surface_y
				- (body_rect.y2 - body.y);

			var stair_rect = self.get_player_rect(
				body.x,
				stair_y
			);

			if (!game.collision.rect_hits_solid(
				stair_rect.x1,
				stair_rect.y1,
				stair_rect.x2,
				stair_rect.y2
			)) {
				body.y = stair_y;
			}
		}


		// ---------------- LÍMITES VERTICALES ----------------

		var final_rect = self.get_player_rect(
			body.x,
			body.y
		);

		var top_offset =
			final_rect.y1 - body.y;

		var bottom_offset =
			final_rect.y2 - body.y;

		var grid_bottom =
			game.world.get_floor_y(grid);

		var grid_top =
			grid_bottom - config.build_h;

		body.y = clamp(
			body.y,
			grid_top - top_offset,
			grid_bottom - bottom_offset
		);


		// ---------------- APLICAR ----------------

		p.x = body.x;
		p.y = body.y;

		// Build no utiliza gravedad ni grounded.

		p.grounded = false;

		p.hsp = 0;
		p.vsp = 0;


	}

	function update_battle() {

		var p = self.get_local_player();
		if (is_undefined(p) || !p.active) return;
		if (!p.alive) return;
		if (p.input_grace_frames > 0) p.input_grace_frames--;
			
			
		var grid = game.world.get_active_grid();

		p.grounded = game.collision.entity_on_ground(p);

		var was_on_stair =
			!is_undefined(
				game.collision.get_stair_support_y(p, 4)
			);

		if (p.grounded && p.vsp > 0)
			p.vsp = 0;

		// ---------------- MOVIMIENTO ----------------

		var move_x =
			keyboard_check(ord("D"))
			- keyboard_check(ord("A"));

		move_x +=
			keyboard_check(vk_right)
			- keyboard_check(vk_left);

		move_x = clamp(move_x, -1, 1);

		p.moving = (move_x != 0);

		// ---------------- SALTO ----------------

		var jump_pressed =
			keyboard_check_pressed(ord("W")) && p.input_grace_frames <= 0;

		var jump_held =
			keyboard_check(ord("W"));

		if (jump_pressed)
			p.jump_buffer_timer = config.player_jump_buffer_frames;
		else
			p.jump_buffer_timer = max(0, p.jump_buffer_timer - 1);

		if (p.grounded)
			p.coyote_timer = config.player_coyote_frames;
		else
			p.coyote_timer = max(0, p.coyote_timer - 1);

		var can_jump = p.grounded || p.coyote_timer > 0;

		if (p.jump_buffer_timer > 0 && can_jump) {

			p.vsp = -config.player_jump_speed;
			p.grounded = false;
			p.jump_buffer_timer = 0;
			p.coyote_timer = 0; // consumido — evita doble salto en el aire

			p.jump_phase = 1;
			p.jmp_seq += 1;

			if (p.anim_state != "attack") {
				p.anim_state = "jump";
				p.image_index = 0;
			}
		}
	
		// ------------ ATACAR --------
		
		p.attack_timer = max(0, p.attack_timer - 1);

		var attack_pressed = mouse_check_button_pressed(mb_left) && p.input_grace_frames <= 0;

		if (attack_pressed)
			p.attack_queued = true;

		if (p.attack_queued && p.attack_timer <= 0) {
			self.try_attack(p);
			p.attack_queued = false;
		}
	
		if (!p.attack_hit_resolved) {

			p.attack_frame++;

			if (p.attack_frame >= config.player_attack_hit_frame) {
				self.resolve_attack_hits(p);
				p.attack_hit_flash_timer = 6;

				var window_end = config.player_attack_hit_frame + config.player_attack_active_frames - 1;

				if (p.attack_frame >= window_end
				|| p.attack_hit_count >= config.player_attack_max_targets) {
					p.attack_hit_resolved = true;
				}
			}
		}
	
		// ---------------- ACELERACIÓN ----------------

		var target_hsp =
			move_x * config.player_speed;

		var accel =
			p.grounded
				? config.player_accel
				: config.player_air_accel;

		var mfriction =
			p.grounded
				? config.player_friction
				: config.player_air_friction;

		if (move_x != 0) {

			p.hsp = lerp(
				p.hsp,
				target_hsp,
				accel
			);

			p.facing = sign(move_x);
		}
		else {

			p.hsp = lerp(
				p.hsp,
				0,
				mfriction
			);

			if (abs(p.hsp) < 0.05)
				p.hsp = 0;
		}

		// ---------------- GRAVEDAD ----------------

		if (!jump_held && p.vsp < 0)
			p.vsp += config.player_jump_cut_gravity;

		p.vsp = min(
			p.vsp + config.player_gravity,
			config.player_max_fall
		);

		// ---------------- MOVIMIENTO X ----------------

		var previous_x = p.x;

		game.collision.move_entity_x(
			p,
			p.hsp
		);

		var player_rect = self.get_player_rect(
			p.x,
			p.y
		);

		var left_offset = player_rect.x1 - p.x;
		var right_offset = player_rect.x2 - p.x;

		p.x = clamp(
			p.x,
			game.world.get_left(grid) - left_offset,
			game.world.get_right(grid) - right_offset
		);

		// ---------------- MOVIMIENTO Y ----------------

		p.grounded = false;

		var previous_y = p.y;

		game.collision.move_entity_y(
			p,
			p.vsp
		);

		var floor_y =
			game.world.get_floor_y(grid);

		if (p.y >= floor_y) {

			p.y = floor_y;
			p.vsp = 0;
			p.grounded = true;
		}

		// ---------------- ESCALERAS ----------------

		if (p.vsp >= 0) {

			if (was_on_stair) {

				var stair_tolerance =
					config.cell
					+ abs(p.hsp)
					+ max(0, p.vsp);

				game.collision.resolve_stair_contact(
					p,
					stair_tolerance
				);
			}
			else {

				var stair_landing_tolerance =
					max(
						4,
						max(0, p.vsp) + 1
					);

				game.collision.resolve_stair_landing(
					p,
					previous_y,
					stair_landing_tolerance
				);
			}
		}
	}

	function update_local() {

		if (game.state == FortinState.BUILD) {

			self.update_build();
			return;
		}

		if (game.state == FortinState.BATTLE) {

			self.update_battle();
			return;
		}
	}

	function update() {
		if (game.state != FortinState.BUILD
		&& game.state != FortinState.BATTLE) return;
		
		self.update_remote_players();
		self.update_local();
		game.network.send_local_player_state();
	}
		
	function update_remote_players() {
		for (var i = 0; i < array_length(players); i++) {
			var p = players[i];

			if (!is_struct(p) || !p.active) continue;

			if (p.health_bar_timer > 0) p.health_bar_timer--;

			if (p.player_id == config.local_player_id) continue;
			if (!p.net_init) continue;

			if (point_distance(p.x, p.y, p.net_x, p.net_y) > 160) {
				p.x = p.net_x;
				p.y = p.net_y;
				p.net_age = 0;
			}
			else {
				p.net_age = min(p.net_age + 1, config.net_extrapolate_max);

				// Predicción: dónde debería estar ahora según su última velocidad
				var tx = p.net_x + p.net_hsp * p.net_age;
				var ty = p.grounded ? p.net_y : p.net_y + p.net_vsp * p.net_age;

				p.x = lerp(p.x, tx, config.net_smooth);
				p.y = lerp(p.y, ty, config.net_smooth);
			}
		}
	}
		
	function move_players_between_layouts(_defender_from_x, _defender_from_y, _goblin_from_x, _goblin_from_y) {
		for (var i = 0; i < array_length(players); i++) {
			var p = players[i];
			if (!is_struct(p) || !p.active) continue;

			var old_x = (p.team == FortinTeam.GOBLINS) ? _goblin_from_x : _defender_from_x;
			var old_y = (p.team == FortinTeam.GOBLINS) ? _goblin_from_y : _defender_from_y;
			var new_grid = game.world.get_grid_for_team(p.team);

			p.x = new_grid.x + (p.x - old_x);
			p.y = new_grid.y + (p.y - old_y);
			p.net_x = p.x;
			p.net_y = p.y;
		}
	}

	function get_player_anim_sprite(_state) {
		switch (_state) {
			case "walk":   return (sprite_exists(spr_player_walk_red))   ? spr_player_walk_red   : spr_player_idle_red;
			case "jump":   return (sprite_exists(spr_player_jump_red))   ? spr_player_jump_red   : spr_player_idle_red;
			case "trans":  return (sprite_exists(spr_player_trans_red))  ? spr_player_trans_red  : spr_player_idle_red;
			case "attack": return (sprite_exists(spr_player_attack_red)) ? spr_player_attack_red : spr_player_idle_red;
			default:       return spr_player_idle_red;
		}
	}

	function draw_anim_frame(_spr, _frame, _p, _visual_scale) {
		draw_set_color(c_white);
		draw_sprite_ext(_spr, _frame, _p.x, _p.y, _p.facing * _visual_scale, _visual_scale, 0, c_white, 1);
	}

	function draw_leaning_sprite(_spr, _frame, _p, _visual_scale, _angle) {

		// IMPORTANTE: dr

		var xoff = sprite_get_xoffset(_spr);
		var yoff = sprite_get_yoffset(_spr);

		var left   = (sprite_get_bbox_left(_spr)   - xoff)     * _visual_scale;
		var right  = (sprite_get_bbox_right(_spr)  - xoff + 1) * _visual_scale;
		var top    = (sprite_get_bbox_top(_spr)    - yoff)     * _visual_scale;
		var bottom = (sprite_get_bbox_bottom(_spr) - yoff + 1) * _visual_scale;

		// Pivote: misma X que el origen, Y en el borde superior
		// REAL del dibujo (bbox_top), no del canvas completo.
		var pivot_x = 0;
		var pivot_y = top;

		var corners_x = [left, right, right, left];
		var corners_y = [top, top, bottom, bottom];

		var world_x = array_create(4);
		var world_y = array_create(4);

		var c = dcos(_angle);
		var s = dsin(_angle);

		for (var i = 0; i < 4; i++) {

			var dx = corners_x[i] - pivot_x;
			var dy = corners_y[i] - pivot_y;

			var rx = dx * c + dy * s;
			var ry = -dx * s + dy * c;

			world_x[i] = _p.x + pivot_x + rx;
			world_y[i] = _p.y + pivot_y + ry;
		}

		// Espejado horizontal según hacia dónde mira, intercambiando
		// las esquinas izquierda/derecha del mapeo (sin tocar la
		// rotación ya calculada).
		if (_p.facing < 0) {

			var tx = world_x[0]; var ty = world_y[0];
			world_x[0] = world_x[1]; world_y[0] = world_y[1];
			world_x[1] = tx; world_y[1] = ty;

			tx = world_x[3]; ty = world_y[3];
			world_x[3] = world_x[2]; world_y[3] = world_y[2];
			world_x[2] = tx; world_y[2] = ty;
		}


	    draw_set_color(c_white);

	    draw_sprite_ext(
	        _spr, _frame,
	        _p.x, _p.y,
	        _p.facing * _visual_scale, _visual_scale,
	        _angle, // sin condicional de facing — el mirror (xscale negativo) ya invierte el sentido visual solo
	        c_white, 1
	    );
	}
	
	function draw_player(_p) {
		if (!_p.active) return;
		if (!_p.alive) return; 

		var visual_scale = 64 / 256; // spr_player_idle_red es 256x256, lo mostramos a 64x64
		var anim_speed = 0.5; // subimagenes por frame, ajusta a gusto

		// ---------------- BUILD: SIEMPRE VOLANDO ----------------

		if (game.state == FortinState.BUILD) {
			
			if (_p.anim_state != "fly") {
				_p.anim_state = "fly";
				_p.jump_phase = 0;
				_p.image_index = 0;
				_p.fly_lean_angle = 0;
				_p.fly_lean_velocity = 0;
			}
			
			var fly_spr = spr_player_fly_red;
			var fly_frame_count = sprite_get_number(fly_spr);
			
			
			
			self.draw_leaning_sprite(
				fly_spr,
				floor(_p.image_index),
				_p,
				visual_scale,
				_p.fly_lean_angle
			);

			_p.image_index += anim_speed;
			if (_p.image_index >= fly_frame_count)
				_p.image_index -= fly_frame_count;

			return;
			
		}

		// ---------------- SALTO ----------------
		// 0-6 despegue (siempre completo), 7-27 aire (se acorta/loopea segun cuanto dure el salto),
		// 28-33 aterrizaje (siempre completo)
		if (_p.anim_state == "jump") {
			var jump_spr = self.get_player_anim_sprite("jump");
			var jump_frame_count = sprite_get_number(jump_spr);

			var takeoff_end = min(6, jump_frame_count - 1);
			var air_start    = min(7, jump_frame_count - 1);
			var air_end      = min(27, jump_frame_count - 1);
			var land_start   = min(28, jump_frame_count - 1);
			var land_end     = jump_frame_count - 1;

			switch (_p.jump_phase) {
				case 1: // empujando desde el suelo
					_p.image_index += anim_speed;
					if (_p.image_index > takeoff_end) {
						_p.jump_phase = 2;
						_p.image_index = air_start;
					}
					break;

				case 2: // en el aire
					_p.image_index += anim_speed;
					if (_p.image_index > air_end) _p.image_index = air_start; // loop mientras siga en el aire
					if (_p.grounded) {
						_p.jump_phase = 3;
						_p.image_index = land_start;
					}
					break;

				case 3: // ya en el suelo, terminando la animacion
					_p.image_index += anim_speed;
					if (_p.image_index > land_end) {
						_p.jump_phase = 0;
						_p.anim_state = _p.moving ? "walk" : "idle";
						_p.image_index = 0;
						self.draw_player(_p); // ya redibuja con el estado final, mismo frame
						return;
					}
					break;
			}

			self.draw_anim_frame(jump_spr, floor(clamp(_p.image_index, 0, jump_frame_count - 1)), _p, visual_scale);
			return;
		}
		// ----------- ATACAR -------
		
		if (_p.anim_state == "attack") {
			var atk_spr = self.get_player_anim_sprite("attack");
			var atk_frame_count = sprite_get_number(atk_spr);

			self.draw_anim_frame(atk_spr, floor(_p.image_index), _p, visual_scale);

			_p.image_index += anim_speed;
			if (_p.image_index >= atk_frame_count) {

				if (!_p.grounded) {
					_p.anim_state = "jump";
					_p.jump_phase = 2;
					_p.image_index = 7;
				}
				else {
					_p.anim_state = _p.moving ? "walk" : "idle";
					_p.jump_phase = 0;
					_p.image_index = 0;
				}
			}
			return;
		}
		
		// ---------------- TRANSICION CAMINAR <-> IDLE ----------------
		// se reproduce al derecho al ir de "walk" a "idle", e invertida al ir de "idle" a "walk"
		if (_p.anim_state == "trans") {
			var trans_spr = self.get_player_anim_sprite("trans");
			var trans_frame_count = sprite_get_number(trans_spr);

			var frame_to_draw = _p.trans_reverse
				? (trans_frame_count - 1 - floor(_p.image_index))
				: floor(_p.image_index);

			self.draw_anim_frame(trans_spr, clamp(frame_to_draw, 0, trans_frame_count - 1), _p, visual_scale);

			_p.image_index += anim_speed;
			if (_p.image_index >= trans_frame_count) {
				_p.anim_state = _p.moving ? "walk" : "idle";
				_p.image_index = 0;
			}
			return;
		}

		// ---------------- IDLE / CAMINAR ----------------
		var new_state = _p.moving ? "walk" : "idle";

		// si cambio entre idle y walk, primero pasamos por la transicion
		if (new_state != _p.anim_state) {
			_p.trans_reverse = (_p.anim_state == "idle"); // idle -> walk se reproduce invertida
			_p.anim_state = "trans";
			_p.image_index = 0;
			self.draw_player(_p); // dibuja ya el primer frame de la transicion
			return;
		}

		var spr = self.get_player_anim_sprite(_p.anim_state);
		var frame_count = sprite_get_number(spr);

		self.draw_anim_frame(spr, floor(_p.image_index), _p, visual_scale);

		_p.image_index += anim_speed;
		if (_p.image_index >= frame_count) _p.image_index -= frame_count;
	}

	function draw_world() {
		for (var i = 0; i < array_length(players); i++) {
			var p = players[i];
			if (!is_undefined(p)) self.draw_player(p);
		}
	}
	
	function draw_debug_hitboxes() {
		if (!config.debug_show_hitboxes) return;

		draw_set_alpha(0.5);

		// Hurtboxes de jugadores (dónde te pueden golpear)
		for (var i = 0; i < array_length(players); i++) {
			var p = players[i];
			if (!is_struct(p) || !p.active || !p.alive) continue;

			var hurt_rect = game.collision.get_sprite_rect(spr_entity_hurtbox, p.x, p.y);
			if (is_struct(hurt_rect)) {
				draw_set_color(c_lime);
				draw_rectangle(hurt_rect.x1, hurt_rect.y1, hurt_rect.x2, hurt_rect.y2, true);
			}

			if (p.attack_hit_flash_timer > 0) {
				p.attack_hit_flash_timer--;
			}

			// Hitbox de ataque: amarillo mientras carga, rojo el flash al conectar
			if (p.anim_state == "attack") {
				var hitbox = self.get_attack_hitbox_rect(p);
				if (is_struct(hitbox)) {
					draw_set_color(p.attack_hit_flash_timer > 0 ? c_red : c_yellow);
					draw_rectangle(hitbox.x1, hitbox.y1, hitbox.x2, hitbox.y2, true);
				}
			}
		}

		// Hurtboxes de tropas
		for (var i = 0; i < array_length(game.troops.items); i++) {
			var troop = game.troops.items[i];
			if (!is_struct(troop) || !troop.active) continue;

			var t_rect = game.collision.get_sprite_rect(spr_entity_hurtbox, troop.x, troop.y);
			if (is_struct(t_rect)) {
				draw_set_color(c_aqua);
				draw_rectangle(t_rect.x1, t_rect.y1, t_rect.x2, t_rect.y2, true);
			}
		}

		// Rects de estructuras (target de ataque)
		for (var i = 0; i < array_length(game.structures.items); i++) {
			var structure = game.structures.items[i];
			if (!is_struct(structure) || !structure.active) continue;

			var s_rect = game.structures.get_structure_target_rect(structure);
			if (is_struct(s_rect)) {
				draw_set_color(c_orange);
				draw_rectangle(s_rect.x1, s_rect.y1, s_rect.x2, s_rect.y2, true);
			}
		}

		draw_set_alpha(1);
		draw_set_color(c_white);
	}

	reset();
}
