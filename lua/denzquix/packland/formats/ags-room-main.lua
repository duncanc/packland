
local R = require 'denzquix.packland.reader'

local format = {}

function format.dbinit(db)

	assert(db:exec [[



	]])

end

local reader_proto = {}

function format.todb(intype, inpath, db)
	assert(intype == 'file', 'input must be a file (got ' .. intype .. ')')

	format.dbinit(db)

	local reader = assert(R.fromfile(inpath))
	reader:inject 'bindata'
	reader:inject(reader_proto)

	local room = {}
	reader:room(room)
end

function reader_proto:room(room)
	if room.version >= kRoomVersion_208 then
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
	if room.version >= kRoomVersion_303a then
		for _, hotspot in ipairs(room.hotspots) do
			hotspot.name = self:nullTerminated()
		end
	else
		for _, hotspot in ipairs(room.hotspots) do
			hotspot.name = self:nullTerminated(30)
		end
	end
	if room.version >= kRoomVersion_270 then
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
