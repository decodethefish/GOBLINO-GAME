function NetworkSystem(_game) constructor {
	game = _game;
	config = game.config;

	is_host = false;
	is_connected = false;
	local_player_id = config.local_player_id;

	server_socket = -1;
	client_socket = -1;
	state_send_timer = 0;

	clients = [];
	recv_state = ds_map_create();
	status_text = "Selecciona HOST o UNIRSE";

	function make_client(_socket, _player_id) {
		return {
			socket: _socket,
			player_id: _player_id,
		};
	}

	function find_client_by_socket(_socket) {
		for (var i = 0; i < array_length(clients); i++) {
			var c = clients[i];
			if (!is_struct(c)) continue;
			if (c.socket == _socket) return c;
		}

		return undefined;
	}

	function send_packet(_socket, _message) {
		if (_socket < 0) return false;

		var text = json_stringify(_message);
		var text_len = string_byte_length(text);

		var buff = buffer_create(4 + text_len + 1, buffer_fixed, 1);

		buffer_write(buff, buffer_u32, text_len);   // prefijo: cuántos bytes vienen
		buffer_write(buff, buffer_string, text);    // el mensaje en sí

		network_send_packet(_socket, buff, buffer_tell(buff));
		buffer_delete(buff);

		return true;
	}

	function broadcast_packet(_message, _except_socket = -1) {
		for (var i = 0; i < array_length(clients); i++) {
			var c = clients[i];
			if (!is_struct(c)) continue;
			if (c.socket == _except_socket) continue;

			self.send_packet(c.socket, _message);
		}

		return true;
	}

	function broadcast_budget() {
		if (!is_host) return false;

		return self.broadcast_packet({
			msg: FortinNetMsg.BUDGET_UPDATE,
			defender_budget: game.budget.defender_budget,
			goblin_budget: game.budget.goblin_budget,
		});
	}

	function send_to_host(_message) {
		if (is_host) return false;
		return self.send_packet(client_socket, _message);
	}

	function host_local() {
		if (server_socket >= 0) {
			network_destroy(server_socket);
		}

		is_host = true;
		is_connected = true;
		local_player_id = 0;
		config.local_player_id = 0;

		clients = [];

		server_socket = network_create_server(network_socket_tcp, config.network_port, config.max_players - 1);

		if (server_socket < 0) {
			is_host = false;
			is_connected = false;
			status_text = "No se pudo crear HOST";
			return false;
		}

		status_text = "HOST LAN listo";
		game.start_team_select();
		game.players.set_player_active(0, true);

		return true;
	}

	function join_local(_ip = undefined) {
		if (client_socket >= 0) {
			network_destroy(client_socket);
			client_socket = -1;
		}

		var ip = is_undefined(_ip) ? config.network_join_host : _ip;

		// network_connect BLOQUEA hasta conectar o agotar este tiempo (ms).
		// Sin esto, una IP equivocada congela el juego ~20 s.
		network_set_config(network_config_connect_timeout, 4000);

		is_host = false;
		is_connected = false;

		client_socket = network_create_socket(network_socket_tcp);
		var result = network_connect(client_socket, ip, config.network_port);

		if (result < 0) {
			network_destroy(client_socket);
			client_socket = -1;
			status_text = "No se pudo conectar a " + ip;
			return false;
		}

		config.network_join_host = ip;
		status_text = "Conectado, esperando asignacion...";

		self.send_to_host({
			msg: FortinNetMsg.JOIN,
		});

		return true;
	}

	function send_known_world_to(_socket) {
		for (var i = 0; i < array_length(game.structures.items); i++) {
			var s = game.structures.items[i];
			if (!is_struct(s)) continue;
			if (!s.active) continue;

			self.send_packet(_socket, {
				msg: FortinNetMsg.BUILD_STRUCTURE,
				structure_id: s.structure_id,
				build_id: s.build_id,
				col: s.col,
				row: s.row,
				owner_id: s.owner_id,
				facing: s.facing,
				height_segments: s.height_segments,
			});
		}

		for (var p_i = 0; p_i < array_length(game.players.players); p_i++) {
			var p = game.players.players[p_i];
			if (!is_struct(p)) continue;
			if (!p.active) continue;

			self.send_packet(_socket, {
				msg: FortinNetMsg.PLAYER_STATE,
				player_id: p.player_id,
				x: p.x,
				y: p.y,
				hsp: p.hsp,
				vsp: p.vsp,
				grounded: p.grounded,
				facing: p.facing,
			});
			
			self.send_packet(_socket, {
				msg: FortinNetMsg.TEAM_CHANGE,
				player_id: p.player_id,
				team: p.team,
			});
		}
	}

	function get_free_player_id() {
		for (var pid = 1; pid < config.max_players; pid++) {
			var used = false;

			for (var i = 0; i < array_length(clients); i++) {
				if (is_struct(clients[i]) && clients[i].player_id == pid) {
					used = true;
					break;
				}
			}

			if (!used) return pid;
		}

		return -1;
	}

	function free_recv_state(_socket) {
		if (!ds_map_exists(recv_state, _socket)) return;

		buffer_delete(recv_state[? _socket].buffer);
		ds_map_delete(recv_state, _socket);
	}

	// HOST: un cliente se cayó -> limpiar su slot y avisar a los demás
	function host_remove_client(_socket) {
		var c = self.find_client_by_socket(_socket);

		self.free_recv_state(_socket);

		if (!is_struct(c)) return false;

		var kept = [];

		for (var i = 0; i < array_length(clients); i++) {
			if (is_struct(clients[i]) && clients[i].socket != _socket) {
				array_push(kept, clients[i]);
			}
		}

		clients = kept;

		game.players.set_player_active(c.player_id, false);

		self.broadcast_packet({
			msg: FortinNetMsg.PLAYER_LEFT,
			player_id: c.player_id,
		});

		status_text = "Jugador " + string(c.player_id) + " se desconecto";
		return true;
	}

	// CLIENTE: se cayó el host
	function client_lost_host() {
		if (client_socket >= 0) {
			self.free_recv_state(client_socket);
			network_destroy(client_socket);
			client_socket = -1;
		}

		is_connected = false;
		status_text = "Se perdio la conexion con el host";
	}

	function broadcast_troop_snapshot(_troops, _structures, _vault_hp) {
		if (!is_host) return false;

		return self.broadcast_packet({
			msg: FortinNetMsg.TROOP_SNAPSHOT,
			t: _troops,
			s: _structures,
			v: _vault_hp,
		});
	}

	function host_accept_client(_socket) {
		if (game.state != FortinState.LOBBY
		&& game.state != FortinState.TEAM_SELECT) {

			self.send_packet(_socket, {
				msg: FortinNetMsg.JOIN_DENIED,
			});

			network_destroy(_socket);
			status_text = "Se rechazo una conexion";
			return false;
		}
		
		var player_id = self.get_free_player_id();

		if (player_id < 0) {
			self.send_packet(_socket, {
				msg: FortinNetMsg.JOIN_DENIED,
				reason: "full",
			});

			network_destroy(_socket);
			status_text = "Partida llena";
			return false;
		}

		array_push(clients, self.make_client(_socket, player_id));

		game.players.set_player_active(player_id, true);
		self.broadcast_team_change(player_id, game.players.get_player(player_id).team);
		
		self.send_packet(_socket, {
			msg: FortinNetMsg.ASSIGN,
			player_id: player_id,
		});

		self.send_known_world_to(_socket);

		self.broadcast_packet({
			msg: FortinNetMsg.PLAYER_STATE,
			player_id: player_id,
			x: game.players.get_player(player_id).x,
			y: game.players.get_player(player_id).y,
			hsp: 0,
			vsp: 0,
			grounded: false,
			facing: 1,
		}, _socket);

		status_text = "Jugador " + string(player_id) + " conectado";
		return true;
	}

	function client_apply_assign(_player_id) {
		local_player_id = clamp(_player_id, 0, config.max_players - 1);
		config.local_player_id = local_player_id;

		is_connected = true;
		status_text = "Conectado como jugador " + string(local_player_id);

		game.start_team_select();

		game.players.set_player_active(0, true);
		game.players.set_player_active(local_player_id, true);

		return true;
	}

	function request_build_structure(_build_id, _col, _row, _build_data = undefined) {
		if (!is_connected && !is_host) {
			status_text = "Primero crea o unete a una partida";
			return false;
		}

		if (is_host) {
			return game.build.host_place_structure(_build_id, _col, _row, local_player_id, _build_data);
		}

		var msg_data = {
			msg: FortinNetMsg.BUILD_REQUEST,
			build_id: _build_id,
			col: _col,
			row: _row,
		};

		if (is_struct(_build_data)) {
			msg_data.facing = _build_data.facing;
			msg_data.height_segments = _build_data.height_segments;
		}

		return self.send_to_host(msg_data);
	}

	function request_delete_structure(_structure_id) {
		if (!is_connected && !is_host) {
			status_text = "Primero crea o unete a una partida";
			return false;
		}

		if (is_host) {
			return game.build.host_delete_structure(_structure_id, local_player_id);
		}

		return self.send_to_host({
			msg: FortinNetMsg.DELETE_REQUEST,
			structure_id: _structure_id,
		});
	}

	function request_team_change(_team) {
	if (!is_connected && !is_host) {
		status_text = "Primero crea o unete a una partida";
		return false;
	}

	if (is_host) {
		game.players.set_player_team(local_player_id, _team);
		self.broadcast_team_change(local_player_id, _team);
		return true;
	}

	return self.send_to_host({
		msg: FortinNetMsg.TEAM_CHANGE_REQUEST,
		team: _team,
	});
}

	function broadcast_structure(_structure) {
		if (!is_host) return false;
		if (!is_struct(_structure)) return false;

		return self.broadcast_packet({
			msg: FortinNetMsg.BUILD_STRUCTURE,
			structure_id: _structure.structure_id,
			build_id: _structure.build_id,
			col: _structure.col,
			row: _structure.row,
			owner_id: _structure.owner_id,
			facing: _structure.facing,
			height_segments: _structure.height_segments,
		});
	}

	function broadcast_structure_delete(_structure_id) {
		if (!is_host) return false;

		return self.broadcast_packet({
			msg: FortinNetMsg.DELETE_STRUCTURE,
			structure_id: _structure_id,
		});
	}

	function broadcast_team_change(_player_id, _team) {
	if (!is_host) return false;

	return self.broadcast_packet({
		msg: FortinNetMsg.TEAM_CHANGE,
		player_id: _player_id,
		team: _team,
	});
}

	function broadcast_start_build() {
		if (!is_host) return false;

		return self.broadcast_packet({
			msg: FortinNetMsg.START_BUILD,
		});
	}

	function broadcast_start_battle() {
	if (!is_host) return false;

	return self.broadcast_packet({
		msg: FortinNetMsg.START_BATTLE,
	});
}

	function broadcast_battle_end(_winner_team, _defender_base_budget, _goblin_base_budget) {
		if (!is_host) return false;

		return self.broadcast_packet({
			msg: FortinNetMsg.BATTLE_END,
			winner_team: _winner_team,
			defender_base_budget: _defender_base_budget,
			goblin_base_budget: _goblin_base_budget,
		});
	}

	function send_ready_for_build() {
		if (is_host) return false;
		return self.send_to_host({
			msg: FortinNetMsg.READY_FOR_BUILD,
		});
	}

	function send_local_player_state() {
		if (game.state != FortinState.BUILD
		&& game.state != FortinState.BATTLE) return false;

		var p = game.players.get_local_player();
		if (!is_struct(p)) return false;
		if (!p.active) return false;

		state_send_timer--;
		if (state_send_timer > 0) return false;
		state_send_timer = config.net_send_interval;

		var in_build = (game.state == FortinState.BUILD);

		var msg = {
			msg: FortinNetMsg.PLAYER_STATE,
			player_id: local_player_id,
			x: round(p.x * 10) / 10,
			y: round(p.y * 10) / 10,
			hsp: round((in_build ? p.build_hsp : p.hsp) * 100) / 100,
			vsp: round((in_build ? p.build_vsp : p.vsp) * 100) / 100,
			grounded: p.grounded,
			facing: p.facing,
			moving: p.moving,
			atk: p.atk_seq,
			jmp: p.jmp_seq,
			lean: round(p.fly_lean_angle * 10) / 10,
		};

		if (is_host) {
			self.broadcast_packet(msg);
			return true;
		}

		return self.send_to_host(msg);
	}

	function send_player_damage(_player_id, _hp, _alive) {
		var msg = {
			msg: FortinNetMsg.PLAYER_DAMAGE,
			player_id: _player_id,
			hp: _hp,
			alive: _alive,
		};

		if (is_host) {
			self.broadcast_packet(msg);
			return true;
		}

		return self.send_to_host(msg);
	}

	function handle_message(_socket, _data) {
	if (!is_struct(_data)) return false;
	if (!variable_struct_exists(_data, "msg")) return false;

	var msg = _data.msg;
	
	// HOST
	
	if (is_host) {
		if (msg == FortinNetMsg.JOIN) {
			return self.host_accept_client(_socket);
		}

		var c = self.find_client_by_socket(_socket);
		if (!is_struct(c)) return false;

		if (msg == FortinNetMsg.TEAM_CHANGE_REQUEST) {
			game.players.set_player_team(c.player_id, _data.team);
			self.broadcast_team_change(c.player_id, _data.team);
			return true;
		}

		if (msg == FortinNetMsg.PLAYER_STATE) {
			game.players.apply_player_state(c.player_id, _data);

			_data.player_id = c.player_id;
			self.broadcast_packet(_data, _socket);
			return true;
		}
		
		if (msg == FortinNetMsg.PLAYER_DAMAGE) {
			game.players.apply_player_damage(_data.player_id, _data.hp, _data.alive);
			self.broadcast_packet(_data, _socket);
			return true;
		}

		if (msg == FortinNetMsg.DAMAGE_STRUCTURE) {
			var atk_s = game.players.get_player(c.player_id);
			if (!is_struct(atk_s) || !atk_s.alive) return false;

			return game.structures.damage_structure(_data.structure_id, atk_s.attack_damage);
		}

		if (msg == FortinNetMsg.DAMAGE_TROOP) {
			var atk_t = game.players.get_player(c.player_id);
			if (!is_struct(atk_t) || !atk_t.alive) return false;

			return game.troops.damage_troop(game.troops.get_troop_by_sid(_data.sid), atk_t.attack_damage);
		}

		if (msg == FortinNetMsg.BUILD_REQUEST) {
			var request_build_data = {
				facing: variable_struct_exists(_data, "facing") ? _data.facing : 1,
				height_segments: variable_struct_exists(_data, "height_segments") ? _data.height_segments : 1,
			};

			return game.build.host_place_structure(
				_data.build_id,
				_data.col,
				_data.row,
				c.player_id,
				request_build_data
			);
		}

		if (msg == FortinNetMsg.DELETE_REQUEST) {
			return game.build.host_delete_structure(_data.structure_id, c.player_id);
		}
			
		if (msg == FortinNetMsg.READY_FOR_BUILD) {
			game.mark_ready(c.player_id);

			if (game.all_ready()) {
				game.start_build();
				self.broadcast_start_build();
			}

			return true;
		}
			
		return false;
	}
	
	// CLIENTE
	
	if (msg == FortinNetMsg.JOIN_DENIED) {

		status_text = (variable_struct_exists(_data, "reason") && _data.reason == "full")
			? "Partida llena"
			: "La partida ya esta en curso";

		if (client_socket >= 0) {
			network_destroy(client_socket);
			client_socket = -1;
		}

		is_connected = false;

		return true;
	}
	
	if (msg == FortinNetMsg.ASSIGN) {
		return self.client_apply_assign(_data.player_id);
	}

	if (msg == FortinNetMsg.TEAM_CHANGE) {
		return game.players.set_player_team(
			_data.player_id,
			_data.team
		);
	}
	
	if (msg == FortinNetMsg.BUDGET_UPDATE) {

		game.budget.defender_budget = _data.defender_budget;
		game.budget.goblin_budget = _data.goblin_budget;

		return true;
	}	
	
	if (msg == FortinNetMsg.START_BUILD) {
		game.start_build();
		return true;
	}

	if (msg == FortinNetMsg.START_BATTLE) {
		game.start_battle();
		return true;
	}
		
	if (msg == FortinNetMsg.BATTLE_END) {
		game.budget.defender_base_budget = _data.defender_base_budget;
		game.budget.goblin_base_budget = _data.goblin_base_budget;
		game.start_results(_data.winner_team);
		return true;
	}

	if (msg == FortinNetMsg.PLAYER_STATE) {
		if (_data.player_id == local_player_id) return true;

		return game.players.apply_player_state(_data.player_id, _data);
	}
	
	if (msg == FortinNetMsg.PLAYER_DAMAGE) {
		return game.players.apply_player_damage(_data.player_id, _data.hp, _data.alive);
	}

	if (msg == FortinNetMsg.TROOP_SNAPSHOT) {
		game.troops.apply_snapshot(_data);
		return true;
	}

	if (msg == FortinNetMsg.PLAYER_LEFT) {
		return game.players.set_player_active(_data.player_id, false);
	}

	if (msg == FortinNetMsg.BUILD_STRUCTURE) {
		var build_data = {
			facing: variable_struct_exists(_data, "facing") ? _data.facing : 1,
			height_segments: variable_struct_exists(_data, "height_segments") ? _data.height_segments : 1,
		};

		return is_struct(game.build.place_structure_from_network(
			_data.structure_id,
			_data.build_id,
			_data.col,
			_data.row,
			_data.owner_id,
			build_data
		));
	}

	if (msg == FortinNetMsg.DELETE_STRUCTURE) {
		return game.structures.destroy_structure(_data.structure_id);
	}

	return false;
}

	function get_async_socket(_async_load) {
		if (ds_map_exists(_async_load, "socket")) {
			return _async_load[? "socket"];
		}

		if (ds_map_exists(_async_load, "id")) {
			return _async_load[? "id"];
		}

		return -1;
	}

	function get_recv_state(_socket) {
		if (!ds_map_exists(recv_state, _socket)) {
			ds_map_add(recv_state, _socket, {
				buffer: buffer_create(256, buffer_grow, 1),
				length: 0,
			});
		}
		return recv_state[? _socket];
	}

	function consume_from_recv_state(_state, _amount) {
		var remaining = _state.length - _amount;
		var new_buffer = buffer_create(max(256, remaining), buffer_grow, 1);

		if (remaining > 0) {
			buffer_copy(_state.buffer, _amount, remaining, new_buffer, 0);
		}

		buffer_delete(_state.buffer);
		_state.buffer = new_buffer;
		_state.length = remaining;
	}

	function feed_socket_data(_socket, _src_buffer, _size) {
		var state = self.get_recv_state(_socket);

		if (buffer_get_size(state.buffer) < state.length + _size) {
			buffer_resize(state.buffer, (state.length + _size) * 2);
		}

		buffer_copy(_src_buffer, 0, _size, state.buffer, state.length);
		state.length += _size;

		// puede haber MAS de un mensaje completo esperando — los procesamos todos
		while (state.length >= 4) {

			var msg_len = buffer_peek(state.buffer, 0, buffer_u32);
			var total_needed = 4 + msg_len + 1;

			if (state.length < total_needed) break; // mensaje incompleto, esperamos mas bytes

			buffer_seek(state.buffer, buffer_seek_start, 4);
			var text = buffer_read(state.buffer, buffer_string);

			self.consume_from_recv_state(state, total_needed);

			var data = is_string(text) ? json_parse(text) : undefined;
			self.handle_message(_socket, data);
		}
	}

	function on_async(_async_load) {
		var ev_type = _async_load[? "type"];

		if (ev_type == network_type_connect) {
			if (!is_host) {
				status_text = "Conectado, esperando asignacion...";

				self.send_to_host({
					msg: FortinNetMsg.JOIN,
				});
			}

			return;
		}

		if (ev_type == network_type_disconnect) {
			var dc_socket = self.get_async_socket(_async_load);

			if (is_host) self.host_remove_client(dc_socket);
			else self.client_lost_host();

			return;
		}

		if (ev_type != network_type_data) return;

		var socket_id = self.get_async_socket(_async_load);
		var buff = _async_load[? "buffer"];
		var size = _async_load[? "size"];

		self.feed_socket_data(socket_id, buff, size);
	}

	function update() {
		// Reservado para heartbeats/reintentos. El envio de estado ocurre desde PlayerSystem.
	}

	function destroy() {
		if (server_socket >= 0) network_destroy(server_socket);
		if (client_socket >= 0) network_destroy(client_socket);

		server_socket = -1;
		client_socket = -1;
		clients = [];

		var key = ds_map_find_first(recv_state);
		while (!is_undefined(key)) {
			buffer_delete(recv_state[? key].buffer);
			key = ds_map_find_next(recv_state, key);
		}
		ds_map_clear(recv_state);
	}
		
}
