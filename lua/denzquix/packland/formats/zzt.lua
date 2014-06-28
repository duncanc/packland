
local R = require 'denzquix.packland.reader'

local format = {}

local reader_proto = {}

function format.dbinit(db)

	assert(db:exec [[

		CREATE TABLE IF NOT EXISTS zzt_world (
			dbid INTEGER PRIMARY KEY,
			name TEXT,
			torch_cycles_left INTEGER,
			energy_cycles_left INTEGER,
			time_passed INTEGER,
			is_saved_game INTEGER
		);

		CREATE TABLE IF NOT EXISTS zzt_flag (
			dbid INTEGER PRIMARY KEY,
			world_dbid INTEGER,
			idx INTEGER,
			name TEXT,

			FOREIGN KEY (world_dbid) REFERENCES zzt_world(dbid)
		);

		CREATE TABLE IF NOT EXISTS zzt_board (
			dbid INTEGER PRIMARY KEY,
			world_dbid INTEGER,
			idx INTEGER,
			name TEXT,
			width INTEGER,
			height INTEGER,
			tile_type_data BLOB,
			tile_colour_data BLOB,

			FOREIGN KEY (world_dbid) REFERENCES zzt_world(dbid)
		);

		CREATE TABLE IF NOT EXISTS zzt_oop_script (
			dbid INTEGER PRIMARY KEY,
			source_code TEXT
		);

		CREATE TABLE IF NOT EXISTS zzt_board_element (
			dbid INTEGER PRIMARY KEY,
			board_dbid INTEGER,
			name TEXT,
			idx INTEGER,
			x INTEGER,
			y INTEGER,
			step_x INTEGER,
			step_y INTEGER,
			cycle INTEGER,
			param1 INTEGER,
			param2 INTEGER,
			param3 INTEGER,
			script_dbid INTEGER,

			FOREIGN KEY (board_dbid) REFERENCES zzt_board(dbid),
			FOREIGN KEY (script_dbid) REFERENCES zzt_oop_script(dbid)
		);

		CREATE TABLE IF NOT EXISTS zzt_player_state (
			dbid INTEGER PRIMARY KEY,
			world_dbid INTEGER,
			ammo INTEGER,
			gems INTEGER,
			has_blue_key INTEGER,
			has_green_key INTEGER,
			has_cyan_key INTEGER,
			has_red_key INTEGER,
			has_purple_key INTEGER,
			has_yellow_key INTEGER,
			has_white_key INTEGER,
			health INTEGER,
			torches INTEGER,
			board_dbid INTEGER,
			score INTEGER,

			FOREIGN KEY (world_dbid) REFERENCES zzt_world(dbid),
			FOREIGN KEY (board_dbid) REFERENCES zzt_board(dbid)
		);

	]])

end

function format.todb(intype, inpath, db, context)
	local reader = R.fromfile(inpath)

	reader:inject 'bindata'
	reader:inject (reader_proto)

	local world = {}

	local world_type = reader:int16le()

	if world_type == -2 then
		world.is_super = true
	elseif world_type ~= -1 then
		error 'unknown world type'
	end

	reader:world(world)

	format.dbinit(db)

	do
		local exec_add_world = assert(db:prepare [[

			INSERT INTO zzt_world (
				name,
				torch_cycles_left,
				energy_cycles_left,
				time_passed,
				is_saved_game
			)
			VALUES (
				:name,
				:torch_cycles_left,
				:energy_cycles_left,
				:time_passed,
				:is_saved_game
			)

		]])

		assert( exec_add_world:bind_text(':name', world.name) )
		assert( exec_add_world:bind_int(':torch_cycles_left', world.torch_cycles_left) )
		assert( exec_add_world:bind_int(':energy_cycles_left', world.energy_cycles_left) )
		assert( exec_add_world:bind_int(':time_passed', world.time_passed) )
		assert( exec_add_world:bind_bool(':is_saved_game', world.is_saved_game) )

		assert( assert( exec_add_world:step() ) == 'done' )
		assert( exec_add_world:finalize() )
	end

	local world_dbid = db:last_insert_rowid()

	do
		local exec_add_flag = assert(db:prepare [[

			INSERT INTO zzt_flag (
				world_dbid,
				idx,
				name
			)
			VALUES (
				:world_dbid,
				:idx,
				:name
			)

		]])

		assert( exec_add_flag:bind_int64(':world_dbid', world_dbid) )

		for _, flag in ipairs(world.flags) do
			assert( exec_add_flag:bind_int(':idx', flag.idx) )
			assert( exec_add_flag:bind_text(':name', flag.name) )

			assert( assert( exec_add_flag:step() ) == 'done' )
			assert( exec_add_flag:reset() )
		end

		assert( exec_add_flag:finalize() )
	end

	local board_dbids = {}

	do
		local exec_add_board = assert(db:prepare [[

			INSERT INTO zzt_board (
				world_dbid,
				idx,
				name,
				width,
				height,
				tile_type_data,
				tile_colour_data
			)
			VALUES (
				:world_dbid,
				:idx,
				:name,
				:width,
				:height,
				:tile_type_data,
				:tile_colour_data
			)

		]])

		assert( exec_add_board:bind_int64(':world_dbid', world_dbid) )

		local exec_add_element = assert(db:prepare [[

			INSERT INTO zzt_board_element (
				board_dbid,
				idx,
				name,
				x,
				y,
				step_x,
				step_y,
				cycle,
				param1,
				param2,
				param3,
				script_dbid
			)
			VALUES (
				:board_dbid,
				:idx,
				:name,
				:x,
				:y,
				:step_x,
				:step_y,
				:cycle,
				:param1,
				:param2,
				:param3,
				:script_dbid
			)

		]])

		local exec_add_script = assert(db:prepare [[

			INSERT INTO zzt_oop_script (
				source_code
			)
			VALUES (
				:source_code
			)

		]])

		local script_dbid_cache = {}
		local function add_script(text)
			local cached = script_dbid_cache[text]
			if cached then
				return cached
			end
			assert( exec_add_script:bind_text(':source_code', text) )
			assert( exec_add_script:step() == 'done' )
			assert( exec_add_script:reset() )
			local dbid = db:last_insert_rowid()
			script_dbid_cache[text] = dbid
			return dbid
		end

		for _, board in ipairs(world.boards) do
			do
				assert( exec_add_board:bind_int(':idx', board.idx) )
				assert( exec_add_board:bind_text(':name', board.name) )
				assert( exec_add_board:bind_int(':width', board.width) )
				assert( exec_add_board:bind_int(':height', board.height) )
				assert( exec_add_board:bind_blob(':tile_type_data', board.tile_type_data) )
				assert( exec_add_board:bind_blob(':tile_colour_data', board.tile_colour_data) )
				assert( assert( exec_add_board:step() ) == 'done' )
				assert( exec_add_board:reset() )
			end

			local board_dbid = db:last_insert_rowid()
			board_dbids[board.idx] = board_dbid

			assert( exec_add_element:bind_int64(':board_dbid', board_dbid) )

			for _, element in ipairs(board.status_elements) do

				if element.source_code then
					assert( exec_add_element:bind_int64(':script_dbid', add_script(element.source_code)) )
					assert( exec_add_element:bind_text(':name', element.source_code:match('^@([^\r\n]+)')) )
				else
					assert( exec_add_element:bind_null(':script_dbid') )
					assert( exec_add_element:bind_null(':name') )
				end

				assert( exec_add_element:bind_int(':idx', element.idx) )
				assert( exec_add_element:bind_int(':x', element.location_x) )
				assert( exec_add_element:bind_int(':y', element.location_y) )
				assert( exec_add_element:bind_int(':step_x', element.step_x) )
				assert( exec_add_element:bind_int(':step_y', element.step_y) )
				assert( exec_add_element:bind_int(':cycle', element.cycle) )
				assert( exec_add_element:bind_int(':param1', element.param1) )
				assert( exec_add_element:bind_int(':param2', element.param2) )
				assert( exec_add_element:bind_int(':param3', element.param3) )

				assert( assert( exec_add_element:step() ) == 'done' )
				assert( exec_add_element:reset() )
			end
		end

		assert( exec_add_board:finalize() )
		assert( exec_add_element:finalize() )
	end

	do
		local exec_add_player = assert(db:prepare [[

			INSERT INTO zzt_player_state (
				world_dbid,
				ammo,
				gems,
				has_blue_key,
				has_green_key,
				has_cyan_key,
				has_red_key,
				has_purple_key,
				has_yellow_key,
				has_white_key,
				health,
				torches,
				board_dbid,
				score
			)
			VALUES (
				:world_dbid,
				:ammo,
				:gems,
				:has_blue_key,
				:has_green_key,
				:has_cyan_key,
				:has_red_key,
				:has_purple_key,
				:has_yellow_key,
				:has_white_key,
				:health,
				:torches,
				:board_dbid,
				:score
			)

		]])

		assert( exec_add_player:bind_int64(':world_dbid', world_dbid) )
		assert( exec_add_player:bind_int(':ammo', world.player.ammo) )
		assert( exec_add_player:bind_int(':gems', world.player.gems) )
		assert( exec_add_player:bind_bool(':has_blue_key', world.player.keys.blue) )
		assert( exec_add_player:bind_bool(':has_green_key', world.player.keys.green) )
		assert( exec_add_player:bind_bool(':has_cyan_key', world.player.keys.cyan) )
		assert( exec_add_player:bind_bool(':has_red_key', world.player.keys.red) )
		assert( exec_add_player:bind_bool(':has_purple_key', world.player.keys.purple) )
		assert( exec_add_player:bind_bool(':has_yellow_key', world.player.keys.yellow) )
		assert( exec_add_player:bind_bool(':has_white_key', world.player.keys.white) )
		assert( exec_add_player:bind_int(':health', world.player.health) )
		assert( exec_add_player:bind_int(':torches', world.player.torches) )
		assert( exec_add_player:bind_int(':score', world.player.score) )
		assert( exec_add_player:bind_int(':board_dbid', board_dbids[ world.player.board_idx ]) )

		assert( assert( exec_add_player:step() ) == 'done' )
		assert( exec_add_player:finalize() )
	end
end

local key_colours = {'blue', 'green', 'cyan', 'red', 'purple', 'yellow', 'white'}

function reader_proto:world(world)
	local board_count = self:int16le()

	world.boards = {}
	-- title board is not included in count, so add 1
	for i = 1, board_count + 1 do
		world.boards[i] = {idx=i-1}
	end

	world.player = {}
	world.player.ammo = self:int16le()
	world.player.gems = self:int16le()
	world.player.keys = {}
	for _, key_colour in ipairs(key_colours) do
		if self:uint8() ~= 0 then
			world.player.keys[key_colour] = true
		end
	end
	world.player.health = self:int16le()
	world.player.board_idx = self:int16le()

	if world.is_super then
		self:super_zzt_world(world)
		self:pos('set', 0x400)
		for _, board in ipairs(world.boards) do
			self:super_zzt_board(board)
		end
	else
		self:zzt_world(world)
		self:pos('set', 0x200)
		for _, board in ipairs(world.boards) do
			self:zzt_board(board)
		end
	end

end

function reader_proto:zzt_world(world)
	world.player.torches = self:int16le()
	world.torch_cycles_left = self:int16le()
	world.energy_cycles_left = self:int16le()
	self:skip(2) -- always 0
	world.player.score = self:int16le()
	world.name = self:len_prefix_string(20)
	world.flags = {}
	for i = 1, 10 do
		world.flags[i] = {idx=i-1, name=self:len_prefix_string(20)}
	end
	world.time_passed = self:int16le()
	self:skip(2) -- runtime memory location of player data
	world.is_saved_game = self:bool8()
end

function reader_proto:super_zzt_world(world)
	self:skip(2) -- always 0
	world.player.score = self:int16le()
	self:skip(2) -- always 0
	world.energy_cycles_left = self:int16le()
	world.name = self:len_prefix_string(20)
	world.flags = {}
	for i = 1, 16 do
		world.flags[i] = {idx=i-1, name=self:len_prefix_string(20)}
	end
	world.time_passed = self:int16le()
	self:skip(2) -- runtime memory location of player data
	world.is_saved_game = self:bool8()
	world.player.stones_of_power = self:int16le()
end

function reader_proto:zzt_board(board)
	local size_bytes = self:int16le()
	board.name = self:len_prefix_string(50)
	board.width = 60
	board.height = 25
	board.tile_type_data, board.tile_colour_data = self:zzt_rle(board.width * board.height)
	board.max_player_shots = self:uint8()
	board.is_dark = self:bool8()
	board.north_board_idx = self:uint8()
	board.south_board_idx = self:uint8()
	board.west_board_idx = self:uint8()
	board.east_board_idx = self:uint8()
	board.restarts_on_zap = self:bool8()
	board.message = self:len_prefix_string(58)
	board.player_enter_x = self:uint8()
	board.player_enter_y = self:uint8()
	board.time_limit_seconds = self:int16le()
	self:skip(16) -- unused

	board.status_elements = {}
	-- add one to include player element
	for i = 1, self:int16le() + 1 do
		local el = {idx=i-1}
		self:status_element(el)
		board.status_elements[i] = el
		self:skip(8) -- padding
		if el.zzt_oop_length then
			el.source_code = self:blob(el.zzt_oop_length)
		end
	end
	for _, el in ipairs(board.status_elements) do
		if el.copy_idx then
			el.source_code = assert(board.status_elements[el.copy_idx+1].source_code)
		end
	end
end

function reader_proto:status_element(el)
	el.location_x = self:uint8()
	el.location_y = self:uint8()
	el.step_x = self:int16le()
	el.step_y = self:int16le()
	el.cycle = self:int16le()
	el.param1 = self:uint8()
	el.param2 = self:uint8()
	el.param3 = self:uint8()
	el.follower_idx = self:int16le()
	el.leader_idx = self:int16le()
	el.under_id = self:uint8()
	el.under_color = self:uint8()
	self:skip(4) -- code pointer
	el.zzt_oop_offset = self:int16le()
	local v = self:int16le()
	if v > 0 then
		el.zzt_oop_length = v
	elseif v < 0 then
		el.copy_idx = -v
	end
end

function reader_proto:super_zzt_board(board)
	local size_bytes = self:int16le()
	board.name = self:len_prefix_string(50)
	board.width = 96
	board.height = 80
	board.tile_type_data, board.tile_colour_data = self:zzt_rle(board.width * board.height)
	board.max_player_shots = self:uint8()
	board.north_board_idx = self:uint8()
	board.south_board_idx = self:uint8()
	board.west_board_idx = self:uint8()
	board.east_board_idx = self:uint8()
	board.restarts_on_zap = self:bool8()
	board.player_enter_x = self:uint8()
	board.player_enter_y = self:uint8()
	-- camera pos not used when loading worlds
	board.camera_x = self:int16le()
	board.camera_y = self:int16le()
	board.time_limit_seconds = self:int16le()
	self:skip(14) -- unused
	board.player_element = {}
	self:status_element(board.player_element)
	board.status_elements = {}
	for i = 1, status_element_count do
		local el = {idx=i-1}
		self:status_element(el)
		board.status_elements[i] = el
		if el.zzt_oop_length then
			el.source_code = self:blob(el.zzt_oop_length)
		end
	end
end

function reader_proto:len_prefix_string(max_length)
	local actual_len = self:uint8()
	return self:blob(max_length):sub(1, actual_len)
end

function reader_proto:zzt_rle(tile_count)
	local tile_type_buf = {}
	local tile_colour_buf = {}
	local total = 0
	repeat
		local count = self:uint8()
		if count == 0 then
			count = 256
		end
		local element = self:blob(1)
		local color = self:blob(1)
		tile_type_buf[#tile_type_buf+1] = string.rep(element, count)
		tile_colour_buf[#tile_colour_buf+1] = string.rep(color, count)
		total = total + count
	until total >= tile_count
	return table.concat(tile_type_buf), table.concat(tile_colour_buf)
end

return format
