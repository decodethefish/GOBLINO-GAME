
#macro PATH_INF 1000000

function PathSystem(_game) constructor {

	game = _game;
	config = game.config;

	ready = false;
	dirty = true;
	cooldown = 0;
	build_count = 0;
	last_build_us = 0;

	cols = 0;
	rows = 0;
	cell_count = 0;

	cell_kind = [];
	cell_sid = [];
	cell_facing = [];
	cell_break_cost = [];

	e_from = [];
	e_to = [];
	e_cost = [];
	e_kind = [];
	e_sid = [];
	e_next = [];
	e_count = 0;
	in_head = [];
	goals = [];

	dist = [];
	next_node = [];
	next_edge = [];
	next_sid = [];
	in_heap = [];

	step = {
		valid: false,
		dir: 0,
		jump: false,
		sid: -1,
		edge: PathEdge.NONE,
	};

	heap = ds_priority_create();

	// ---------------------------------------------------------
	// API publica
	// ---------------------------------------------------------

	function mark_dirty() {
		dirty = true;
	}

	function is_ready() {
		return ready;
	}

	function update() {
		if (keyboard_check_pressed(vk_f3)) {
			config.debug_show_paths = !config.debug_show_paths;
		}

		if (game.state != FortinState.BATTLE) {
			ready = false;
			dirty = true;
			return;
		}

		if (cooldown > 0) cooldown--;

		if (dirty && cooldown <= 0) {
			self.rebuild();
		}
	}

	function rebuild() {
		var t0 = get_timer();

		self.build_map();
		self.build_edges();
		self.run_dijkstra();

		dirty = false;
		ready = true;
		cooldown = config.path_rebuild_frames;
		build_count++;
		last_build_us = get_timer() - t0;
	}

	function destroy() {
		ds_priority_destroy(heap);
	}

	// ---------------------------------------------------------
	// Mapa
	// ---------------------------------------------------------

	function allocate(_cols, _rows) {
		cols = _cols;
		rows = _rows;
		cell_count = cols * rows;

		cell_kind = array_create(cell_count, PathCell.AIR);
		cell_sid = array_create(cell_count, -1);
		cell_facing = array_create(cell_count, 1);
		cell_break_cost = array_create(cell_count, PATH_INF);

		var n = cell_count * 2;
		in_head = array_create(n, -1);
		dist = array_create(n, PATH_INF);
		next_node = array_create(n, -1);
		next_edge = array_create(n, PathEdge.NONE);
		next_sid = array_create(n, -1);
		in_heap = array_create(n, false);
	}

	function set_cell(_c, _r, _kind, _sid, _facing, _cost) {
		if (_c < 0 || _c >= cols || _r < 0 || _r >= rows) return;

		var idx = _r * cols + _c;
		cell_kind[idx] = _kind;
		cell_sid[idx] = _sid;
		cell_facing[idx] = _facing;
		cell_break_cost[idx] = _cost;
	}

	function build_map() {
		var world = game.world;
		var grid = world.battle_grid;

		if (cell_count != grid.cols * grid.rows) {
			self.allocate(grid.cols, grid.rows);
		}

		for (var i = 0; i < cell_count; i++) {
			cell_kind[i] = PathCell.AIR;
			cell_sid[i] = -1;
			cell_facing[i] = 1;
			cell_break_cost[i] = PATH_INF;
		}

		// Estructuras solidas (muros y escaleras). Torres y tropas no son solidas: se ignoran.
		var items = game.structures.items;

		for (var i = 0; i < array_length(items); i++) {
			var s = items[i];

			if (!is_struct(s)) continue;
			if (!s.active) continue;

			var def = game.data.get_structure_def(s.build_id);

			if (!is_struct(def)) continue;
			if (!def.solid) continue;

			var sgrid = world.get_grid_for_team(s.team);
			var off_c = round((sgrid.x - grid.x) / config.cell);
			var off_r = round((sgrid.y - grid.y) / config.cell);

			var is_stair = (def.type == ConstructionType.LADDER);
			var facing = game.structures.get_structure_facing(s);
			var cost = config.path_break_base + def.hp * config.path_break_per_hp;

			for (var k = 0; k < array_length(def.occupied_offsets); k++) {
				var off = def.occupied_offsets[k];

				self.set_cell(
					off_c + s.col + off.dx,
					off_r + s.row + off.dy,
					is_stair ? PathCell.STAIR : PathCell.WALL,
					s.structure_id,
					facing,
					cost
				);
			}
		}

		// Vault: no se puede romper, es la meta.
		var vault = world.get_vault();

		if (vault.hp > 0) {
			var vgrid = world.get_grid_for_team(vault.team);
			var voff_c = round((vgrid.x - grid.x) / config.cell);
			var voff_r = round((vgrid.y - grid.y) / config.cell);

			for (var vr = 0; vr < vault.height; vr++) {
				for (var vc = 0; vc < vault.width; vc++) {
					self.set_cell(
						voff_c + vault.col + vc,
						voff_r + vault.row + vr,
						PathCell.VAULT,
						-1,
						1,
						PATH_INF
					);
				}
			}
		}
	}

	function kind_at(_c, _r) {
		if (_c < 0 || _c >= cols || _r < 0 || _r >= rows) return -1;
		return cell_kind[_r * cols + _c];
	}

	function is_solid_kind(_k) {
		return _k == PathCell.WALL || _k == PathCell.VAULT;
	}

	function supported(_c, _r) {
		if (_r >= rows - 1) return true;
		return self.is_solid_kind(cell_kind[(_r + 1) * cols + _c]);
	}

	function standable(_c, _r) {
		return self.kind_at(_c, _r) == PathCell.AIR && self.supported(_c, _r);
	}

	function touches_vault(_c, _r) {
		return self.kind_at(_c - 1, _r) == PathCell.VAULT
			|| self.kind_at(_c + 1, _r) == PathCell.VAULT
			|| self.kind_at(_c, _r - 1) == PathCell.VAULT
			|| self.kind_at(_c, _r + 1) == PathCell.VAULT;
	}

	function landing(_c, _r, _first_air) {
		for (var rr = _r; rr < rows; rr++) {
			var idx = rr * cols + _c;
			var k = cell_kind[idx];
			var first = (rr == _r && _first_air);

			if (!first && k == PathCell.STAIR) return idx;

			if (first || k == PathCell.AIR) {
				if (self.supported(_c, rr)) {
					if (first && k == PathCell.STAIR) return cell_count + idx;
					return idx;
				}
				continue;
			}

			return -1;
		}

		return -1;
	}

	// ---------------------------------------------------------
	// Grafo
	// ---------------------------------------------------------

	function add_edge(_from, _to, _cost, _kind, _sid) {
		e_from[e_count] = _from;
		e_to[e_count] = _to;
		e_cost[e_count] = _cost;
		e_kind[e_count] = _kind;
		e_sid[e_count] = _sid;
		e_next[e_count] = in_head[_to];
		in_head[_to] = e_count;
		e_count++;
	}

	function add_step_edge(_src, _dst, _r) {
		var fall = ((_dst mod cell_count) div cols) - _r;
		var cost = config.path_cost_walk + fall * config.path_cost_drop;

		self.add_edge(_src, _dst, cost, (fall > 0) ? PathEdge.DROP : PathEdge.WALK, -1);
	}

	function air_edges(_c, _r, _src) {
		var jump_cells = config.troop_jump_cells;

		for (var d = -1; d <= 1; d += 2) {
			var nc = _c + d;
			var nk = self.kind_at(nc, _r);

			if (nk == -1) continue;

			var ni = _r * cols + nc;
			var dst = -1;

			if (nk == PathCell.AIR) {
				dst = self.landing(nc, _r, false);
				if (dst >= 0) self.add_step_edge(_src, dst, _r);
			}
			else if (nk == PathCell.STAIR) {
				var f = cell_facing[ni];

				// Solo se sube una escalera entrando por su lado bajo.
				if (d == -f) {
					self.add_edge(_src, ni, config.path_cost_walk, PathEdge.WALK, -1);
				}
				else if (jump_cells >= 1
					&& self.kind_at(_c, _r - 1) == PathCell.AIR
					&& self.kind_at(_c, _r - 2) == PathCell.AIR) {
					self.add_edge(_src, ni, config.path_cost_jump, PathEdge.JUMP, -1);
				}

				dst = self.landing(nc, _r, true);
				if (dst >= 0) self.add_edge(_src, dst, cell_break_cost[ni], PathEdge.BREAK, cell_sid[ni]);
			}
			else if (nk == PathCell.WALL) {
				for (var h = 1; h <= jump_cells; h++) {
					// El arco sube un poco mas que h celdas: necesita techo libre
					// (una celda extra) sobre el origen y sobre el destino.
					if (self.kind_at(_c, _r - h) != PathCell.AIR) break;
					if (self.kind_at(_c, _r - h - 1) != PathCell.AIR) break;
					if (self.kind_at(nc, _r - h) != PathCell.AIR) continue;
					if (self.kind_at(nc, _r - h - 1) != PathCell.AIR) continue;
					if (!self.standable(nc, _r - h)) continue;

					self.add_edge(_src, (_r - h) * cols + nc, config.path_cost_jump + (h - 1), PathEdge.JUMP, -1);
					break;
				}

				dst = self.landing(nc, _r, true);
				if (dst >= 0) self.add_edge(_src, dst, cell_break_cost[ni], PathEdge.BREAK, cell_sid[ni]);
			}
		}
	}

	function stair_edges(_c, _r) {
		var idx = _r * cols + _c;
		var f = cell_facing[idx];

		// Lado bajo (misma fila)
		var lc = _c + f;
		var lk = self.kind_at(lc, _r);
		var dst = -1;

		if (lk == PathCell.AIR) {
			dst = self.landing(lc, _r, false);
			if (dst >= 0) self.add_step_edge(idx, dst, _r);
		}
		else if (lk == PathCell.WALL) {
			dst = self.landing(lc, _r, true);
			if (dst >= 0) {
				var li = _r * cols + lc;
				self.add_edge(idx, dst, cell_break_cost[li], PathEdge.BREAK, cell_sid[li]);
			}
		}

		// Cadena hacia abajo (escalera siguiente, misma orientacion)
		if (self.kind_at(lc, _r + 1) == PathCell.STAIR && cell_facing[(_r + 1) * cols + lc] == f) {
			self.add_edge(idx, (_r + 1) * cols + lc, config.path_cost_walk, PathEdge.WALK, -1);
		}

		// Lado alto (una fila arriba)
		var hc = _c - f;
		var hk = self.kind_at(hc, _r - 1);
		var hi = (_r - 1) * cols + hc;

		if (hk == PathCell.AIR) {
			dst = self.landing(hc, _r - 1, false);
			if (dst >= 0) self.add_step_edge(idx, dst, _r - 1);
		}
		else if (hk == PathCell.STAIR) {
			if (cell_facing[hi] == f) {
				self.add_edge(idx, hi, config.path_cost_walk, PathEdge.WALK, -1);
			}
		}
		else if (hk == PathCell.WALL) {
			dst = self.landing(hc, _r - 1, true);
			if (dst >= 0) self.add_edge(idx, dst, cell_break_cost[hi], PathEdge.BREAK, cell_sid[hi]);
		}
	}

	function build_edges() {
		e_count = 0;
		goals = [];

		for (var n = 0; n < cell_count * 2; n++) {
			in_head[n] = -1;
		}

		for (var r = 0; r < rows; r++) {
			for (var c = 0; c < cols; c++) {
				var idx = r * cols + c;
				var k = cell_kind[idx];

				if (k == PathCell.AIR || k == PathCell.WALL) {
					// Muro = nodo virtual ("como si ya estuviera roto")
					if (!self.supported(c, r)) continue;

					self.air_edges(c, r, idx);

					if (self.touches_vault(c, r)) array_push(goals, idx);
				}
				else if (k == PathCell.STAIR) {
					self.stair_edges(c, r);

					if (self.touches_vault(c, r)) array_push(goals, idx);

					if (self.supported(c, r)) {
						self.air_edges(c, r, cell_count + idx);

						if (self.touches_vault(c, r)) array_push(goals, cell_count + idx);
					}
				}
			}
		}
	}

	function run_dijkstra() {
		var n = cell_count * 2;

		for (var i = 0; i < n; i++) {
			dist[i] = PATH_INF;
			next_node[i] = -1;
			next_edge[i] = PathEdge.NONE;
			next_sid[i] = -1;
			in_heap[i] = false;
		}

		ds_priority_clear(heap);

		for (var g = 0; g < array_length(goals); g++) {
			var goal = goals[g];

			dist[goal] = 0;
			in_heap[goal] = true;
			ds_priority_add(heap, goal, 0);
		}

		while (!ds_priority_empty(heap)) {
			var v = ds_priority_delete_min(heap);
			in_heap[v] = false;

			var e = in_head[v];

			while (e >= 0) {
				var u = e_from[e];
				var nd = dist[v] + e_cost[e];

				if (nd < dist[u]) {
					dist[u] = nd;
					next_node[u] = v;
					next_edge[u] = e_kind[e];
					next_sid[u] = e_sid[e];

					if (in_heap[u]) {
						ds_priority_change_priority(heap, u, nd);
					}
					else {
						ds_priority_add(heap, u, nd);
						in_heap[u] = true;
					}
				}

				e = e_next[e];
			}
		}
	}

	function node_at(_x, _y) {
		var grid = game.world.battle_grid;
		var cell = config.cell;

		var fx = (_x - grid.x) / cell;
		var c = clamp(floor(fx), 0, cols - 1);
		var r = clamp(floor((_y - 1 - grid.y) / cell), 0, rows - 1);
		var idx = r * cols + c;
		var k = cell_kind[idx];

		if (k == PathCell.STAIR) return idx;
		if (k != PathCell.AIR) return -1;

		// Extremo alto de una rampa: los pies quedan en la fila de arriba.
		if (r + 1 < rows && cell_kind[idx + cols] == PathCell.STAIR) return idx + cols;

		// Sin apoyo bajo el centro: puede estar parado en el borde de un muro
		// con el centro por fuera. Probar la columna vecina mas cercana.
		if (!self.supported(c, r)) {
			var first = (fx - floor(fx) < 0.5) ? c - 1 : c + 1;
			var second = (first < c) ? c + 1 : c - 1;

			if (self.standable(first, r)) return r * cols + first;
			if (self.standable(second, r)) return r * cols + second;
		}

		return idx;
	}

	function get_step(_troop) {
		var s = step;

		s.valid = false;
		s.dir = 0;
		s.jump = false;
		s.sid = -1;
		s.edge = PathEdge.NONE;

		if (!ready) return s;

		var node = self.node_at(_troop.x, _troop.y);
		if (node < 0) return s;

		var nxt = next_node[node];
		if (nxt < 0) return s;

		var c = node mod cols;
		var nc = (nxt mod cell_count) mod cols;
		var dir = sign(nc - c);

		if (dir == 0) return s;

		s.valid = true;
		s.dir = dir;
		s.edge = next_edge[node];
		s.sid = next_sid[node];

		// Saltar solo cuando el cuerpo ya esta pegado a la cara del obstaculo.
		if (s.edge == PathEdge.JUMP) {
			var body = game.collision.get_entity_rect(_troop);

			if (is_struct(body)) {
				var grid = game.world.battle_grid;
				var face_x = grid.x + ((dir > 0) ? (c + 1) : c) * config.cell;
				var edge_x = (dir > 0) ? body.x2 : body.x1;

				s.jump = ((face_x - edge_x) * dir <= config.troop_jump_trigger);
			}
		}

		return s;
	}

	// ---------------------------------------------------------
	// Debug (F3)
	// ---------------------------------------------------------

	function draw_debug() {
		if (!config.debug_show_paths) return;
		if (!ready) return;

		var grid = game.world.battle_grid;
		var cell = config.cell;

		for (var r = 0; r < rows; r++) {
			for (var c = 0; c < cols; c++) {
				var idx = r * cols + c;
				var px = grid.x + c * cell;
				var py = grid.y + r * cell;
				var k = cell_kind[idx];

				if (k != PathCell.AIR) {
					draw_set_alpha(0.25);

					if (k == PathCell.WALL) draw_set_color(c_gray);
					else if (k == PathCell.STAIR) draw_set_color(c_orange);
					else draw_set_color(c_purple);

					draw_rectangle(px, py, px + cell, py + cell, false);
				}

				// Los muros son nodos virtuales ("si ya estuvieran rotos"): sin flechas, solo ruido.
				if (k == PathCell.WALL) continue;
				if (next_node[idx] < 0) continue;

				var nn = next_node[idx] mod cell_count;
				var cx = px + cell * 0.5;
				var cy = py + cell * 0.5;
				var tx = grid.x + (nn mod cols) * cell + cell * 0.5;
				var ty = grid.y + (nn div cols) * cell + cell * 0.5;

				switch (next_edge[idx]) {
					case PathEdge.WALK: draw_set_color(c_lime); break;
					case PathEdge.JUMP: draw_set_color(c_yellow); break;
					case PathEdge.DROP: draw_set_color(c_aqua); break;
					case PathEdge.BREAK: draw_set_color(c_red); break;
					default: draw_set_color(c_white); break;
				}

				draw_set_alpha(1);
				draw_arrow(cx, cy, tx, ty, 8);
				draw_text_transformed(px + 3, py + 3, string_format(dist[idx], 1, 1), 0.5, 0.5, 0);
			}
		}

		draw_set_color(c_white);
		draw_text(
			grid.x,
			grid.y - 28,
			"PATH [F3] rebuild: " + string_format(last_build_us / 1000, 1, 2) + " ms | builds: " + string(build_count)
		);

		draw_set_alpha(1);
		draw_set_color(c_white);
	}
}
