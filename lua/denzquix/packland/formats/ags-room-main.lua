
local R = require 'denzquix.packland.reader'

local format = {}

local kRoomVersion_pre114_3   = 3  -- exact version unknown
local kRoomVersion_pre114_4   = 4  -- exact version unknown
local kRoomVersion_pre114_5   = 5  -- exact version unknown
local kRoomVersion_pre114_6   = 6  -- exact version unknown
local kRoomVersion_114        = 8
local kRoomVersion_200_alpha  = 9
local kRoomVersion_200_alpha7 = 10
local kRoomVersion_200_final  = 11
local kRoomVersion_208        = 12
local kRoomVersion_214        = 13
local kRoomVersion_240        = 14
local kRoomVersion_241        = 15
local kRoomVersion_250a       = 16
local kRoomVersion_250b       = 17
local kRoomVersion_251        = 18
local kRoomVersion_253        = 19
local kRoomVersion_255a       = 20
local kRoomVersion_255b       = 21
local kRoomVersion_261        = 22
local kRoomVersion_262        = 23
local kRoomVersion_270        = 24
local kRoomVersion_272        = 25
local kRoomVersion_300a       = 26
local kRoomVersion_300b       = 27
local kRoomVersion_303a       = 28
local kRoomVersion_303b       = 29
local kRoomVersion_Current    = kRoomVersion_303b


function format.dbinit(db)

	assert(db:exec [[

		CREATE TABLE IF NOT EXISTS bitmap (
			dbid INTEGER PRIMARY KEY,
			pixel_format TEXT,
			pixel_data BLOB,
			palette BLOB
		);

		CREATE TABLE IF NOT EXISTS room (
			dbid INTEGER PRIMARY KEY,

			background_image_dbid INTEGER,
			hotspot_map_dbid INTEGER,
			walkbehind_map_dbid INTEGER,
			walkable_map_dbid INTEGER,

			top_edge_y INTEGER,
			bottom_edge_y INTEGER,
			left_edge_x INTEGER,
			right_edge_x INTEGER,

			FOREIGN KEY (background_image_dbid) REFERENCES bitmap(dbid),
			FOREIGN KEY (hotspot_map_dbid) REFERENCES bitmap(dbid),
			FOREIGN KEY (walkbehind_map_dbid) REFERENCES bitmap(dbid),
			FOREIGN KEY (walkable_map_dbid) REFERENCES bitmap(dbid)
		);

		CREATE TABLE IF NOT EXISTS room_walkbehind (
			dbid INTEGER PRIMARY KEY,
			room_dbid INTEGER NOT NULL,
			idx INTEGER,
			baseline INTEGER,
			
			FOREIGN KEY (room_dbid) REFERENCES room(dbid)
		);

		CREATE TABLE IF NOT EXISTS room_object (
			dbid INTEGER PRIMARY KEY,
			room_dbid INTEGER NOT NULL,
			idx INTEGER,

			sprite_idx INTEGER,
			x INTEGER,
			y INTEGER,
			is_visible INTEGER,

			FOREIGN KEY (room_dbid) REFERENCES room(dbid)
		);

		CREATE TABLE IF NOT EXISTS room_hotspot (
			dbid INTEGER PRIMARY KEY,
			room_dbid INTEGER NOT NULL,
			idx INTEGER,

			FOREIGN KEY (room_dbid) REFERENCES room(dbid)
		);

		CREATE TABLE IF NOT EXISTS message (
			dbid INTEGER PRIMARY KEY,
			room_dbid INTEGER,
			idx INTEGER,
			content TEXT,
			continues_to_next INTEGER,
			is_removed_after_timeout INTEGER,
			is_shown_as_speech INTEGER,

			FOREIGN KEY (room_dbid) REFERENCES room(dbid)
		);


	]])

end

local reader_proto = {}

function format.todb(intype, inpath, db, context)
	assert(intype == 'file', 'input must be a file (got ' .. intype .. ')')
	assert(context and tonumber(context.v), 'room format version must be specified (e.g. -v=10)')

	format.dbinit(db)

	local reader = assert(R.fromfile(inpath))
	reader:inject 'bindata'
	reader:inject(reader_proto)
	reader.v = tonumber(context.v)

	local room = {}
	reader:room(room)

	local exec_add_bitmap = assert(db:prepare [[

		INSERT INTO bitmap (
			pixel_format,
			pixel_data,
			palette
		)
		VALUES (
			:pixel_format,
			:pixel_data,
			:palette
		)

	]])

	local function add_bitmap(bitmap)
		assert( exec_add_bitmap:bind_text(':pixel_format', 'p8') )
		assert( exec_add_bitmap:bind_blob(':pixel_data', bitmap.pixel_data) )
		assert( exec_add_bitmap:bind_blob(':palette', bitmap.palette) )
		assert( assert( exec_add_bitmap:step() ) == 'done' )
		assert( exec_add_bitmap:reset() )
		return db:last_insert_rowid()
	end

	local background_image_dbid = add_bitmap(room.background_image)
	local hotspot_map_dbid = add_bitmap(room.hotspot_map)
	local walkbehind_map_dbid = add_bitmap(room.walkbehind_map)
	local walkable_map_dbid = add_bitmap(room.walkable_map)

	assert( exec_add_bitmap:finalize() )

	local exec_add_room = assert(db:prepare [[

		INSERT INTO room (
			background_image_dbid,
			hotspot_map_dbid,
			walkbehind_map_dbid,
			walkable_map_dbid,

			top_edge_y,
			bottom_edge_y,
			left_edge_x,
			right_edge_x
		)
		VALUES (
			:background_image_dbid,
			:hotspot_map_dbid,
			:walkbehind_map_dbid,
			:walkable_map_dbid,

			:top_edge_y,
			:bottom_edge_y,
			:left_edge_x,
			:right_edge_x
		)

	]])

	assert( exec_add_room:bind_int64(':background_image_dbid', background_image_dbid) )
	assert( exec_add_room:bind_int64(':hotspot_map_dbid',      hotspot_map_dbid     ) )
	assert( exec_add_room:bind_int64(':walkbehind_map_dbid',   walkbehind_map_dbid  ) )
	assert( exec_add_room:bind_int64(':walkable_map_dbid',     walkable_map_dbid    ) )
	assert( exec_add_room:bind_int(':top_edge_y', room.top_edge) )
	assert( exec_add_room:bind_int(':bottom_edge_y', room.bottom_edge) )
	assert( exec_add_room:bind_int(':left_edge_x', room.left_edge) )
	assert( exec_add_room:bind_int(':right_edge_x', room.right_edge) )
	assert( assert( exec_add_room:step() ) == 'done' )

	assert( exec_add_room:finalize() )

	local room_dbid = db:last_insert_rowid()

	if room.objects[1] then
		local exec_add_object = assert(db:prepare [[

			INSERT INTO room_object (
				room_dbid,
				idx,

				sprite_idx,
				x,
				y,
				is_visible
			)
			VALUES (
				:room_dbid,
				:idx,

				:sprite_idx,
				:x,
				:y,
				:is_visible
			)

		]])

		assert( exec_add_object:bind_int64(':room_dbid', room_dbid) )

		for _, object in ipairs(room.objects) do
			assert( exec_add_object:bind_int(':idx', object.id) )
			assert( exec_add_object:bind_int(':sprite_idx', object.sprite_idx) )
			assert( exec_add_object:bind_int(':x', object.x) )
			assert( exec_add_object:bind_int(':y', object.y) )
			assert( exec_add_object:bind_bool(':is_visible', object.on) )

			assert( assert( exec_add_object:step() ) == 'done' )
			assert( exec_add_object:reset() )
		end

		assert( exec_add_object:finalize() )
	end

	if room.walkbehinds[1] then
		local exec_add_walkbehind = assert(db:prepare [[

			INSERT INTO room_walkbehind (
				room_dbid,
				idx,
				baseline
			)
			VALUES (
				:room_dbid,
				:idx,
				:baseline
			)

		]])

		assert( exec_add_walkbehind:bind_int64(':room_dbid', room_dbid) )

		for _, walkbehind in ipairs(room.walkbehinds) do
			assert( exec_add_walkbehind:bind_int(':idx', walkbehind.id) )
			assert( exec_add_walkbehind:bind_int(':baseline', walkbehind.baseline) )

			assert( assert( exec_add_walkbehind:step() ) == 'done' )
			assert( exec_add_walkbehind:reset() )
		end

		assert( exec_add_walkbehind:finalize() )
	end

	if room.messages[1] then
		local exec_add_message = assert(db:prepare [[

			INSERT INTO message (
				room_dbid,
				idx,
				content,
				continues_to_next,
				is_removed_after_timeout,
				is_shown_as_speech
			)
			VALUES (
				:room_dbid,
				:idx,
				:content,
				:continues_to_next,
				:is_removed_after_timeout,
				:is_shown_as_speech
			)

		]])

		assert( exec_add_message:bind_int64(':room_dbid', room_dbid) )

		for _, message in ipairs(room.messages) do
			assert( exec_add_message:bind_int(':idx', message.id) )
			assert( exec_add_message:bind_text(':content', message.text) )
			assert( exec_add_message:bind_bool(':continues_to_next', message.continues_to_next) )
			assert( exec_add_message:bind_bool(':is_removed_after_timeout', message.is_removed_after_timeout) )
			assert( exec_add_message:bind_bool(':is_shown_as_speech', message.is_shown_as_speech) )

			assert( assert( exec_add_message:step() ) == 'done' )
			assert( exec_add_message:reset() )
		end

		assert( exec_add_message:finalize() )
	end

	if room.hotspots[1] then
		local exec_add_hotspot = assert(db:prepare [[

			INSERT INTO room_hotspot (
				room_dbid,
				idx
			)
			VALUES (
				:room_dbid,
				:idx
			)

		]])

		assert( exec_add_hotspot:bind_int64(':room_dbid', room_dbid) )

		for _, hotspot in ipairs(room.hotspots) do
			assert( exec_add_hotspot:bind_int(':idx', hotspot.id) )

			assert( assert( exec_add_hotspot:step() ) == 'done' )
			assert( exec_add_hotspot:reset() )
		end

		assert( exec_add_hotspot:finalize() )
	end

end

local function list(length)
	local t = {byId={}}
	for i = 1, length do
		local id = i-1
		local el = {id = id}
		t[i] = el
		t.byId[id] = el
	end
	return t
end

function reader_proto:room(room)
	room.walkbehinds = list(self:uint16le())
	for _, walkbehind in ipairs(room.walkbehinds) do
		walkbehind.baseline = self:int16le()
	end
	room.hotspots = list(16)
	room.event_handlers = list(125)
	for _, event_handler in ipairs(room.event_handlers) do
		event_handler.response = self:int16le()
	end
	for _, event_handler in ipairs(room.event_handlers) do
		event_handler.data1 = self:int16le()
	end
	for _, event_handler in ipairs(room.event_handlers) do
		event_handler.data2 = self:int16le()
	end
	for _, event_handler in ipairs(room.event_handlers) do
		event_handler.misc = self:int16le()
	end
	for _, event_handler in ipairs(room.event_handlers) do
		event_handler.points = self:uint8()
	end
	room.top_edge = self:int16le()
	room.bottom_edge = self:int16le()
	room.left_edge = self:int16le()
	room.right_edge = self:int16le()
	room.objects = list(self:uint16le())
	for _, object in ipairs(room.objects) do
		self:room_object(object)
	end
	room.password = self:blob(11)
	room.startup_music = self:uint8()
	room.allows_save_load = self:bool8()
	room.hides_player_character = self:bool8()
	room.player_special_view = self:uint8()
	if room.player_special_view == 0 then
		room.player_special_view = nil
	end
	room.music_volume = self:int8() -- 0 normal, -3 quietest, 5 loudest (but 3 highest setting in editor)
	self:skip(5) -- 5 unused room options
	room.messages = list(self:uint16le())
	for _, message in ipairs(room.messages) do
		message.is_shown_as_speech = self:bool8()
		local flags = self:uint8()
		if 0 ~= bit.band(1, flags) then
			message.continues_to_next = true
		end
		if 0 ~= bit.band(2, flags) then
			message.is_removed_after_timeout = true
		end
	end
	for _, message in ipairs(room.messages) do
		message.text = self:nullTerminated()
		if message.text:sub(-1) == '\200' then
			message.text = message.text:sub(1, -2)
			message.continues_to_next = true
		end
	end
	if self.v >= kRoomVersion_pre114_4 and self.v < kRoomVersion_250a then
		assert( self:int32le() == 1, 'invalid script configuration version' )
		room.script_vars = list( self:int32le() )
		for _, script_var in ipairs(room.script_vars) do
			script_var.name = self:blob( self:uint8() )
		end
		room.scripts = {}
		while true do
			local ct = self:int32le()
			if ct == -1 or ct == nil then
				break
			end
			room.scripts[#room.scripts+1] = {idx=ct, code=self:blob( self:int32le() )}
		end
	end
	room.background_image = {}
	self:allegro_bitmap(room.background_image)
	room.walkable_map = {}
	self:allegro_bitmap(room.walkable_map)
	room.walkbehind_map = {}
	self:allegro_bitmap(room.walkbehind_map)
	room.hotspot_map = {}
	self:allegro_bitmap(room.hotspot_map)
end

function reader_proto:room_object(object)
	object.sprite_idx = self:int16le()
	object.x = self:int16le()
	object.y = self:int16le()
	object.room = self:int16le()
	object.on = self:bool16()
end

function reader_proto:allegro_bitmap(bitmap)
	local width  = self:int16le()
	local height = self:int16le()

	local buf = {}

	local left = width * height

	repeat
		local bytes
		local cx = self:int8()
		if cx == -128 then
			bytes = self:blob(1)
		elseif cx < 0 then
			bytes = string.rep(self:blob(1), 1 - cx)
		else
			bytes = self:blob(1 + cx)
		end
		buf[#buf+1] = bytes
		left = left - #bytes
	until left == 0

	bitmap.width = width
	bitmap.height = height

	bitmap.pixel_data = table.concat(buf)

	bitmap.pixel_format = 'p8'

	bitmap.palette_pixel_format = 'r8g8b8'
	bitmap.palette = self:blob(768)
end

return format
