function DebuffSystem(_game) constructor {

	game = _game;
	defs = {};

	function register(_id, _duration_s, _tick_s, _damage) {
		defs[$ _id] = {
			debuff_id: _id,
			duration: room_speed * _duration_s,
			tick: room_speed * _tick_s,
			damage: _damage,
		};
	}

	function is_player(_e) {
		return variable_struct_exists(_e, "player_id");
	}

	function is_alive(_e) {
		if (self.is_player(_e)) return _e.active && _e.alive;
		return _e.active;
	}

	function damage(_e, _amount) {
		if (_amount <= 0) return false;
		if (!self.is_alive(_e)) return false;

		if (self.is_player(_e)) return game.players.damage_player(_e, _amount);
		return game.troops.damage_troop(_e, _amount);
	}

	function apply(_e, _debuff_id) {
		var def = defs[$ _debuff_id];

		if (is_undefined(def)) return false;
		if (!self.is_alive(_e)) return false;

		if (!variable_struct_exists(_e, "debuffs")) _e.debuffs = {};

		if (variable_struct_exists(_e.debuffs, _debuff_id)) {
			_e.debuffs[$ _debuff_id].left = def.duration;
		}
		else {
			_e.debuffs[$ _debuff_id] = { left: def.duration, timer: def.tick };
		}

		return true;
	}

	function clear(_e) {
		_e.debuffs = {};
	}

	function tick_entity(_e) {
		if (!variable_struct_exists(_e, "debuffs")) return;

		if (!self.is_alive(_e)) {
			_e.debuffs = {};
			return;
		}

		var keys = variable_struct_get_names(_e.debuffs);

		for (var i = 0; i < array_length(keys); i++) {
			var key = keys[i];
			var d = _e.debuffs[$ key];
			var def = defs[$ key];

			d.left -= 1;
			d.timer -= 1;

			if (d.timer <= 0) {
				d.timer = def.tick;
				self.damage(_e, def.damage);
			}

			if (d.left <= 0) variable_struct_remove(_e.debuffs, key);
		}
	}

	function update() {
		var p = game.players.get_local_player();
		if (is_struct(p)) self.tick_entity(p);

		// Las tropas las simula solo el host
		if (!game.troops.is_authority()) return;

		for (var i = 0; i < array_length(game.troops.items); i++) {
			var t = game.troops.items[i];
			if (!is_struct(t)) continue;

			self.tick_entity(t);
		}
	}

	// ---- DEBUFFS ----  (id, duración s, cada cuántos s hace daño, daño por tick)
	self.register("poison", 5, 1, 2);
	// self.register("fire", 3, 0.5, 4);
}
