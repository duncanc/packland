
local ffi = require 'ffi'
local bit = require 'bit'
local R = require 'denzquix.packland.reader'
require 'denzquix.packland.data.ags.read'

local format = {}

local kRoomVersion_pre114_2   = 2  -- exact version unknown
local kRoomVersion_pre114_3   = 3  -- exact version unknown
local kRoomVersion_pre114_4   = 4  -- exact version unknown
local kRoomVersion_pre114_5   = 5  -- exact version unknown
local kRoomVersion_pre114_6   = 6  -- exact version unknown
local kRoomVersion_pre114_7   = 7  -- exact version unknown
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

local tested_versions = {
	[kRoomVersion_pre114_2] = true;
	[kRoomVersion_pre114_3] = true;
	[kRoomVersion_pre114_4] = true;
	[kRoomVersion_pre114_5] = true;
	[kRoomVersion_pre114_6] = true;
	[kRoomVersion_pre114_7] = true;
	[kRoomVersion_114] = true;
	-- NOT kRoomVersion_200_alpha
	[kRoomVersion_200_alpha7] = true;
	[kRoomVersion_200_final] = true;
	[kRoomVersion_208] = true;
	[kRoomVersion_214] = true;
	[kRoomVersion_240] = true;
	-- NOT kRoomVersion_241
	-- NOT kRoomVersion_250a
	[kRoomVersion_250b] = true;
}

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
			region_map_dbid INTEGER,

			top_edge_y INTEGER,
			bottom_edge_y INTEGER,
			left_edge_x INTEGER,
			right_edge_x INTEGER,

			width INTEGER,
			height INTEGER,
			resolution TEXT,

			FOREIGN KEY (background_image_dbid) REFERENCES bitmap(dbid),
			FOREIGN KEY (hotspot_map_dbid) REFERENCES bitmap(dbid),
			FOREIGN KEY (walkbehind_map_dbid) REFERENCES bitmap(dbid),
			FOREIGN KEY (walkable_map_dbid) REFERENCES bitmap(dbid),
			FOREIGN KEY (region_map_dbid) REFERENCES bitmap(dbid)
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

			baseline INTEGER,

			FOREIGN KEY (room_dbid) REFERENCES room(dbid)
		);

		CREATE TABLE IF NOT EXISTS room_hotspot (
			dbid INTEGER PRIMARY KEY,
			room_dbid INTEGER NOT NULL,
			idx INTEGER,
			display_name TEXT,

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

		CREATE TABLE IF NOT EXISTS room_anim (
			dbid INTEGER PRIMARY KEY,
			room_dbid INTEGER,
			idx INTEGER,

			FOREIGN KEY (room_dbid) REFERENCES room(dbid)
		);

		CREATE TABLE IF NOT EXISTS room_anim_stage (
			dbid INTEGER PRIMARY KEY,
			anim_dbid INTEGER,
			idx INTEGER,

			x INTEGER,
			y INTEGER,
			data INTEGER,
			object INTEGER,
			speed INTEGER,
			action INTEGER,
			wait INTEGER,

			FOREIGN KEY (anim_dbid) REFERENCES room_anim(dbid)
		);

		CREATE TABLE IF NOT EXISTS room_region (
			dbid INTEGER PRIMARY KEY,
			room_dbid INTEGER,
			idx INTEGER,
			shading INTEGER,

			FOREIGN KEY (room_dbid) REFERENCES room(dbid)
		);

		CREATE TABLE IF NOT EXISTS room_walk_zone (
			dbid INTEGER PRIMARY KEY,
			room_dbid INTEGER,
			idx INTEGER,
			scale_top INTEGER,
			scale_bottom INTEGER,
			light_level INTEGER,

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
		if bitmap == nil then
			return nil
		end
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
	local region_map_dbid = add_bitmap(room.region_map)

	assert( exec_add_bitmap:finalize() )

	local exec_add_room = assert(db:prepare [[

		INSERT INTO room (
			background_image_dbid,
			hotspot_map_dbid,
			walkbehind_map_dbid,
			walkable_map_dbid,
			region_map_dbid,

			top_edge_y,
			bottom_edge_y,
			left_edge_x,
			right_edge_x,

			width,
			height,
			resolution
		)
		VALUES (
			:background_image_dbid,
			:hotspot_map_dbid,
			:walkbehind_map_dbid,
			:walkable_map_dbid,
			:region_map_dbid,

			:top_edge_y,
			:bottom_edge_y,
			:left_edge_x,
			:right_edge_x,

			:width,
			:height,
			:resolution
		)

	]])

	assert( exec_add_room:bind_int64(':background_image_dbid', background_image_dbid) )
	assert( exec_add_room:bind_int64(':hotspot_map_dbid',      hotspot_map_dbid     ) )
	assert( exec_add_room:bind_int64(':walkbehind_map_dbid',   walkbehind_map_dbid  ) )
	assert( exec_add_room:bind_int64(':walkable_map_dbid',     walkable_map_dbid    ) )
	if region_map_dbid == nil then
		assert( exec_add_room:bind_null(':region_map_dbid') )
	else
		assert( exec_add_room:bind_int64(':region_map_dbid',   region_map_dbid      ) )
	end
	assert( exec_add_room:bind_int(':top_edge_y', room.top_edge) )
	assert( exec_add_room:bind_int(':bottom_edge_y', room.bottom_edge) )
	assert( exec_add_room:bind_int(':left_edge_x', room.left_edge) )
	assert( exec_add_room:bind_int(':right_edge_x', room.right_edge) )
	if room.width == nil then
		assert( exec_add_room:bind_null(':width') )
		assert( exec_add_room:bind_null(':height') )
	else
		assert( exec_add_room:bind_int(':width', room.width) )
		assert( exec_add_room:bind_int(':height', room.height) )
	end
	assert( exec_add_room:bind_text(':resolution', room.resolution) )
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
				is_visible,

				baseline
			)
			VALUES (
				:room_dbid,
				:idx,

				:sprite_idx,
				:x,
				:y,
				:is_visible,

				:baseline
			)

		]])

		assert( exec_add_object:bind_int64(':room_dbid', room_dbid) )

		for _, object in ipairs(room.objects) do
			assert( exec_add_object:bind_int(':idx', object.id) )
			assert( exec_add_object:bind_int(':sprite_idx', object.sprite_idx) )
			assert( exec_add_object:bind_int(':x', object.x) )
			assert( exec_add_object:bind_int(':y', object.y) )
			assert( exec_add_object:bind_bool(':is_visible', object.on) )

			if object.baseline == nil then
				assert( exec_add_object:bind_null(':baseline') )
			else
				assert( exec_add_object:bind_int(':baseline', object.baseline) )
			end

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
			if walkbehind.baseline == nil then
				assert( exec_add_walkbehind:bind_null(':baseline') )
			else
				assert( exec_add_walkbehind:bind_int(':baseline', walkbehind.baseline) )
			end

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
				idx,
				display_name
			)
			VALUES (
				:room_dbid,
				:idx,
				:display_name
			)

		]])

		assert( exec_add_hotspot:bind_int64(':room_dbid', room_dbid) )

		for _, hotspot in ipairs(room.hotspots) do
			assert( exec_add_hotspot:bind_int(':idx', hotspot.id) )
			assert( exec_add_hotspot:bind_text(':display_name', hotspot.name) )

			assert( assert( exec_add_hotspot:step() ) == 'done' )
			assert( exec_add_hotspot:reset() )
		end

		assert( exec_add_hotspot:finalize() )
	end

	if room.anims and room.anims[1] then
		local exec_add_anim = assert(db:prepare [[

			INSERT INTO room_anim (
				room_dbid,
				idx
			)
			values (
				:room_dbid,
				:idx
			)

		]])

		assert( exec_add_anim:bind_int64(':room_dbid', room_dbid) )

		local exec_add_stage = assert(db:prepare [[

			INSERT INTO room_anim_stage (
				anim_dbid,
				idx,

				x,
				y,
				data,
				object,
				speed,
				action,
				wait
			)
			VALUES (
				:anim_dbid,
				:idx,

				:x,
				:y,
				:data,
				:object,
				:speed,
				:action,
				:wait
			)

		]])

		for _, anim in ipairs(room.anims) do
			assert( exec_add_anim:bind_int(':idx', anim.id) )
			assert( assert( exec_add_anim:step() ) == 'done' )
			assert( exec_add_anim:reset() )

			local anim_dbid = db:last_insert_rowid()

			assert( exec_add_stage:bind_int64(':anim_dbid', anim_dbid) )

			for _, stage in ipairs(anim.stages) do
				assert( exec_add_stage:bind_int(':idx', stage.id) )
				assert( exec_add_stage:bind_int(':x', stage.x) )
				assert( exec_add_stage:bind_int(':y', stage.y) )
				assert( exec_add_stage:bind_int(':data', stage.data) )
				assert( exec_add_stage:bind_int(':object', stage.object) )
				assert( exec_add_stage:bind_int(':speed', stage.speed) )
				assert( exec_add_stage:bind_int(':action', stage.action) )
				assert( exec_add_stage:bind_int(':wait', stage.wait) )
				assert( assert( exec_add_stage:step() ) == 'done' )
				assert( exec_add_stage:reset() )
			end
		end

		assert( exec_add_anim:finalize() )

		assert( exec_add_stage:finalize() )
	end

	if room.regions and room.regions[1] then
		local exec_add_region = assert(db:prepare [[

			INSERT INTO room_region (
				room_dbid,
				idx,
				shading
			)
			VALUES (
				:room_dbid,
				:idx,
				:shading
			)

		]])

		assert( exec_add_region:bind_int64(':room_dbid', room_dbid) )

		for _, region in ipairs(room.regions) do
			assert( exec_add_region:bind_int(':idx', region.id) )
			assert( exec_add_region:bind_int(':shading', region.shading) )

			assert( assert(exec_add_region:step()) == 'done' )
			assert( exec_add_region:reset() )
		end

		assert( exec_add_region:finalize() )
	end

	if room.walk_zones and room.walk_zones[1] then
		local exec_add_walk_zone = assert(db:prepare [[

			INSERT INTO room_walk_zone (
				room_dbid,
				idx,
				scale_top,
				scale_bottom,
				light_level
			)
			VALUES (
				:room_dbid,
				:idx,
				:scale_top,
				:scale_bottom,
				:light_level
			)

		]])

		assert( exec_add_walk_zone:bind_int64(':room_dbid', room_dbid) )

		for _, walk_zone in ipairs(room.walk_zones) do
			assert( exec_add_walk_zone:bind_int(':idx', walk_zone.id) )
			assert( exec_add_walk_zone:bind_int(':scale_top', walk_zone.scale_top) )
			assert( exec_add_walk_zone:bind_int(':scale_bottom', walk_zone.scale_bottom) )
			if walk_zone.light_level == nil then
				assert( exec_add_walk_zone:bind_null(':light_level') )
			else
				assert( exec_add_walk_zone:bind_int(':light_level', walk_zone.light_level) )
			end

			assert( assert( exec_add_walk_zone:step() ) == 'done' )
			assert( exec_add_walk_zone:reset() )
		end

		assert( exec_add_walk_zone:finalize() )
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

function reader_proto:masked_blob(op, mask, n)
	local buf = {}
	if op == '+' then

		for i = 1, n do
			local b = self:uint8()
			local mb = mask:byte(((i-1) % #mask) + 1)
			buf[i] = string.char(bit.band(0xFF, b + mb))
		end

	elseif op == '-' then

		for i = 1, n do
			local b = self:uint8()
			local mb = mask:byte(((i-1) % #mask) + 1)
			buf[i] = string.char(bit.band(0xFF, b - mb))
		end

	else
		error('unsupported mask op', 2)
	end
	return table.concat(buf)
end

function reader_proto:interactions_v2(interactions)
	local max_interactions = 8
	for i = 1, max_interactions do
		interactions[i] = {event=self:int32le()}
	end
	for i = 1, max_interactions do
		interactions[i].response = self:int32le()
	end
	for i = 1, max_interactions do
		interactions[i].data1 = self:int32le()
	end
	for i = 1, max_interactions do
		interactions[i].data2 = self:int32le()
	end
	local used_interactions = self:int32le()
	for i = 1, max_interactions do
		interactions[i].points = self:int16le()
	end
	for i = used_interactions+1, max_interactions do
		interactions[i] = nil
	end
end

function reader_proto:room(room)
	assert(tested_versions[self.v], 'unsupported room data version')

	local max_hotspots, max_objects, max_walk_zones
	if self.v >= kRoomVersion_200_alpha then
		max_hotspots = 20
		max_objects = 10
		max_walk_zones = 16
	else
		max_hotspots = 16
		max_objects = 10
	end

	local max_regions
	if self.v >= kRoomVersion_114 then
		max_regions = 16
	end

	if max_regions then
		room.regions = list(max_regions)
	end

	if self.v >= kRoomVersion_208 then
		local bpp = self:int32le()
		if bpp == 1 then
			room.pixel_format = 'p8'
		elseif bpp == 2 then
			room.pixel_format = 'r5g6b5'
		elseif bpp == 3 then
			room.pixel_format = 'r8g8b8'
		elseif bpp == 4 then
			room.pixel_format = 'r8g8b8x8'
		else
			error('unsupported bits-per-pixel value: ' .. bpp)
		end
	else
		room.pixel_format = 'p8'
	end

	room.walkbehinds = list(self:uint16le())
	for _, walkbehind in ipairs(room.walkbehinds) do
		walkbehind.baseline = self:int16le()
		if walkbehind.baseline == -1 then
			walkbehind.baseline = nil
		end
	end

	if self.v >= kRoomVersion_200_alpha then

		-- to trim room.hotspots later
		room.used_hotspots = self:int32le()
		if room.used_hotspots == 0 then
			room.used_hotspots = nil
		end

	end

	room.hotspots = list(max_hotspots)

	if self.v >= kRoomVersion_200_alpha and self.v <= kRoomVersion_240 then

		for _, hotspot in ipairs(room.hotspots) do
			hotspot.interactions_v2 = {}
			self:interactions_v2(hotspot.interactions_v2)
		end

		room.objects = list(max_objects)

		for _, object in ipairs(room.objects) do
			object.interactions_v2 = {}
			self:interactions_v2(object.interactions_v2)
		end

		room.interactions_v2 = {}
		self:interactions_v2(room.interactions_v2)

	end

	if self.v >= kRoomVersion_200_alpha then

		for _, hotspot in ipairs(room.hotspots) do
			hotspot.walk_to_x = self:int16le()
			hotspot.walk_to_y = self:int16le()
		end

		for _, hotspot in ipairs(room.hotspots) do
			hotspot.name = self:nullTerminated(30)
		end

		room.walls = list( self:int32le() )

		for _, wall in ipairs(room.walls) do
			wall.points = list(30)
			for _, point in ipairs(wall.points) do
				point.x = self:int32le()
			end
			for _, point in ipairs(wall.points) do
				point.y = self:int32le()
			end
			for i = self:int32le() + 1, #wall.points do
				wall.points[i] = nil
			end
		end

	end

	if self.v <= kRoomVersion_pre114_6 then
		room.event_handlers = list(125)
	elseif self.v <= kRoomVersion_114 then
		room.event_handlers = list(127)
	end

	if room.event_handlers then
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
	end

	if room.used_hotspots then
		for i = room.used_hotspots+1, max_hotspots do
			room.hotspots[i] = nil
		end
	end

	room.top_edge = self:int16le()
	room.bottom_edge = self:int16le()
	room.left_edge = self:int16le()
	room.right_edge = self:int16le()

	local used_object_count = self:uint16le()
	if room.objects then
		for i = used_object_count + 1, max_objects do
			room.objects[i] = nil
		end
	else
		room.objects = list(used_object_count)
	end

	for _, object in ipairs(room.objects) do
		self:room_object(object)
	end

	if self.v >= kRoomVersion_241 then
		self:inject 'ags:interactions'
		for _, hotspot in ipairs(room.hotspots) do
			hotspot.interactions_v3 = {}
			self:interactions_v3(hotspot.interactions_v3)
		end
		for _, object in ipairs(room.objects) do
			object.interactions_v3 = {}
			self:interactions_v3(object.interactions_v3)
		end

		room.interactions_v3 = {}
		self:interactions_v3(room.interactions_v3)

		for _, region in ipairs(room.regions) do
			region.interactions_v3 = {}
			self:interactions_v3(region.interactions_v3)
		end
	end

	if self.v >= kRoomVersion_200_alpha then
		for _, object in ipairs(room.objects) do
			object.baseline = self:int32le()
			if object.baseline == -1 then
				object.baseline = nil
			end
		end

		room.width = self:int16le()
		room.height = self:int16le()
	end

	if self.v >= kRoomVersion_200_final then
		room.resolution = self:int16le()
		if room.resolution == 1 then
			room.resolution = 'low'
		elseif room.resolution == 2 then
			room.resolution = 'high'
		else
			room.resolution = tostring(room.resolution)
		end
	end

	if self.v >= kRoomVersion_240 then
		room.walk_zones = list(self:int32le() + 1)
	elseif self.v >= kRoomVersion_200_alpha7 then
		room.walk_zones = list(max_walk_zones)
	end

	if room.walk_zones then
		table.remove(room.walk_zones, 1)
		room.walk_zones.byId[0] = nil
	end

	if self.v >= kRoomVersion_200_alpha7 then
		for _, walk_zone in ipairs(room.walk_zones) do
			walk_zone.scale_top = self:int16le()
			walk_zone.scale_bottom = walk_zone.scale_top
		end
	end

	if self.v >= kRoomVersion_214 then
		for _, walk_zone in ipairs(room.walk_zones) do
			walk_zone.light_level = self:int16le()
		end
	end

	if self.v >= kRoomVersion_200_alpha then
		room.password = self:masked_blob('+', 'Avis Durgan', 11)
	else
		room.password = self:masked_blob('+', '\60', 11)
	end

	room.password = string.match(room.password, '^%Z+')

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
	-- TODO: check about message flags pre-v3?
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
	if self.v >= kRoomVersion_pre114_6 then
		room.anims = list( self:int16le() )
		for _, anim in ipairs(room.anims) do
			self:room_anim(anim)
		end
	end

	-- graphical script
	if self.v >= kRoomVersion_pre114_4 and self.v <= kRoomVersion_241 then
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

	if self.v >= kRoomVersion_114 then
		for _, region in ipairs(room.regions) do
			region.shading = self:int16le()
		end
	end
	room.background_image = {}
	if self.v >= kRoomVersion_pre114_5 then
		self:lzw_bitmap(room.background_image, room.pixel_format)
	else
		self:allegro_bitmap(room.background_image)
	end
	if self.v >= kRoomVersion_114 then
		room.region_map = {}
		self:allegro_bitmap(room.region_map)
	end
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

function reader_proto:room_anim(anim)
	anim.stages = list(10)
	for _, stage in ipairs(anim.stages) do
		self:anim_stage(stage)
	end
	for i = self:int32le() + 1, #anim.stages do
		anim.stages.byId[anim.stages[i].id] = nil
		anim.stages[i] = nil
	end
end

function reader_proto:anim_stage(stage)
	local base = self:pos()
	stage.x = self:int32le()
	stage.y = self:int32le()
	stage.data = self:int32le()
	stage.object = self:int32le()
	stage.speed = self:int32le()
	stage.action = self:uint8()
	stage.wait = self:uint8()
	self:align(4, base)
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

local function bytes_per_pixel(pixel_format)
	local bitcount = 0
	for bits in pixel_format:gmatch('%d+') do
		bitcount = bitcount + tonumber(bits)
	end
	return math.ceil(bitcount / 8)
end

function reader_proto:lzw_bitmap(bitmap, pixel_format)
	local palbuf = {}
	for i = 1, 256 do
		palbuf[i] = self:blob(4):sub(1,3)
	end
	bitmap.palette_pixel_format = 'r8g8b8'
	bitmap.palette = table.concat(palbuf)
	local max_size = self:int32le()
	local uncomp_size = self:int32le()
	local end_pos = self:pos() + uncomp_size

	local lzbuffer = ffi.new('uint8_t[4096]')

	local ix = 0x1000 - 0x10

	local pixbuf = {}
	local written = 0
	repeat
		local bits = self:uint8()
		for bitpos = 0, 7 do
			if 0 ~= bit.band(bits, bit.lshift(1, bitpos)) then
				local jx = self:int16le()
				local len = bit.band(bit.rshift(jx, 12), 0xF) + 3
				jx = bit.band(ix - jx - 1, 0xFFF)
				for _ = 1, len do
					pixbuf[#pixbuf+1] = string.char(lzbuffer[jx])
					lzbuffer[ix] = lzbuffer[jx]
					jx = (jx + 1) % 0x1000
					ix = (ix + 1) % 0x1000
				end
				written = written + len
			else
				local ch = self:uint8()
				lzbuffer[ix] = ch
				pixbuf[#pixbuf+1] = string.char(ch)
				ix = (ix + 1) % 0x1000
				written = written + 1
			end
			if written >= max_size then
				break
			end
		end
	until written >= max_size
	assert(self:pos() == end_pos)
	bitmap.pixel_data = table.concat(pixbuf)
	bitmap.pixel_format = pixel_format

	local size_reader = R.fromstring(bitmap.pixel_data:sub(1,8))
	size_reader:inject 'bindata'
	bitmap.width = size_reader:int32le() / bytes_per_pixel(pixel_format)
	bitmap.height = size_reader:int32le()

	bitmap.pixel_data = bitmap.pixel_data:sub(9)
end

return format
