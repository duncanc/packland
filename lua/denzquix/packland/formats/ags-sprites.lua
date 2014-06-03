
local bit = require 'bit'
local ffi = require 'ffi'
local R = require 'denzquix.packland.reader'

-------------------------------------------------------------------------------

local format = {}

local reader_proto = {}

-------------------------------------------------------------------------------

function format.dbinit(db)
	db:exec [[

		CREATE TABLE IF NOT EXISTS sprite_store (
			dbid INTEGER PRIMARY KEY
		);

		CREATE TABLE IF NOT EXISTS sprite (
			dbid INTEGER PRIMARY KEY,
			cache_dbid INTEGER NOT NULL,
			idx INTEGER NOT NULL,
			width INTEGER NOT NULL,
			height INTEGER NOT NULL,
			bytes_per_pixel INTEGER NOT NULL,
			pixel_data BLOB NOT NULL,
			FOREIGN KEY (cache_dbid) REFERENCES sprite_store(dbid)
		);
		CREATE UNIQUE INDEX IF NOT EXISTS sprite_idx
		ON sprite (cache_dbid, idx);

	]]
end

function format.todb(intype, inpath, db)
	assert(intype == 'file', 'input must be a file (got ' .. intype .. ')')
	local reader = assert(R.fromfile(inpath))
	reader:inject('bindata')
	reader:inject(reader_proto)

	local cache = {}
	reader:spriteCache(cache)

	format.dbinit(db)

	db:exec [[

		INSERT INTO sprite_store DEFAULT VALUES

	]]

	local cache_dbid = db:last_insert_rowid()

	local exec_add_sprite = assert( db:prepare [[

		INSERT INTO sprite (cache_dbid, idx, width, height, bytes_per_pixel, pixel_data)
		VALUES (:cache_dbid, :idx, :width, :height, :bytes_per_pixel, :pixel_data)

	]] )

	assert( exec_add_sprite:bind_int64(':cache_dbid', cache_dbid) )
		
	for i, sprite in ipairs(cache) do

		if sprite ~= false then
			assert( exec_add_sprite:bind_int(':idx', sprite.number) )
			assert( exec_add_sprite:bind_int(':width', sprite.width) )
			assert( exec_add_sprite:bind_int(':height', sprite.height) )
			assert( exec_add_sprite:bind_int(':bytes_per_pixel', sprite.bytes_per_pixel) )
			assert( exec_add_sprite:bind_blob(':pixel_data', sprite.data) )

			assert( assert( exec_add_sprite:step() ) == 'done' )
			assert( exec_add_sprite:reset() )
		end

	end

	assert( exec_add_sprite:finalize() )
end

-------------------------------------------------------------------------------

function reader_proto:spriteCache(cache)
	local version = self:int16le()
	assert(version >= 4 and version <= 6, 'unsupported version')
	assert(self:expectBlob ' Sprite File ', 'signature not found')
	local compressed, file_id
	if version == 4 then
		compressed = false
	elseif version == 5 then
		compressed = true
	elseif version >= 6 then
		compressed = self:uint8() == 1
		file_id = self:int32le()
	end
	if version < 5 then
		self:skip(256 * 3) -- palette
	end
	local last_i = self:int16le()
	if version < 4 then
		count = 200
	end
	for sprite_i = 0, last_i do
		local sprite = {number = sprite_i}
		sprite.bytes_per_pixel = self:int16le()
		if sprite.bytes_per_pixel ~= 0 then
			sprite.width = self:int16le()
			sprite.height = self:int16le()
			if compressed then
				local uncompressor = R.fromstring(self:blob(self:int32le()))
				uncompressor:inject 'bindata'
				uncompressor:inject(reader_proto)
				sprite.data = uncompressor:uncompress(sprite.bytes_per_pixel)
			else
				sprite.data = self:blob(sprite.width * sprite.height * sprite.bytes_per_pixel)
			end
			cache[#cache+1] = sprite
		end
	end
end

function reader_proto:uncompress(bytes_per_pixel)
	local buf = {}
	while true do
		local cx = self:int8()
		if cx == nil then
			break
		end
		if cx == -128 then
			cx = 0
		end
		if cx < 0 then
			-- repeated pixel
			buf[#buf+1] = string.rep(self:blob(bytes_per_pixel), 1 - cx)
		else
			-- sequence of pixels
			buf[#buf+1] = self:blob(bytes_per_pixel * (1 + cx))
		end
	end
	return table.concat(buf)
end

-------------------------------------------------------------------------------

return format
