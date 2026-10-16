function FortinData() constructor {
	structure_defs = {};
	unit_defs = {};

	function register_structure(
		_build_id,
		_name,
		_type,
		_class_id,
		_variant,
		_price,
		_visual_sprite,
		_collision_sprite,
		_size_x,
		_size_y,
		_top_visual_sprite = undefined,
		_top_offset_x = 0,
		_top_offset_y = 0,
		_occupied_offsets = undefined,
		_solid = true,
		_allowed_team = FortinTeam.DEFENDERS,
		_preview_sprite = undefined,
		_anchor_x = 0,
		_anchor_y = 0,
		_unit_id = undefined,
		_hp = 200,
		_trap = undefined,
	) {
		var occupied_offsets = _occupied_offsets;
		var preview_sprite = _preview_sprite;
		
		if (is_undefined(preview_sprite)) {
			preview_sprite = _visual_sprite;
		}

		if (is_undefined(occupied_offsets)) {
			occupied_offsets = [];
			for (var xx = 0; xx < _size_x; xx++) {
				for (var yy = 0; yy < _size_y; yy++) {
					array_push(occupied_offsets, {
						dx: xx,
						dy: yy,
					});
				}
			}
		}

		structure_defs[$ _build_id] = {
			build_id: _build_id,
			name: _name,
			type: _type,
			class_id: _class_id,
			variant: _variant,
			price: _price,
			visual_sprite: _visual_sprite,
			collision_sprite: _collision_sprite,
			top_visual_sprite: _top_visual_sprite,
			top_offset_x: _top_offset_x,
			top_offset_y: _top_offset_y,
			occupied_offsets: occupied_offsets,
			size_x: _size_x,
			size_y: _size_y,
			can_rotate: false,
			solid: _solid,
			allowed_team: _allowed_team,
			preview_sprite: preview_sprite,
			anchor_x: _anchor_x,
			anchor_y: _anchor_y,
			unit_id: _unit_id,
			hp: _hp,
			trap: _trap,
		};
	};
	
	function register_unit(
		_unit_id,
		_name,
		_hp,
		_move_speed,
		_attack_damage,
		_attack_range,
		_attack_cooldown,
		_idle_sprite,
		_walk_sprite,
		_attack_sprite = undefined,
		_projectile = undefined,
		_collision_sprite  = undefined,
		_movement_type = TroopMovementType.GROUND,
	) {

		unit_defs[$ _unit_id] = {

			unit_id: _unit_id,

			name: _name,

			hp: _hp,

			move_speed: _move_speed,

			attack_damage: _attack_damage,

			attack_range: _attack_range,

			attack_cooldown: _attack_cooldown,

			idle_sprite: _idle_sprite,

			walk_sprite: _walk_sprite,

			attack_sprite: _attack_sprite,

			projectile: _projectile,
			
			collision_sprite: _collision_sprite,
			
			movement_type: _movement_type,
			

		};

	}

	function get_structure_def(_build_id) {
		if (is_undefined(structure_defs[$ _build_id])) return undefined;
		return structure_defs[$ _build_id];
	};

	function get_unit_def(_unit_id) {

		if (is_undefined(unit_defs[$ _unit_id]))
			return undefined;

		return unit_defs[$ _unit_id];

	}

	self.register_structure(
		"MA1",
		"Muro A1",
		ConstructionType.WALL,
		ConstructionClass.A,
		1,
		5,
		spr_obj_wall_1,
		spr_obj_wall_col,
		1,
		1
	);

	self.register_structure(
		"SA1",
		"Escalera A1",
		ConstructionType.LADDER,
		ConstructionClass.A,
		1,
		3,
		spr_obj_stair_left,
		spr_obj_stair_col_left,
		1,
		1
	);

	self.register_structure(
		"TA1",
		"Torre A1",
		ConstructionType.TOWER,
		ConstructionClass.A,
		1,
		10,
		spr_obj_tower_1,
		undefined,
		2,
		2,
		spr_obj_tower_top_1,
		0,
		-1,
		[
			{ dx: 0, dy: -1 },
			{ dx: 1, dy: -1 },
			{ dx: 0, dy: 0 },
			{ dx: 1, dy: 0 },
			{ dx: 0, dy: 1 },
			{ dx: 1, dy: 1 },
		],
		false
	);

	self.register_structure(
		"PA1", "Pinchos A1", ConstructionType.TRAP, ConstructionClass.A, 1, 8,
		spr_obj_spikes, spr_obj_trap_col, 1, 1,
		undefined, 0, 0, undefined,
		false, FortinTeam.DEFENDERS, undefined, 0, 0, undefined,
		60,
		{ damage: 15, tick: room_speed * 0.5, debuff: undefined }
	);

	self.register_structure(
		"VA1", "Veneno A1", ConstructionType.TRAP, ConstructionClass.A, 1, 12,
		spr_obj_venom, spr_obj_trap_col, 1, 1,
		undefined, 0, 0, undefined,
		false, FortinTeam.DEFENDERS, undefined, 0, 0, undefined,
		60,
		{ damage: 7, tick: room_speed * 0.5, debuff: "poison" }
	);

	self.register_structure(
		"GS1",
		"Soldado Goblin",
		ConstructionType.SOLDIER,
		ConstructionClass.C,
		1,
		5,
		spr_goblin_idle_sol,
		undefined,
		1,
		1,
		undefined,
		0,
		0,
		undefined,
		false,
		FortinTeam.GOBLINS,
		spr_obj_gob_sol,
		0.5,
		1,
		"GOBLIN_SOLDIER",
		100
	);

	self.register_structure(
		"GS2",
		"Sniper Goblin",
		ConstructionType.SOLDIER,
		ConstructionClass.C,
		1,
		10,
		spr_goblin_idle_snipe,
		undefined,
		1,
		1,
		undefined,
		0,
		0,
		undefined,
		false,
		FortinTeam.GOBLINS,
		spr_obj_gob_snipe,
		0.5,
		1,
		"GOBLIN_SNIPER",
		100
	);

	self.register_structure(
		"GS3",
		"Ingeniero Goblin",
		ConstructionType.SOLDIER,
		ConstructionClass.C,
		1,
		20,
		spr_goblin_idle_engin,
		undefined,
		1,
		1,
		undefined,
		0,
		0,
		undefined,
		false,
		FortinTeam.GOBLINS,
		spr_obj_gob_snipe_1,
		0.5,
		1,
		"GOBLIN_ENGINEER",
		100
	);


	// UNIDADES
	
	self.register_unit(
		"GOBLIN_SOLDIER",
		"Soldado Goblin",
		100,
		2.0,
		10,
		34,
		room_speed * 0.8,
		spr_goblin_idle_sol,
		spr_goblin_walk_sol,
		spr_goblin_attack_sol,
		undefined,
		spr_troop_col,
	);

	self.register_unit(
		"GOBLIN_SNIPER",
		"Sniper Goblin",
		70,
		1.8,
		30,
		330,
		room_speed * 2,
		spr_goblin_idle_snipe,
		spr_goblin_walk_snipe,
		spr_goblin_attack_snipe,
		undefined,	
		spr_troop_col,
	);

	self.register_unit(
		"GOBLIN_ENGINEER",
		"Ingeniero Goblin",
		120,
		3.3,
		0,
		48,
		room_speed,
		spr_goblin_idle_engin,
		spr_goblin_walk_engin,
		undefined,
		undefined,		
		spr_troop_col,
	);
}
