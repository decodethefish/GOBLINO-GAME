if (!is_struct(troop))
	exit;

draw_sprite_ext(
	troop.current_sprite,
	floor(troop.image_index),
	x,
	y,
	0.25 * troop.facing,
	0.25,
	0,
	c_white,
	1
);