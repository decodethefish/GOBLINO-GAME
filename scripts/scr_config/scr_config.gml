function FortinConfig() constructor {
	screen_w = 1920;
	screen_h = 1080;
	max_players = 8;
	cell = 64;

	build_cols = 15;
	build_rows = 14;
	build_w = build_cols * cell;
	build_h = build_rows * cell;

	build_x = (screen_w - build_w) * 0.5;
	build_y = (screen_h - build_h) * 0.5;
	
	grid_gap = cell * 15;
	trap_visual_scale = 0.3;
	
	defender_start_budget = 200;
	goblin_start_budget = 200;
	local_player_id = 0;
	local_team = FortinTeam.DEFENDERS;
	
	player_attack_active_frames = 8; 
	player_max_hp = 120;
	player_attack_damage = 20;
	player_attack_cooldown = 50;
	player_attack_hitbox_offset = 0;
	player_attack_max_targets = 1;
	
	player_jump_buffer_frames = 10;  
	player_coyote_frames = 6;
	
	debug_show_hitboxes = true; 
	
	player_speed = 5.5;
	player_accel = 0.55;
	player_build_speed = 7;
	player_build_accel = 0.35;
	player_build_friction = 0.20;
	player_friction = 0.25;
	player_air_accel = 0.40;
	player_air_friction = 0.10;
	player_gravity = 0.7;
	player_max_fall = 14;
	player_jump_cut_gravity = 2;
	player_jump_speed = 14;
	player_attack_hit_frame = 12;
	
	
	troop_gravity = player_gravity;
	troop_max_fall = player_max_fall;
	
	troop_jump_cells = 1;
	troop_jump_speed = sqrt(2 * troop_gravity * (troop_jump_cells * cell + 16));
	troop_jump_trigger = 10;
	
	path_cost_walk = 1;
	path_cost_jump = 2.5;
	path_cost_drop = 0.5;
	path_break_base = 4;
	path_break_per_hp = 0.05;
	path_rebuild_frames = 8;
	debug_show_paths = false;
	
	color_background = make_color_rgb(141, 157, 198);
	color_grid = make_color_rgb(103, 101, 157);
	color_grid_select = make_color_rgb(45, 31, 114);
	grid_line_width = 2;
	grid_select_line_width = 3;

	network_port = 6510;
	network_join_host = "127.0.0.1";
	
	net_send_interval = 2;      // 30 Hz (1 para 60 Hz)
	net_extrapolate_max = 6;    // frames máximos de predicción
	net_smooth = 0.6;           // más alto = más pegado al objetivo

	color_player_host = make_color_rgb(56, 168, 254);
	color_player_pool = [
		make_color_rgb(255, 47, 98),
		make_color_rgb(71, 244, 93),
		make_color_rgb(255, 222, 69),
		make_color_rgb(255, 150, 60),
		make_color_rgb(180, 90, 255),
		make_color_rgb(90, 240, 220),
		make_color_rgb(255, 255, 255),
	];
}