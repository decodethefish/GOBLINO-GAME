if (is_undefined(global.Game)) exit;
if (global.Game.state != FortinState.BUILD) exit;

var local_team = global.Game.players.get_player_team(global.Game.config.local_player_id);
var is_goblin_team = local_team == FortinTeam.GOBLINS;

if (is_goblin_team) {
	if (global.Game.build.selected_tool == BuildTool.WALL
	|| global.Game.build.selected_tool == BuildTool.STAIR
	|| global.Game.build.selected_tool == BuildTool.TOWER
	|| global.Game.build.selected_tool == BuildTool.VENOM
	|| global.Game.build.selected_tool == BuildTool.SPIKES) {
		global.Game.build.select_tool(BuildTool.NONE);
	}
}
else if (global.Game.build.selected_tool == BuildTool.SOLDIER
|| global.Game.build.selected_tool == BuildTool.SNIPER
|| global.Game.build.selected_tool == BuildTool.ENGINEER) {
	global.Game.build.select_tool(BuildTool.NONE);
}

var total_w = 0;

if (is_goblin_team) {
	total_w = soldier_button_w + sniper_button_w + engineer_button_w + delete_button_w + button_gap * 3;
	soldier_button_x = global.Game.config.screen_w * 0.5 - total_w * 0.5;
	sniper_button_x = soldier_button_x + soldier_button_w + button_gap;
	engineer_button_x = sniper_button_x + sniper_button_w + button_gap;
	delete_button_x = engineer_button_x + engineer_button_w + button_gap;
}
else {
	total_w = wall_button_w + stair_button_w + tower_button_w + venom_button_w + spike_button_w + delete_button_w + button_gap * 5;
	wall_button_x = global.Game.config.screen_w * 0.5 - total_w * 0.5;
	stair_button_x = wall_button_x + wall_button_w + button_gap;
	tower_button_x = stair_button_x + stair_button_w + button_gap;
	venom_button_x = tower_button_x + tower_button_w + button_gap;
	spike_button_x = venom_button_x + venom_button_w + button_gap;
	delete_button_x = spike_button_x + spike_button_w + button_gap;
}

var mx = device_mouse_x_to_gui(0);
var my = device_mouse_y_to_gui(0);

var inside_wall = mx >= wall_button_x && mx <= wall_button_x + wall_button_w
	&& my >= button_y && my <= button_y + wall_button_h;

var inside_stair = mx >= stair_button_x && mx <= stair_button_x + stair_button_w
	&& my >= button_y && my <= button_y + stair_button_h;

var inside_tower = mx >= tower_button_x && mx <= tower_button_x + tower_button_w
	&& my >= button_y && my <= button_y + tower_button_h;

var inside_soldier = mx >= soldier_button_x && mx <= soldier_button_x + soldier_button_w
	&& my >= button_y && my <= button_y + soldier_button_h;

var inside_sniper = mx >= sniper_button_x && mx <= sniper_button_x + sniper_button_w
	&& my >= button_y && my <= button_y + sniper_button_h;

var inside_engineer = mx >= engineer_button_x && mx <= engineer_button_x + engineer_button_w
	&& my >= button_y && my <= button_y + engineer_button_h;

var inside_delete = mx >= delete_button_x && mx <= delete_button_x + delete_button_w
	&& my >= button_y && my <= button_y + delete_button_h;

var inside_venom = mx >= venom_button_x && mx <= venom_button_x + venom_button_w
	&& my >= button_y && my <= button_y + venom_button_h;

var inside_spike = mx >= spike_button_x && mx <= spike_button_x + spike_button_w
	&& my >= button_y && my <= button_y + spike_button_h;

if (mouse_check_button_pressed(mb_left)) {
	if (!is_goblin_team && inside_wall) {
		global.Game.ui.mouse_consumed = true;
		global.Game.build.select_tool(global.Game.build.selected_tool == BuildTool.WALL ? BuildTool.NONE : BuildTool.WALL);
	}

	if (!is_goblin_team && inside_stair) {
		global.Game.ui.mouse_consumed = true;
		global.Game.build.select_tool(global.Game.build.selected_tool == BuildTool.STAIR ? BuildTool.NONE : BuildTool.STAIR);
	}

	if (!is_goblin_team && inside_tower) {
		global.Game.ui.mouse_consumed = true;
		global.Game.build.select_tool(global.Game.build.selected_tool == BuildTool.TOWER ? BuildTool.NONE : BuildTool.TOWER);
	}
	
	if (!is_goblin_team && inside_venom) {
		global.Game.ui.mouse_consumed = true;
		global.Game.build.select_tool(global.Game.build.selected_tool == BuildTool.VENOM ? BuildTool.NONE : BuildTool.VENOM);
	}

	if (!is_goblin_team && inside_spike) {
		global.Game.ui.mouse_consumed = true;
		global.Game.build.select_tool(global.Game.build.selected_tool == BuildTool.SPIKES ? BuildTool.NONE : BuildTool.SPIKES);
	}
	
	if (is_goblin_team && inside_soldier) {
		global.Game.ui.mouse_consumed = true;
		global.Game.build.select_tool(global.Game.build.selected_tool == BuildTool.SOLDIER ? BuildTool.NONE : BuildTool.SOLDIER);
	}

	if (is_goblin_team && inside_sniper) {
		global.Game.ui.mouse_consumed = true;
		global.Game.build.select_tool(global.Game.build.selected_tool == BuildTool.SNIPER ? BuildTool.NONE : BuildTool.SNIPER);
	}

	if (is_goblin_team && inside_engineer) {
		global.Game.ui.mouse_consumed = true;
		global.Game.build.select_tool(global.Game.build.selected_tool == BuildTool.ENGINEER ? BuildTool.NONE : BuildTool.ENGINEER);
	}

	if (inside_delete) {
		global.Game.ui.mouse_consumed = true;
		global.Game.build.select_tool(global.Game.build.selected_tool == BuildTool.DELETE ? BuildTool.NONE : BuildTool.DELETE);
	}
}
