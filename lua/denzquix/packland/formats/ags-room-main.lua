
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
	if self.v >= kRoomVersion_208 then
		local bpp = math.max(1, self:int32le())
		if bpp == 1 then
			room.pixel_format = 'pal8'
		elseif bpp == 2 then
			room.pixel_format = 'r5g6b5'
		else
			room.pixel_format = 'r8g8b8x8'
		end
	else
		room.pixel_format = 'pal8'
	end
	room.walk_behinds = list( self:int16le() )
	for _, walk_behind in ipairs(room.walk_behinds) do
		walk_behind.baseline = self:int16le()
	end
	local hotspot_count = self:int32le()
	if hotspot_count == 0 then
		hotspot_count = 20
	end
	room.hotspots = list( hotspot_count )
	for _, hotspot in ipairs(room.hotspots) do
		hotspot.walk_to_x = self:int16le()
		hotspot.walk_to_y = self:int16le()
	end
	if self.v >= kRoomVersion_303a then
		for _, hotspot in ipairs(room.hotspots) do
			hotspot.name = self:nullTerminated()
		end
	else
		for _, hotspot in ipairs(room.hotspots) do
			hotspot.name = self:nullTerminated(30)
		end
	end
	if self.v >= kRoomVersion_270 then
		for _, hotspot in ipairs(room.hotspots) do
			hotspot.script_name = self:nullTerminated(20)
		end
	end
	room.wall_points = list(self:int32le())
	for _, wall_point in ipairs(room.wall_points) do
		wall_point.x = self:int32le()
	end
	for _, wall_point in ipairs(room.wall_points) do
		wall_point.y = self:int32le()
	end
	room.top_edge = self:int16le()
	room.bottom_edge = self:int16le()
	room.left_edge = self:int16le()
	room.right_edge = self:int16le()

end

return format
