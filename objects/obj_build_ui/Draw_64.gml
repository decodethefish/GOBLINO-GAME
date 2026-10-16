if (is_undefined(global.Game)) exit;
if (global.Game.state != FortinState.BUILD) exit;

var local_team = global.Game.players.get_player_team(global.Game.config.local_player_id);
var is_goblin_team = local_team == FortinTeam.GOBLINS;

var wall_selected = global.Game.build.selected_tool == BuildTool.WALL;
var stair_selected = global.Game.build.selected_tool == BuildTool.STAIR;
var tower_selected = global.Game.build.selected_tool == BuildTool.TOWER;
var soldier_selected = global.Game.build.selected_tool == BuildTool.SOLDIER;
var sniper_selected = global.Game.build.selected_tool == BuildTool.SNIPER;
var engineer_selected = global.Game.build.selected_tool == BuildTool.ENGINEER;
var delete_selected = global.Game.build.selected_tool == BuildTool.DELETE;
var venom_selected = global.Game.build.selected_tool == BuildTool.VENOM;
var spike_selected = global.Game.build.selected_tool == BuildTool.SPIKES;


var wall_frame = wall_selected ? min(1, sprite_get_number(wall_button_sprite) - 1) : 0;
var stair_frame = stair_selected ? min(1, sprite_get_number(stair_button_sprite) - 1) : 0;
var tower_frame = tower_selected ? min(1, sprite_get_number(tower_button_sprite) - 1) : 0;
var soldier_frame = soldier_selected ? min(1, sprite_get_number(soldier_button_sprite) - 1) : 0;
var sniper_frame = sniper_selected ? min(1, sprite_get_number(sniper_button_sprite) - 1) : 0;
var engineer_frame = engineer_selected ? min(1, sprite_get_number(engineer_button_sprite) - 1) : 0;
var delete_frame = delete_selected ? min(1, sprite_get_number(delete_button_sprite) - 1) : 0;
var venom_frame = venom_selected ? min(1, sprite_get_number(venom_button_sprite) - 1) : 0;
var spike_frame = spike_selected ? min(1, sprite_get_number(spike_button_sprite) - 1) : 0;
if (is_goblin_team) {
	draw_sprite(soldier_button_sprite, soldier_frame, soldier_button_x, button_y);
	draw_sprite(sniper_button_sprite, sniper_frame, sniper_button_x, button_y);
	draw_sprite(engineer_button_sprite, engineer_frame, engineer_button_x, button_y);
}
else {
	draw_sprite(wall_button_sprite, wall_frame, wall_button_x, button_y);
	draw_sprite(stair_button_sprite, stair_frame, stair_button_x, button_y);
	draw_sprite(tower_button_sprite, tower_frame, tower_button_x, button_y);
	draw_sprite(venom_button_sprite, venom_frame, venom_button_x, button_y);
	draw_sprite(spike_button_sprite, spike_frame, spike_button_x, button_y);
}

draw_sprite(delete_button_sprite, delete_frame, delete_button_x, button_y);

draw_set_alpha(1);
draw_set_color(c_white);
