
local ffi = require 'ffi'
local R = require 'denzquix.packland.reader'

local format = {}

local reader_proto = {}

function format.dbinit(db)
	assert(db:exec [[

		CREATE TABLE IF NOT EXISTS bitmap (
			dbid INTEGER PRIMARY KEY,
			pixel_format TEXT,
			pixel_data BLOB,
			palette BLOB,
			width INTEGER,
			height INTEGER
		);

		CREATE TABLE IF NOT EXISTS sprite_bank (
			dbid INTEGER PRIMARY KEY
		);

		CREATE TABLE IF NOT EXISTS sprite (
			dbid INTEGER PRIMARY KEY,
			bank_dbid INTEGER,
			idx INTEGER,
			bitmap_dbid INTEGER,
			handle_x INTEGER,
			handle_y INTEGER,
			type TEXT,

			FOREIGN KEY (bank_dbid) REFERENCES sprite_or_icon_bank,
			FOREIGN KEY (bitmap_dbid) REFERENCES bitmap
		);

	]])
end

function format.todb(intype, inpath, db)
	local data = assert( R.fromfile(inpath) )
	data:inject 'bindata'
	data:inject(reader_proto)

	local bank = {}
	data:amos_bank(bank)

	if bank.type == 'Pic.Pac.' then

		format.dbinit(db)

		local exec_add_pic = assert(db:prepare [[
			INSERT INTO bitmap (width, height, pixel_format, pixel_data, palette)
			VALUES (:width, :height, :pixel_format, :pixel_data, :palette)
		]])

		assert( exec_add_pic:bind_int(':width', bank.pic.width_bytes * 8) )
		assert( exec_add_pic:bind_int(':height', bank.pic.height_linelumps * bank.pic.lines_per_lump) )
		assert( exec_add_pic:bind_text(':pixel_format', 'p8') )
		assert( exec_add_pic:bind_blob(':pixel_data', bank.pic.data) )
		assert( exec_add_pic:bind_blob(':palette', bank.screen.palette) )
		assert( assert( exec_add_pic:step() ) == 'done' )
		assert( exec_add_pic:finalize() )

	elseif bank.type == 'AmSp' or bank.type == 'AmIc' then

		format.dbinit(db)

		local exec_add_bank = assert(db:prepare [[
			INSERT INTO sprite_bank DEFAULT VALUES
		]])

		assert( exec_add_bank:step() == 'done' )
		assert( exec_add_bank:finalize() )

		local bank_dbid = db:last_insert_rowid()

		local exec_add_pic = assert(db:prepare [[
			INSERT INTO bitmap (width, height, pixel_format, pixel_data, palette)
			VALUES (:width, :height, :pixel_format, :pixel_data, :palette)
		]])

		assert( exec_add_pic:bind_blob(':palette', bank.palette) )

		local exec_add_sprite = assert(db:prepare [[
			INSERT INTO sprite (bank_dbid, idx, bitmap_dbid, handle_x, handle_y, type)
			VALUES (:bank_dbid, :idx, :bitmap_dbid, :handle_x, :handle_y, :type)
		]])

		assert( exec_add_sprite:bind_int64(':bank_dbid', bank_dbid) )
		if bank.type == 'AmIc' then
			assert( exec_add_sprite:bind_text(':type', 'icon') )
		else
			assert( exec_add_sprite:bind_text(':type', 'sprite') )
		end

		for _, sprite in ipairs(bank) do
			assert( exec_add_pic:bind_int(':width', sprite.width) )
			assert( exec_add_pic:bind_int(':height', sprite.height) )
			assert( exec_add_pic:bind_text(':pixel_format', 'p8') )
			assert( exec_add_pic:bind_blob(':pixel_data', sprite.pixel_data) )
			assert( assert( exec_add_pic:step() ) == 'done' )
			assert( exec_add_pic:reset() )

			local bitmap_dbid = db:last_insert_rowid()

			assert( exec_add_sprite:bind_int(':idx', sprite.idx) )
			assert( exec_add_sprite:bind_int64(':bitmap_dbid', bitmap_dbid) )
			assert( exec_add_sprite:bind_int(':handle_x', sprite.handle_x) )
			assert( exec_add_sprite:bind_int(':handle_y', sprite.handle_y) )
			assert( assert( exec_add_sprite:step() ) == 'done' )
			assert( exec_add_sprite:reset() )
		end

		assert( exec_add_sprite:finalize() )
		assert( exec_add_pic:finalize() )
	end
end

function reader_proto:amos_bank(bank)
	local header = self:blob(4)
	if header == 'AmBk' then
		self:amos_bank_other(bank)
	elseif header == 'AmSp' or header == 'AmIc' then
		bank.type = header
		self:amos_sprite_bank(bank)
	else
		error('AMOS Bank Header not found')
	end
end

function reader_proto:amos_bank_other(bank)
	bank.idx = self:uint16be()
	bank.memory = self:uint16be()
	if bank.memory == 1 then
		bank.memory = 'fast'
	elseif bank.memory == 0 then
		bank.memory = 'chip'
	end
	local packed = self:int32be()
	bank.length = bit.band(packed, 0x7FFFFFF)
	bank.try_chip_memory = 0 ~= bit.band(packed, 0x40000000)
	bank.try_fast_memory = 0 ~= bit.band(packed, 0x80000000)
	bank.type = self:blob(8):match('^(.-)%s*$')
	if bank.type == 'Pac.Pic.' then
		self:picture_bank(bank)
	else
		error('unsupported bank type: ' .. bank.type)
	end
end

function reader_proto:amos_sprite_bank(bank)
	for i = 1, self:int16be() do
		local entry = {}
		entry.idx = i-1
		self:amos_sprite(entry)
		bank[i] = entry
	end
	bank.palette = self:amiga_colorx_palette()
end

function reader_proto:amos_sprite(sprite)
	local width_words = self:uint16be()
	local width = width_words * 16
	local height = self:uint16be()
	local bitplanes = self:uint16be()
	sprite.handle_x = self:int16be()
	sprite.handle_y = self:int16be()
	local buf = ffi.new('uint8_t[' .. (width * height) .. ']')

	for bp = 0, bitplanes-1 do
		local bpd = bit.lshift(1, bp)
		for y = 0, height-1 do
			for xw = 0, width_words-1 do
				local chunk = self:uint16be()
				local base_ptr = buf + (y * width) + (xw * 16)
				for xo = 0, 15 do
					if 0 ~= bit.band(chunk, bit.rshift(0x8000, xo)) then
						base_ptr[xo] = bit.bor(base_ptr[xo], bpd)
					end
				end
			end
		end
	end

	sprite.width = width
	sprite.height = height
	sprite.pixel_data = ffi.string(buf, width * height)
end

function reader_proto:picture_bank(bank)
	bank.screen = {}
	self:screen_header(bank.screen)

	bank.pic = {}
	self:picture_header(bank.pic)

	local pic = self

	local rle = self:clone()
	rle:pos('set', bank.pic.rle_pos)
	rle:inject 'bindata'

	local points = self:clone()
	points:pos('set', bank.pic.points_pos)
	points:inject 'bindata'

	local output_len = 8 * bank.pic.width_bytes * bank.pic.height_linelumps * bank.pic.lines_per_lump
	local output_pixels = ffi.new('uint8_t[' .. output_len .. ']')

	local rle_byte = rle:uint8()
	local pic_byte = pic:uint8()
	local points_byte = points:uint8()
	if 0 ~= bit.band(0x80, points_byte) then
		rle_byte = rle:uint8()
	end
	local rbit = 7
	local rrbit = 6

	local line_expanded = bank.pic.width_bytes * 8
	local lump_expanded = line_expanded * bank.pic.lines_per_lump

	for bp = 0, bank.pic.bitplanes-1 do
		for y_lump = 0, bank.pic.height_linelumps-1 do
			for x_byte = 0, bank.pic.width_bytes-1 do
				for y_lumpline = 0, bank.pic.lines_per_lump-1 do

					-- if the current RLE bit is set to 1, read in a new picture byte
					if 0 ~= bit.band(rle_byte, bit.lshift(1, rbit)) then
						pic_byte = pic:uint8()
					end

					-- write picture byte and move down by one line in the picture
					local base_ptr =
						output_pixels
						+ (y_lump * lump_expanded)
						+ (y_lumpline * line_expanded)
						+ (x_byte * 8)
					if base_ptr < output_pixels or (base_ptr + 8) > (output_pixels + output_len) then
						error('out of bounds!' .. (base_ptr - output_pixels))
					end
					for bzt = 0, 7 do
						if 1 == bit.band(1, bit.rshift(pic_byte, 7-bzt)) then
							base_ptr[bzt] = bit.bor(base_ptr[bzt], bit.lshift(1, bp))
						end
					end

					-- if we've run out of RLE bits, check the POINTS bits to see if a new RLE byte is needed
					rbit = rbit - 1
					if rbit < 0 then
						rbit = 7
						if 0 ~= bit.band(points_byte, bit.lshift(1, rrbit)) then
							rle_byte = rle:uint8()
						end
						rrbit = rrbit - 1
						if rrbit < 0 then
							rrbit = 7
							points_byte = points:uint8()
						end
					end

				end
			end
		end
	end

	bank.pic.data = ffi.string(output_pixels, output_len)
end

function reader_proto:screen_header(screen)
	assert( self:int32be() == bit.tobit(0x12031990), 'picture bank: bad screen header ID' )
	screen.width = self:int16be()
	screen.height = self:int16be()
	screen.hardware_x = self:int16be()
	screen.hardware_y = self:int16be()
	screen.hardware_width = self:int16be()
	screen.hardware_height = self:int16be()
	self:skip(4) -- unknown short[2]
	screen.hardware_mode = self:int16be() -- HAM, hires, interlaced
	screen.color_count = self:int16be()
	screen.bitplane_count = self:int16be()
	screen.palette = self:amiga_colorx_palette()
end

function reader_proto:amiga_colorx_palette()
	local palbuf = {}
	for i = 1, 32 do
		local color = self:int16be()
		local r = bit.rshift(bit.band(color, 0xF00), 8)
		local g = bit.rshift(bit.band(color, 0x0F0), 4)
		local b =            bit.band(color, 0x00F)
		palbuf[i] = string.char(
			bit.bor(r, bit.lshift(r, 4)), 
			bit.bor(g, bit.lshift(g, 4)), 
			bit.bor(b, bit.lshift(b, 4)))
	end
	return table.concat(palbuf)
end

function reader_proto:picture_header(pic)
	local base = self:pos()
	assert( self:int32be() == bit.tobit(0x06071963), 'picture bank: bad picture header ID' )
	pic.screen_x = self:int16be()
	pic.screen_y = self:int16be()
	pic.width_bytes = self:int16be()
	pic.height_linelumps = self:int16be()
	pic.lines_per_lump = self:int16be()
	pic.bitplanes = self:int16be()
	pic.rle_pos = base + self:int32be()
	pic.points_pos = base + self:int32be()
	pic.picture_pos = self:pos()
end

return format
