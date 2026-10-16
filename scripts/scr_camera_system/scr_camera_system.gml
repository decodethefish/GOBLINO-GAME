function CameraSystem(_game) constructor {
	game = _game;
	config = game.config;

	cam = -1;

	x = config.screen_w * 0.5;
	y = config.screen_h * 0.5;
	target_x = x;
	target_y = y;

	zoom = 1;
	target_zoom = 1;
	min_zoom = 1;
	max_zoom = 4;

	zoom_speed = 1.15;
	zoom_lerp = 0.18;
	move_lerp = 0.12;

	grid_margin = config.cell * 1.25;

	dragging = false;
	drag_last_x = 0;
	drag_last_y = 0;

	setup = function() {
		display_set_gui_size(config.screen_w, config.screen_h);

		view_enabled = true;
		view_visible[0] = true;

		if (cam == -1) {
			cam = camera_create_view(0, 0, config.screen_w, config.screen_h, 0, noone, -1, -1, -1, -1);
		}

		view_camera[0] = cam;
		view_xport[0] = 0;
		view_yport[0] = 0;
		view_wport[0] = config.screen_w;
		view_hport[0] = config.screen_h;
	};

	function get_active_bounds() {
	    var grid = game.world.get_view_grid(); // antes: get_active_grid()
	    return game.world.get_bounds(grid);
	};

	get_grid_center = function() {
		var b = self.get_active_bounds();

		return {
			x: (b.x1 + b.x2) * 0.5,
			y: (b.y1 + b.y2) * 0.5,
		};
	};

	get_fit_zoom = function() {
		var b = self.get_active_bounds();

		var content_w = (b.x2 - b.x1) + grid_margin * 2;
		var content_h = (b.y2 - b.y1) + grid_margin * 2;

		var fit_x = config.screen_w / content_w;
		var fit_y = config.screen_h / content_h;

		return min(fit_x, fit_y);
	};

	function get_follow_point() {
		
	    if (game.world.is_peeking) {
	        return self.get_grid_center();
	    }
		
		var p = game.players.get_local_player();

		if (!is_undefined(p)
		&& p.active
		&& (game.state == FortinState.BUILD
		|| game.state == FortinState.BATTLE)) {
			var player_mid_y = p.y
				+ ((sprite_get_bbox_top(spr_player) + sprite_get_bbox_bottom(spr_player) + 1) * 0.5)
				- sprite_get_yoffset(spr_player);

			return {
				x: p.x,
				y: player_mid_y,
			};
		}

		return self.get_grid_center();
	};

	clamp_axis = function(_value, _min, _max, _view_size) {
		var content_min = _min - grid_margin;
		var content_max = _max + grid_margin;
		var content_size = content_max - content_min;

		if (_view_size >= content_size) {
			return (content_min + content_max) * 0.5;
		}

		var min_center = content_min + _view_size * 0.5;
		var max_center = content_max - _view_size * 0.5;

		return clamp(_value, min_center, max_center);
	};

	apply_limits = function() {
		var b = self.get_active_bounds();

		var view_w = config.screen_w / target_zoom;
		var view_h = config.screen_h / target_zoom;

		target_x = self.clamp_axis(target_x, b.x1, b.x2, view_w);
		target_y = self.clamp_axis(target_y, b.y1, b.y2, view_h);
	};

	reset_to_grid = function() {
		var center = self.get_grid_center();
		var fit_zoom = self.get_fit_zoom();

		target_zoom = clamp(fit_zoom, min_zoom, max_zoom);
		zoom = target_zoom;

		target_x = center.x;
		target_y = center.y;
		x = target_x;
		y = target_y;
	};

	update_zoom = function() {
		if (mouse_wheel_up()) {
			target_zoom *= zoom_speed;
		}

		if (mouse_wheel_down()) {
			target_zoom /= zoom_speed;
		}

		var fit_zoom = self.get_fit_zoom();
		min_zoom = clamp(fit_zoom, 0.1, max_zoom);

		target_zoom = clamp(target_zoom, min_zoom, max_zoom);
	};

	update_drag = function() {
		var mx = device_mouse_x_to_gui(0);
		var my = device_mouse_y_to_gui(0);

		if (mouse_check_button_pressed(mb_middle)) {
			dragging = true;
			drag_last_x = mx;
			drag_last_y = my;
		}

		if (mouse_check_button_released(mb_middle)) {
			dragging = false;
		}

		if (!dragging) return;

		var dx = mx - drag_last_x;
		var dy = my - drag_last_y;

		target_x -= dx / zoom;
		target_y -= dy / zoom;

		drag_last_x = mx;
		drag_last_y = my;
	};

	update_follow = function() {
		if (dragging) return;

		var fit_zoom = self.get_fit_zoom();

		if (target_zoom <= fit_zoom + 0.01) {
			var center = self.get_grid_center();
			target_x = center.x;
			target_y = center.y;
			return;
		}

		var follow = self.get_follow_point();
		target_x = follow.x;
		target_y = follow.y;
	};

	update = function() {
		if (cam == -1) self.setup();

		self.update_zoom();
		self.update_drag();
		self.update_follow();
		self.apply_limits();

		zoom = lerp(zoom, target_zoom, zoom_lerp);
		x = lerp(x, target_x, move_lerp);
		y = lerp(y, target_y, move_lerp);

		var view_w = config.screen_w / zoom;
		var view_h = config.screen_h / zoom;

		camera_set_view_size(cam, view_w, view_h);
		camera_set_view_pos(cam, x - view_w * 0.5, y - view_h * 0.5);
	};

	destroy = function() {
		if (cam != -1) {
			camera_destroy(cam);
			cam = -1;
		}
	};

	self.setup();
	self.reset_to_grid();
}
