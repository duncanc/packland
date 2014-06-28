
local lfs = require 'lfs'
local ffi = require 'ffi'
local D = require 'extern.sqlite3'

-------------------------------------------------------------------------------

local app = {}

local function lineargs(...)
	local p = {}
	for i = 1, select('#', ...) do
		local arg = select(i, ...)
		arg = arg:match('^%-(.+)$')
		if arg then
			local k,v = arg:match('^([^=]+)=(.*)$')
			if k then
				p[k] = v
			else
				p[arg] = true
			end
		end
	end
	return p
end

function app.extract(inpath, extraction, outpath)
	local ret_db = ffi.new 'sqlite3*[1]'
	local err = D.sqlite3_open(inpath, ret_db)
	if err ~= D.SQLITE_OK then
		error('unable to open database')
	end
	local db = ret_db[0]

	local select_file = assert(db:prepare [[

		SELECT contents FROM file WHERE name LIKE :name

	]])

	assert( select_file:bind_text(':name', extraction) )

	local result = assert(select_file:step())
	if result == 'done' then
		error('extractable not found: ' .. extraction)
	end
	assert(result == 'row')
	local data = select_file:column_blob(0)
	assert(select_file:finalize())

	if data ~= nil then
		local f = assert(io.open(outpath, 'wb'))
		f:write(data)
		f:close()
	end
end

function app.todb(format, inpath, outpath, ...)
	if not format and inpath and outpath then
		return app.info()
	end
	local format = require('denzquix.packland.formats.' .. format)
	local args = lineargs(...)
	local intype = lfs.attributes(inpath, 'mode')
	if intype == nil then
		error('nothing to open at: ' .. inpath)
	end
	local outtype = lfs.attributes(outpath, 'mode')
	local ret_db = ffi.new 'sqlite3*[1]'
	local err = D.sqlite3_open(outpath, ret_db)
	if err ~= D.SQLITE_OK then
		error('unable to open database')
	end
	local db = ret_db[0]

	assert( db:exec [[ BEGIN EXCLUSIVE TRANSACTION ]] )

	format.todb(intype, inpath, db, args)

	assert( db:exec [[ COMMIT ]] )
	
	db:close()
end

function app.togif(format, inpath, outpath)
	local format = require('denzquix.packland.formats.' .. format)
	if not format.togif then
		error('format does not support gif output')
	end

	local ret_db = ffi.new 'sqlite3*[1]'
	local err = D.sqlite3_open(inpath, ret_db)
	if err ~= D.SQLITE_OK then
		error('unable to open database')
	end
	local db = ret_db[0]

	format.togif(db, outpath)

	db:close()
end

function app.bmpdump(dbpath)
	local ret_db = ffi.new 'sqlite3*[1]'
	local err = D.sqlite3_open(dbpath, ret_db)
	if err ~= D.SQLITE_OK then
		error('unable to open database')
	end
	local db = ret_db[0]

	local exec_next_image = assert(db:prepare [[
		SELECT dbid, pixel_format, pixel_data, palette, width, height
		FROM bitmap
		WHERE width>0 AND height>0
	]])

	while assert( exec_next_image:step() ) == 'row' do
		local dbid = exec_next_image:column_int64(0)
		local pixel_format = exec_next_image:column_text(1)
		local pixel_data = exec_next_image:column_blob(2)
		local palette = exec_next_image:column_blob(3)
		local width = exec_next_image:column_int(4)
		local height = exec_next_image:column_int(5)

		local path = string.format('bitmap_%d.bmp', tonumber(dbid))
		local f = assert( io.open(path, 'wb') )

		local function enc_int32le(v)
			return string.char(
				bit.band(v, 0xff),
				bit.band(bit.rshift(v, 8), 0xff),
				bit.band(bit.rshift(v, 16), 0xff),
				bit.band(bit.rshift(v, 24), 0xff))
		end

		local function enc_uint16le(v)
			return string.char(bit.band(v, 0xff), bit.band(bit.rshift(v, 8), 0xff))
		end

		local header_1_size = 14
		local header_2_size = 40 -- 108
		local palette_size = (256 * 4)
		local row_size = width
		while (row_size % 4) ~= 0 do
			row_size = row_size + 1
		end

		-- header 1
		f:write('BM')
		f:write( enc_int32le(header_1_size + header_2_size + palette_size + (row_size * height)) )
		f:write('\0\0\0\0')
		f:write( enc_int32le(header_1_size + header_2_size + palette_size) )

		-- header 2
		f:write( enc_int32le(header_2_size) )
		f:write( enc_int32le(width) )
		f:write( enc_int32le(height) )
		f:write( enc_uint16le(1) ) -- planes
		f:write( enc_uint16le(8) ) -- bits per pixel
		f:write( enc_int32le(0) ) -- compression (0 = none)
		f:write( enc_int32le(width * height) ) -- size of bitmap
		f:write( enc_int32le(2835) ) -- x pixels per meter
		f:write( enc_int32le(2835) ) -- y pixels per meter
		f:write( enc_int32le(256) ) -- colours used
		f:write( enc_int32le(256) ) -- important colours

		for i = 0, 255 do
			local pal = palette:sub(1 + i * 3, 3 + i * 3) or ''
			pal = string.reverse(pal) -- BGR
			f:write(pal .. string.rep('\0', 4 - #pal))
		end

		local extra = width % 4
		if extra ~= 0 then
			extra = 4 - extra
		end
		extra = string.rep('\0', extra)

		for y = height-1, 0, -1 do
			local pos = 1 + (width * y)
			local row = pixel_data:sub(pos, pos + width - 1)
			f:write(row)
			f:write(extra)
		end

		f:close()
	end

	assert( exec_next_image:finalize() )
end

function app.bmpreplace(format, dbpath)
	local format = require('denzquix.packland.formats.' .. format)
	if not format.bmpreplace then
		error('format does not support bmpreplace feature')
	end
	local ret_db = ffi.new 'sqlite3*[1]'
	local err = D.sqlite3_open(dbpath, ret_db)
	if err ~= D.SQLITE_OK then
		error('unable to open database')
	end
	local db = ret_db[0]

	format.bmpreplace(db)
end

function app.wavdump(dbpath)
	local ret_db = ffi.new 'sqlite3*[1]'
	local err = D.sqlite3_open(dbpath, ret_db)
	if err ~= D.SQLITE_OK then
		error('unable to open database')
	end
	local db = ret_db[0]

	local function enc_int32le(v)
		return string.char(
			bit.band(v, 0xff),
			bit.band(bit.rshift(v, 8), 0xff),
			bit.band(bit.rshift(v, 16), 0xff),
			bit.band(bit.rshift(v, 24), 0xff))
	end

	local function enc_uint16le(v)
		return string.char(bit.band(v, 0xff), bit.band(bit.rshift(v, 8), 0xff))
	end

	local exec_next_sound = assert(db:prepare [[
		SELECT dbid, sample_format, sample_rate, sample_data, channels
		FROM audio_sample
	]])

	while assert( exec_next_sound:step() ) == 'row' do
		local dbid = exec_next_sound:column_int64(0)
		local sample_format = exec_next_sound:column_text(1)
		local sample_rate = exec_next_sound:column_int(2)
		local sample_data = exec_next_sound:column_blob(3)
		local channels = exec_next_sound:column_int(4)

		local path = string.format('sound_%d.wav', tonumber(dbid))
		local f = assert( io.open(path, 'wb') )

		f:write 'RIFF'
		f:write (enc_int32le(36 + #sample_data))
		f:write 'WAVE'
		f:write 'fmt '
		f:write (enc_int32le(16)) -- 'fmt ' chunk size
		f:write (enc_uint16le(1)) -- PCM
		f:write (enc_uint16le(channels))
		f:write (enc_int32le(sample_rate))
		local bits_per_sample = assert(tonumber(sample_format:match('%d+')))
		f:write (enc_int32le(sample_rate * channels * bits_per_sample/8))
		f:write (enc_uint16le(channels * bits_per_sample/8))
		f:write (enc_uint16le(bits_per_sample))
		f:write 'data'
		f:write (enc_int32le(#sample_data))

		if sample_format == 'i8' then
			-- WAV requires 8-bit audio data to be unsigned
			for i = 1, #sample_data do
				local b = bit.arshift(bit.lshift(string.byte(sample_data, i), 24), 24)
				f:write(string.char(b + 128))
			end
		else
			f:write(sample_data)
		end

		f:close()
	end

	assert( exec_next_sound:finalize() )
end

function app.info()
	print ''
	print 'options:'
	print '  luajit packland.lua todb ags-assets audio.vox audiovox.db'
	print '  luajit packland.lua extract assetpack.db asset.dat extractedasset.dat'
	print '  luajit packland.lua todb ags-room-chunks room2.crm room2.db'
	print '  luajit packland.lua todb ags-sprites acsprset.spr sprites.db'
end

-------------------------------------------------------------------------------

local params = {...}

local action = params[1] or 'info'
if app[action] then
	app[action](select(2, ...))
else
	io.stderr:write('unknown action: ' .. params[1] .. '\n')
end
