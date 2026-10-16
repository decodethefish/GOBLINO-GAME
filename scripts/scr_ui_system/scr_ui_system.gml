function UISystem(_game) constructor {
	game = _game;
	mouse_consumed = false;

	button_w = 260;
	button_h = 72;
	button_gap = 32;
	
	peek_button_w = sprite_get_width(spr_button_peek);
	peek_button_h = sprite_get_height(spr_button_peek);

	host_rect = {
		x1: game.config.screen_w * 0.5 - button_w - button_gap * 0.5,
		y1: game.config.screen_h * 0.5,
		x2: game.config.screen_w * 0.5 - button_gap * 0.5,
		y2: game.config.screen_h * 0.5 + button_h,
	};

	join_rect = {
		x1: game.config.screen_w * 0.5 + button_gap * 0.5,
		y1: game.config.screen_h * 0.5,
		x2: game.config.screen_w * 0.5 + button_w + button_gap * 0.5,
		y2: game.config.screen_h * 0.5 + button_h,
	};

	defenders_rect = {
		x1: game.config.screen_w * 0.5 - 160,
		y1: 320,
		x2: game.config.screen_w * 0.5 + 160,
		y2: 390,
	};

	goblins_rect = {
		x1: game.config.screen_w * 0.5 - 160,
		y1: 420,
		x2: game.config.screen_w * 0.5 + 160,
		y2: 490,
	};

	start_rect = {
		x1: game.config.screen_w * 0.5 - 160,
		y1: 620,
		x2: game.config.screen_w * 0.5 + 160,
		y2: 690,
	};

	battle_test_rect = {
		x1: 24,
		y1: 120,
		x2: 324,
		y2: 180,
	};
		
	ready_rect = {
		x1: game.config.screen_w * 0.5 - 160,
		y1: 620,
		x2: game.config.screen_w * 0.5 + 160,
		y2: 690,
	};

	ip_rect = {
		x1: game.config.screen_w * 0.5 - button_w - button_gap * 0.5,
		y1: host_rect.y2 + 24,
		x2: game.config.screen_w * 0.5 + button_w + button_gap * 0.5,
		y2: host_rect.y2 + 24 + 56,
	};

	ip_focused = false;

	// Última IP usada (persistida en disco)
	ini_open("fortin.ini");
	ip_text = ini_read_string("net", "last_ip", game.config.network_join_host);
	ini_close();

	last_state = FortinState.LOBBY;
	ready_clicked = false;

	function try_join() {
		if (string_length(ip_text) < 7) {
			game.network.status_text = "Escribe la IP del host";
			return false;
		}

		if (!game.network.join_local(ip_text)) return false;

		ini_open("fortin.ini");
		ini_write_string("net", "last_ip", ip_text);
		ini_close();

		return true;
	}

	function point_in_rect(_x, _y, _r) {
		return _x >= _r.x1 && _x <= _r.x2 && _y >= _r.y1 && _y <= _r.y2;
	};
		
	function get_peek_rect() {
	    var local_team = game.players.get_player_team(game.config.local_player_id);
	    var on_left = (local_team == FortinTeam.GOBLINS);

	    var x1 = on_left ? 24 : (game.config.screen_w - 24 - peek_button_w);

	    return {
	        x1: x1,
	        y1: 24,
	        x2: x1 + peek_button_w,
	        y2: 24 + peek_button_h,
	    };
	}

	function update() {
		mouse_consumed = false;
		
	if (last_state != game.state) {
		ready_clicked = false;
		last_state = game.state;
	}

	if (game.state == FortinState.RESULTS) {

		var mx = device_mouse_x_to_gui(0);
		var my = device_mouse_y_to_gui(0);

		if (!ready_clicked
		&& mouse_check_button_pressed(mb_left)
		&& self.point_in_rect(mx, my, ready_rect)) {

			ready_clicked = true;

			if (!game.network.is_connected) {
				game.start_build();
			}
			else if (game.network.is_host) {
				game.mark_ready(game.network.local_player_id);

				if (game.all_ready()) {
					game.start_build();
					game.network.broadcast_start_build();
				}
			}
			else {
				game.network.send_ready_for_build();
			}
		}

		return;
	}

		if (game.state == FortinState.TEAM_SELECT) {

		var mx = device_mouse_x_to_gui(0);
		var my = device_mouse_y_to_gui(0);

			if (mouse_check_button_pressed(mb_left)) {

				if (self.point_in_rect(mx, my, defenders_rect)) {
					game.config.local_team = FortinTeam.DEFENDERS;
					game.network.request_team_change(FortinTeam.DEFENDERS);
				}

				if (self.point_in_rect(mx, my, goblins_rect)) {
					game.config.local_team = FortinTeam.GOBLINS;
					game.network.request_team_change(FortinTeam.GOBLINS);
				}

				if (game.network.is_host && self.point_in_rect(mx, my, start_rect)) {
					game.start_build();
					game.network.broadcast_budget();
					game.network.broadcast_start_build();
				}
			}

			return;
		}

		var mx = device_mouse_x_to_gui(0);
		var my = device_mouse_y_to_gui(0);

		if (game.state == FortinState.BUILD) {
			if (mouse_check_button_pressed(mb_left)
			&& (!game.network.is_connected || game.network.is_host)
			&& self.point_in_rect(mx, my, battle_test_rect)) {
				mouse_consumed = true;
				game.request_start_battle();
			}
			
			if (mouse_check_button_pressed(mb_left)
			&& self.point_in_rect(mx, my, self.get_peek_rect())) {
			    mouse_consumed = true;
			    game.world.toggle_peek();
			}

			return;
		}

		if (game.state != FortinState.LOBBY) return;

		if (mouse_check_button_pressed(mb_left)) {
			var clicked_ip = self.point_in_rect(mx, my, ip_rect);

			if (clicked_ip && !ip_focused) keyboard_string = ip_text;

			ip_focused = clicked_ip;
			if (clicked_ip) mouse_consumed = true;
		}

		if (ip_focused) {
			if (keyboard_check(vk_control) && keyboard_check_pressed(ord("V")) && clipboard_has_text()) {
				keyboard_string = clipboard_get_text();
			}

			// Solo dígitos y puntos, máximo 15 caracteres
			var clean = "";

			for (var ci = 1; ci <= string_length(keyboard_string); ci++) {
				var ch = string_char_at(keyboard_string, ci);
				if (string_pos(ch, "0123456789.") > 0) clean += ch;
			}

			clean = string_copy(clean, 1, 15);
			keyboard_string = clean;
			ip_text = clean;

			if (keyboard_check_pressed(vk_enter)) self.try_join();
		}

		if (mouse_check_button_pressed(mb_left)) {
			if (self.point_in_rect(mx, my, host_rect)) {
				mouse_consumed = true;
				game.network.host_local();
			}

			if (self.point_in_rect(mx, my, join_rect)) {
				mouse_consumed = true;
				self.try_join();
			}
		}
	};

	function draw_menu_button(_rect, _text) {
		var mx = device_mouse_x_to_gui(0);
		var my = device_mouse_y_to_gui(0);
		var hover = self.point_in_rect(mx, my, _rect);

		draw_set_color(hover ? c_white : make_color_rgb(180, 180, 180));
		draw_rectangle(_rect.x1, _rect.y1, _rect.x2, _rect.y2, false);

		draw_set_halign(fa_center);
		draw_set_valign(fa_middle);
		draw_set_color(hover ? c_black : c_white);
		draw_text((_rect.x1 + _rect.x2) * 0.5, (_rect.y1 + _rect.y2) * 0.5, _text);

		draw_set_halign(fa_left);
		draw_set_valign(fa_top);
		draw_set_color(c_white);
	};

	function draw_ip_box() {
		draw_set_font(fnt_sub);
		draw_set_halign(fa_center);
		draw_set_valign(fa_middle);

		draw_set_color(ip_focused ? c_white : make_color_rgb(180, 180, 180));
		draw_rectangle(ip_rect.x1, ip_rect.y1, ip_rect.x2, ip_rect.y2, false);

		var shown = ip_text;

		if (ip_focused && ((current_time div 500) mod 2 == 0)) shown += "|";
		if (ip_text == "" && !ip_focused) shown = "IP del host (ej: 192.168.1.23)";

		draw_set_color(c_black);
		draw_text((ip_rect.x1 + ip_rect.x2) * 0.5, (ip_rect.y1 + ip_rect.y2) * 0.5, shown);

		draw_set_halign(fa_left);
		draw_set_valign(fa_top);
		draw_set_color(c_white);
	};

	function draw_gui() {

		if (game.state == FortinState.TEAM_SELECT) {

	draw_set_halign(fa_center);
	draw_set_valign(fa_middle);
	draw_set_color(c_white);
	draw_set_font(fnt_title);
	
	draw_text(game.config.screen_w * 0.5, 140, "ELIGE TU EQUIPO");
	
	self.draw_menu_button(defenders_rect, "DEFENSORES");
	self.draw_menu_button(goblins_rect, "GOBLINS");

	if (game.network.is_host) {
		self.draw_menu_button(start_rect, "INICIAR PARTIDA");
	}

	draw_text(
		game.config.screen_w * 0.5,
		560,
		(game.config.local_team == FortinTeam.DEFENDERS)
			? "Equipo actual: DEFENSORES"
			: "Equipo actual: GOBLINS"
	);

	return;
}

		if (game.state == FortinState.RESULTS) {

			var local_team = game.players.get_player_team(game.config.local_player_id);
			var won = (local_team == game.battle_winner);

			draw_set_halign(fa_center);
			draw_set_valign(fa_middle);
			draw_set_color(won ? c_lime : c_red);
			draw_set_font(fnt_title);

			draw_text(
				game.config.screen_w * 0.5,
				game.config.screen_h * 0.35,
				won ? "GANASTE" : "PERDISTE"
			);

			draw_set_color(c_white);
			draw_set_font(fnt_sub);
			draw_text(
				game.config.screen_w * 0.5,
				game.config.screen_h * 0.35 + 60,
				"Presupuesto aumentado +30%"
			);

			self.draw_menu_button(ready_rect, "LISTO");

			draw_set_halign(fa_left);
			draw_set_valign(fa_top);
			draw_set_color(c_white);

			return;
		}

		if (game.state == FortinState.BUILD) {
			
			draw_set_halign(fa_left);
			draw_set_valign(fa_top);
			draw_set_color(c_white);
			draw_set_font(fnt_title);

			draw_text(
				24,
				24,
				"Presupuesto: " + string(game.budget.get_budget(game.config.local_team))
			);

			var seconds_left = ceil(game.build_timer / room_speed);
			var minutes_left = seconds_left div 60;
			var seconds_part = seconds_left mod 60;
			var seconds_text = string(seconds_part);

			if (seconds_part < 10) {
				seconds_text = "0" + seconds_text;
			}

			draw_text(
				24,
				72,
				"Batalla en: " + string(minutes_left) + ":" + seconds_text
			);
			
			var local_team = game.players.get_player_team(game.config.local_player_id);
			var flip = (local_team == FortinTeam.GOBLINS) ? -1 : 1;
			var subimg = game.world.is_peeking ? 1 : 0;

			var peek_rect = self.get_peek_rect();
			var draw_x = (flip < 0) ? peek_rect.x2 : peek_rect.x1;

			draw_set_color(c_white);
			draw_sprite_ext(spr_button_peek, subimg, draw_x, peek_rect.y1, flip, 1, 0, c_white, 1);
			
			if (!game.network.is_connected || game.network.is_host) {
				self.draw_menu_button(battle_test_rect, "BATALLA TEST");
			}

			return;
		}

		if (game.state == FortinState.BATTLE) {

			draw_set_halign(fa_left);
			draw_set_valign(fa_top);
			draw_set_color(c_white);
			draw_set_font(fnt_title);
			var local_player = game.players.get_local_player();

			if (is_struct(local_player) && !local_player.alive) {
				draw_set_halign(fa_center);
				draw_set_valign(fa_middle);
				draw_set_color(c_red);
				draw_set_font(fnt_title);
				draw_text(game.config.screen_w * 0.5, 80, "HAS MUERTO");

				draw_set_halign(fa_left);
				draw_set_valign(fa_top);
				draw_set_color(c_white);
			}
			
			draw_text(
				24,
				24,
				"Tropas: " + string(game.troops.count())
			);
			
			var seconds_left = ceil(game.battle.battle_timer / room_speed);
			var minutes_left = seconds_left div 60;
			var seconds_part = seconds_left mod 60;
			var seconds_text = string(seconds_part);

			if (seconds_part < 10) {
				seconds_text = "0" + seconds_text;
			}

			draw_set_halign(fa_center);
			draw_set_valign(fa_top);
			draw_text(
				game.config.screen_w * 0.5,
				24,
				string(minutes_left) + ":" + seconds_text
			);

			draw_set_halign(fa_left);

			return;
		}

		if (game.state != FortinState.LOBBY) return;

		draw_set_alpha(1);
		draw_set_color(c_black);
		draw_rectangle(0, 0, game.config.screen_w, game.config.screen_h, false);
		draw_set_font(fnt_title);		
		
		draw_set_halign(fa_center);
		draw_set_valign(fa_middle);
		draw_set_color(c_white);
		draw_text(game.config.screen_w * 0.5, game.config.screen_h * 0.35, "FORTIN");

		draw_set_halign(fa_left);
		draw_set_valign(fa_top);

		self.draw_menu_button(host_rect, "HOST");
		self.draw_menu_button(join_rect, "UNIRSE");
		self.draw_ip_box();

		draw_set_halign(fa_center);
		draw_set_valign(fa_top);
		draw_set_color(c_white);
		draw_set_font(fnt_sub);
		draw_text(game.config.screen_w * 0.5, ip_rect.y2 + 36, game.network.status_text);

		draw_set_halign(fa_left);
		draw_set_valign(fa_top);
	};
		
}
