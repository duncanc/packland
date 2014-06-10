
local bit = require 'bit'
local R = require 'denzquix.packland.reader'

local format = {}

local reader_proto = {}

function format.dbinit(db)

	assert(db:exec [[

		CREATE TABLE IF NOT EXISTS room (
			dbid INTEGER PRIMARY KEY,
			width INTEGER,
			height INTEGER
		);

		CREATE TABLE IF NOT EXISTS walk_zone (
			dbid INTEGER PRIMARY KEY,

			room_dbid INTEGER NOT NULL,

			idx INTEGER,

			top_y INTEGER,
			bottom_y INTEGER,
			top_left_x INTEGER,
			top_right_x INTEGER,
			bottom_left_x INTEGER,
			bottom_right_x INTEGER,

			FOREIGN KEY (room_dbid) REFERENCES room(dbid)
		);

		CREATE TABLE IF NOT EXISTS walk_zone_link (
			from_zone_dbid INTEGER NOT NULL,
			to_zone_dbid INTEGER NOT NULL,
			next_zone_dbid INTEGER NOT NULL,

			FOREIGN KEY (from_zone_dbid) REFERENCES walk_zone(dbid),
			FOREIGN KEY (to_zone_dbid) REFERENCES walk_zone(dbid),
			FOREIGN KEY (next_zone_dbid) REFERENCES walk_zone(dbid),

			PRIMARY KEY (from_zone_dbid, to_zone_dbid)
		);

	]])

end

function format.todb(intype, inpath, db)
	assert(intype == 'file')
	local reader = assert(R.fromfile(inpath))
	local read_blob = reader.blob
	function reader:blob(...)
		local blob = read_blob(reader, ...)
		if blob == nil then
			return nil
		end
		local buf = {}
		for i = 1, #blob do
			buf[i] = string.char(bit.bxor(0xFF, string.byte(blob, i)))
		end
		return table.concat(buf)
	end
	reader:inject 'bindata'
	reader:inject(reader_proto)

	local lfl = {}
	reader:lfl(lfl)

	format.dbinit(db)

	local room_dbid
	do
		local exec_add_room = assert(db:prepare [[

			INSERT INTO ROOM (width, height)
			VALUES (:width, :height)

		]])

		assert( exec_add_room:bind_int(':width', lfl.width) )
		assert( exec_add_room:bind_int(':height', lfl.height) )

		assert( assert( exec_add_room:step() ) == 'done' )

		assert( exec_add_room:finalize() )

		room_dbid = db:last_insert_rowid()
	end

	local zone_idx_to_dbid = {}

	do
		local exec_add_zone = assert(db:prepare [[

			INSERT INTO walk_zone (
				room_dbid, idx,
				top_y, top_left_x, top_right_x,
				bottom_y, bottom_left_x, bottom_right_x
			)
			VALUES (
				:room_dbid, :idx,
				:top_y, :top_left_x, :top_right_x,
				:bottom_y, :bottom_left_x, :bottom_right_x
			)

		]])

		assert( exec_add_zone:bind_int64(':room_dbid', room_dbid) )

		for _, box in ipairs(lfl.boxes) do
			assert( exec_add_zone:bind_int(':idx', box.idx) )
			assert( exec_add_zone:bind_int(':top_y', box.top_y) )
			assert( exec_add_zone:bind_int(':top_left_x', box.top_left_x) )
			assert( exec_add_zone:bind_int(':top_right_x', box.top_right_x) )
			assert( exec_add_zone:bind_int(':bottom_y', box.top_y) )
			assert( exec_add_zone:bind_int(':bottom_left_x', box.top_left_x) )
			assert( exec_add_zone:bind_int(':bottom_right_x', box.top_right_x) )

			assert( assert( exec_add_zone:step() ) == 'done' )
			assert( exec_add_zone:reset() )

			zone_idx_to_dbid[box.idx] = db:last_insert_rowid()
		end

		assert( exec_add_zone:finalize() )
	end
end

function reader_proto:lfl(lfl)
	local offset_to_something = self:int16le()
	local unknown = self:uint8()
	local unknown = self:uint8()
	lfl.width = self:uint8() * 8
	lfl.height = self:uint8() * 8
	local c64_color_0 = self:uint8()
	local c64_color_1 = self:uint8()
	local c64_color_2 = self:uint8()
	local unknown = self:uint8()
	local offset_to_picture_character_set = self:int16le()
	local offset_to_picture_screen_map = self:int16le()
	local offset_to_picture_c64_color_map = self:int16le()
	local offset_to_picture_walk_behind_mask = self:int16le()
	local offset_to_walk_behind_mask_char_data = self:int16le()
	lfl.objects = {}
	for i = 1, self:uint8() do
		lfl.objects[i] = {idx=i-1}
	end
	local unknown = self:uint8()
	local unknown_bytes_1 = self:uint8()
	local unknown_bytes_2 = self:uint8()
	local unknown_offset = self:int16le()
	local unknown_offset = self:int16le()
	for _, object in ipairs(lfl.objects) do
		object.offset_to_image = self:int16le()
	end
	self:skip(unknown_bytes_1)
	self:skip(unknown_bytes_2)
	lfl.boxes = {}
	for i = 1, self:uint8() do
		lfl.boxes[i] = {idx=i-1}
	end
	for _, box in ipairs(lfl.boxes) do
		box.top_y = self:uint8() * 2 * 8
		box.bottom_y = self:uint8() * 2 * 8
		box.top_left_x = self:uint8() * 8
		box.top_right_x = self:uint8() * 8
		box.bottom_left_x = self:uint8() * 8
		box.bottom_right_x = self:uint8() * 8
		box.unknown_1 = self:uint8()
		box.unknown_2 = self:uint8()
	end
	for _, box in ipairs(lfl.boxes) do
		box.matrix_offset = self:uint8()
	end
end

return format
