
local bit = require 'bit'
local ffi = require 'ffi'
local R = require 'denzquix.packland.reader'

local format = {}

function format.dbinit(db)

	assert(db:exec [[

		CREATE TABLE IF NOT EXISTS gremlin_video (
			dbid INTEGER PRIMARY KEY,
			frames_per_second INTEGER,

			video_width INTEGER,
			video_height INTEGER,
			video_bits_per_pixel INTEGER,
			video_palette BLOB,

			audio_bytes_per_sample INTEGER,
			audio_sample_rate INTEGER,
			audio_channels INTEGER,
			audio_is_dpcm INTEGER
		);

		CREATE TABLE IF NOT EXISTS gremlin_video_frame (
			dbid INTEGER PRIMARY KEY,
			video_dbid INTEGER NOT NULL,
			sequence INTEGER,
			pixel_data BLOB,
			audio_data BLOB,

			FOREIGN KEY (video_dbid) REFERENCES gremlin_video(dbid)
		);

		CREATE INDEX gremlin_video_frame_sequence ON gremlin_video_frame (video_dbid, sequence);

		CREATE TABLE IF NOT EXISTS palette_change (
			frame_dbid INTEGER NOT NULL,
			new_palette BLOB,
			FOREIGN KEY (frame_dbid) REFERENCES gremlin_video_frame(dbid)
		);

	]])

end

function format.todb(intype, inpath, db)
	local data = R.fromfile(inpath)

	data:inject 'bindata'

	assert( data:expectBlob('\148\025\017\041'), 'GDV file header not found' )

	local video = {}
	local audio = {}

	data:skip(2) -- unused short

	video.frame_count       = data:uint16le()
	video.frames_per_second = data:uint16le()

	do
		local packed = data:uint16le()
		audio.is_dpcm = (bit.band(packed, 8) ~= 0)
		if bit.band(packed, 4) == 0 then
			audio.bytes_per_sample = 1
		else
			audio.bytes_per_sample = 2
		end
		if bit.band(packed, 2) == 0 then
			audio.channels = 1 -- mono
		else
			audio.channels = 2 -- stereo
		end
		audio.is_present = (bit.band(packed, 1) ~= 0)
	end

	audio.sample_rate = data:uint16le()

	do
		local packed = data:uint16le()
		local bpp_enum = bit.band(packed, 7)
		if bpp_enum == 1 then
			video.bits_per_pixel = 8
		elseif bpp_enum == 2 then
			video.bits_per_pixel = 15
		elseif bpp_enum == 3 then
			video.bits_per_pixel = 16
		elseif bpp_enum == 4 then
			video.bits_per_pixel = 24
		end
	end

	video.max_frame_size = data:uint16le()

	video.is_present = (video.max_frame_size ~= 0)

	data:uint16le()

	video.width = data:uint16le()
	video.height = data:uint16le()

	if video.is_present then
		if video.bits_per_pixel == 8 then
			video.palette = data:blob(256 * 3)
		else
			error('only 8-bit video is supported')
		end
	end

	if audio.is_present then
		audio.chunk_size = math.ceil(
			math.floor(audio.sample_rate / video.frames_per_second)
			* audio.channels
			* audio.bytes_per_sample)
		if audio.is_dpcm then
			audio.chunk_size = audio.chunk_size / 2
		end
	end

	do
		format.dbinit(db)

		local exec_add_video = assert(db:prepare [[

			INSERT INTO gremlin_video (
				frames_per_second,

				video_width,
				video_height,
				video_bits_per_pixel,
				video_palette,

				audio_bytes_per_sample,
				audio_sample_rate,
				audio_channels,
				audio_is_dpcm)
			VALUES (
				:frames_per_second,

				:video_width,
				:video_height,
				:video_bits_per_pixel,
				:video_palette,

				:audio_bytes_per_sample,
				:audio_sample_rate,
				:audio_channels,
				:audio_is_dpcm)

		]])

		assert( exec_add_video:bind_int(':frames_per_second',    video.frames_per_second) )
		if video.is_present then
			assert( exec_add_video:bind_int(':video_width',          video.width            ) )
			assert( exec_add_video:bind_int(':video_height',         video.height           ) )
			assert( exec_add_video:bind_int(':video_bits_per_pixel', video.bits_per_pixel   ) )
			assert( exec_add_video:bind_blob(':video_palette',       video.palette          ) )
		else
			assert( exec_add_video:bind_null(':video_width'          ) )
			assert( exec_add_video:bind_null(':video_height'         ) )
			assert( exec_add_video:bind_null(':video_bits_per_pixel' ) )
			assert( exec_add_video:bind_null(':video_palette'        ) )
		end

		if audio.is_present then
			assert( exec_add_video:bind_int(':audio_bytes_per_sample', audio.bytes_per_sample) )
			assert( exec_add_video:bind_int(':audio_sample_rate',      audio.sample_rate     ) )
			assert( exec_add_video:bind_int(':audio_channels',         audio.channels        ) )
			assert( exec_add_video:bind_bool(':audio_is_dpcm',         audio.is_dpcm         ) )
		else
			assert( exec_add_video:bind_null(':audio_bytes_per_sample') )
			assert( exec_add_video:bind_null(':audio_sample_rate'     ) )
			assert( exec_add_video:bind_null(':audio_channels'        ) )
			assert( exec_add_video:bind_null(':audio_is_dpcm'         ) )
		end

		assert( assert( exec_add_video:step() ) == 'done' )

		assert( exec_add_video:finalize() )
	end

	local video_dbid = db:last_insert_rowid()

	local pixel_buffer_size = video.width * video.height
	local pixel_buffer = ffi.new('uint8_t[' .. pixel_buffer_size .. ']')

	local pixel_start = ffi.cast('uint8_t*', pixel_buffer)
	local pixel_pos = 0

	local video_width = video.width
	local video_height = video.height

	local half_buffer = setmetatable({}, {
		__index = function(self, pos)
			local x = pos % video_width
			pos = ((pos - x) * 2) + x
			return pixel_buffer[pos]
		end;
		__newindex = function(self, pos, val)
			local x = pos % video_width
			pos = ((pos - x) * 2) + x
			pixel_buffer[pos] = val
			pixel_buffer[pos + video_width] = val
		end;
	})

	local half_width = math.floor(video_width/2)

	local quarter_buffer = setmetatable({}, {
		__index = function(self, pos)
			local x = pos % half_width
			pos = ((pos - x) * 2) + (x * 2)
			return pixel_buffer[pos]
		end;
		__newindex = function(self, pos, val)
			local x = pos % video_width
			pos = ((pos - x) * 2) + (x * 2)
			pixel_buffer[pos] = val
			pixel_buffer[pos + 1] = val
			pixel_buffer[pos + video_width] = val
			pixel_buffer[pos + video_width + 1] = val
		end;
	})

	local current_buffer, current_buffer_size

	local function set_resolution_mode(mode)
		if mode == 'full' then
			current_buffer = pixel_buffer
			current_buffer_size = pixel_buffer_size
		elseif mode == 'half' then
			current_buffer = half_buffer
			current_buffer_size = math.floor(pixel_buffer_size/2)
		elseif mode == 'quarter' then
			current_buffer = quarter_buffer
			current_buffer_size = math.floor(pixel_buffer_size/4)
		else
			error('unknown resolution mode', 2)
		end
	end

	set_resolution_mode 'full'

	local function video_clear(v)
		ffi.fill(pixel_buffer, pixel_buffer_size, v)
	end

	local function set_video_pos(pos)
		pixel_pos = pos
	end

	local function get_video_pos()
		return pixel_pos
	end

	local function video_advance(relative_offset)
		pixel_pos = pixel_pos + relative_offset
	end

	local function write_pixel(px)
		if pixel_pos < 0 or pixel_pos >= current_buffer_size then
			error('attempt to write pixel data out of bounds', 2)
		end
		current_buffer[pixel_pos] = px
		pixel_pos = pixel_pos + 1
	end

	local function read_pixel(offset)
		local read_pos = pixel_pos + offset
		if read_pos < 0 or read_pos >= current_buffer_size then
			error('attempt to read pixel data out of bounds', 2)
		end
		return current_buffer[read_pos]
	end

	local function repeat_pixel(px, n)
		for i = 1, n do
			write_pixel(px)
		end
	end

	local function copy_pixels(offset, length)
		for i = 1, length do
			write_pixel(read_pixel(offset))
		end
	end

	local new_palette
	local function read_palette()
		new_palette = data:blob(256 * 3)
	end

	-- bit data utility
	local queue, qsize
	local function init_bit_reader()
		queue = data:int32le()
		qsize = 16
	end
	local function read_bits(n)
		local retval = bit.band(queue, bit.lshift(1, n) - 1)
		queue = bit.rshift(queue, n)
		qsize = qsize - n
	 	if qsize <= 0 then
			qsize = qsize + 16
			queue = bit.bor(queue, bit.lshift(data:uint16le(), qsize))
		end
		return retval
	end

	local function find_color_for_invalid_offset(offset)
		local result = bit.band(0xFE, bit.rshift(bit.bnot(offset), 3))
		local lastbit = bit.band(0xF, offset)
		if lastbit == 0 then
			result = bit.band(0xFF, result + 2)
		elseif lastbit <= 8 then
			result = bit.band(0xFF, result + 1)
		end
		return result
	end

	-- frame decoders
	local frame_decoders = {}

	frame_decoders[0] = function(frame)
		read_palette()
	end

	frame_decoders[1] = function(frame)
		read_palette()
		video_clear(0)
	end

	frame_decoders[3] = function(frame)
		-- do nothing!
	end

	local decoder_6_subdecoders = {}

	decoder_6_subdecoders[0] = function()
		if read_bits(1) == 0 then
			write_pixel(data:uint8())
			return
		end
		local length = 2
		local count = 0
		local step
		repeat
			count = count + 1
			step = read_bits(count)
			length = length + step
		until step ~= bit.lshift(1, count) - 1
		for i = 1, length do
			write_pixel(data:uint8())
		end
	end

	decoder_6_subdecoders[1] = function()
		if read_bits(1) == 0 then
			video_advance(read_bits(4) + 2)
			return
		end
		local b = data:uint8()
		if bit.band(b, 0x80) == 0 then
			video_advance(b + 18)
			return
		end
		local b2 = data:uint8()
		video_advance(bit.bor(bit.lshift(bit.band(b, 0x7F), 8), b2) + 146)
	end

	decoder_6_subdecoders[2] = function()
		local subTag = read_bits(2)
		if subTag == 3 then
			local b = data:uint8()
			local length = 2
			if bit.band(b, 0x80) == 0x80 then
				length = 3
			end
			local offset = bit.band(b, 0x7F)
			if offset == 0 then
				if get_video_pos() == 0 then
					repeat_pixel(0xFF, length)
				else
					repeat_pixel(read_pixel(-1), length)
				end
				return
			end
			offset = offset + 1
			if offset > get_video_pos() then
				local set_pix = find_color_for_invalid_offset(offset - get_video_pos())
				repeat_pixel(set_pix, length)
				return
			end
			copy_pixels(-offset, length)
			return
		end
		local next_4 = read_bits(4)
		local offset = bit.bor(bit.lshift(next_4, 8), data:uint8())
		if subTag == 0 and offset == 0xFFF then
			return 'stop' -- end of stream
		end
		if subTag == 0 and offset > 0xF80 then
			local length
			length, offset = bit.band(offset, 0xF) + 2, bit.band(bit.rshift(offset, 4), 7)
			local px1 = read_pixel(-(offset + 1))
			local px2 = read_pixel(-offset)
			for i = 1, length do
				write_pixel(px1)
				write_pixel(px2)
			end
			return
		end
		local length = subTag + 3
		if offset == 0xFFF then
			if get_video_pos() == 0 then
				repeat_pixel(0xFF, length)
			else
				repeat_pixel(read_pixel(-1), length)
			end
			return
		end
		offset = 4096 - offset
		if offset > get_video_pos() then
			local set_pix = find_color_for_invalid_offset(offset - get_video_pos())
			repeat_pixel(set_pix, length)
			return
		end
		copy_pixels(-offset, length)
	end

	decoder_6_subdecoders[3] = function()
		local first_byte = data:uint8()
		local length = bit.rshift(first_byte, 4)
		if length == 15 then
			length = length + data:uint8()
		end
		length = length + 6
		local offset = bit.bor(bit.lshift(bit.band(first_byte, 0xF), 8), data:uint8())
		if offset == 0xFFF then
			if get_video_pos() == 0 then
				repeat_pixel(0xFF, length)
			else
				repeat_pixel(read_pixel(-1), length)
			end
			return
		end
		offset = 4096 - offset
		if offset > get_video_pos() then
			local set_pix = find_color_for_invalid_offset(offset-get_video_pos())
			repeat_pixel(set_pix, length)
			return
		end
		copy_pixels(-offset, length)
	end

	frame_decoders[6] = function(frame)
		set_video_pos(frame.offset)
		init_bit_reader()
		local subdecoder
		repeat
			subdecoder = decoder_6_subdecoders[read_bits(2)]
		until subdecoder() == 'stop'
	end

	local decoder_8_subdecoders = {}

	decoder_8_subdecoders[0] = decoder_6_subdecoders[0]

	decoder_8_subdecoders[1] = decoder_6_subdecoders[1]

	decoder_8_subdecoders[2] = decoder_6_subdecoders[2]

	decoder_8_subdecoders[3] = function()
		local first_byte = data:uint8()
		if bit.band(first_byte, 0xC0) == 0xC0 then
			local top_4 = read_bits(4)
			local next_byte = data:uint8()
			length = bit.band(first_byte, 0x3F) + 8
			offset = bit.bor(bit.lshift(top_4, 8), next_byte)
			copy_pixels(offset + 1, length)
			return
		end
		local length, offset
		if bit.band(first_byte, 0x80) == 0 then
			local bits_6_to_4 = bit.rshift(first_byte, 4)
			local bits_3_to_0 = bit.band(first_byte, 0xF)
			local next_byte = data:uint8()
			length = bits_6_to_4 + 6
			offset = bit.bor(bit.lshift(bits_3_to_0, 8), next_byte)
		else
			-- read bits BEFORE read byte!
			local top_4 = read_bits(4)
			local next_byte = data:uint8()
			length = 14 + bit.band(first_byte, 0x3F)
			offset = bit.bor(bit.lshift(top_4, 8), next_byte)
		end
		if offset == 0xFFF then
			if get_video_pos() == 0 then
				repeat_pixel(0xFF, length)
			else
				repeat_pixel(read_pixel(-1), length)
			end
			return
		end
		offset = 4096 - offset
		if offset > get_video_pos() then
			local set_pix = find_color_for_invalid_offset(offset-get_video_pos())
			repeat_pixel(set_pix, length)
			return
		end
		copy_pixels(-offset, length)
	end

	frame_decoders[8] = function(frame)
		set_video_pos(frame.offset)
		init_bit_reader()
		local subdecoder
		repeat
			subdecoder = decoder_8_subdecoders[read_bits(2)]
		until subdecoder() == 'stop'
	end

	local exec_add_frame = assert(db:prepare [[

		INSERT INTO gremlin_video_frame (
			sequence,
			video_dbid,
			pixel_data,
			audio_data)
		VALUES (
			:sequence,
			:video_dbid,
			:pixel_data,
			:audio_data)

	]])

	local exec_add_palette = assert(db:prepare [[

		INSERT INTO palette_change (
			frame_dbid,
			new_palette)
		VALUES (
			:frame_dbid,
			:new_palette)
	]])

	assert( exec_add_frame:bind_int64(':video_dbid', video_dbid) )

	if not audio.is_present then
		assert( exec_add_frame:bind_null(':audio_data') )
	end

	if not video.is_present then
		assert( exec_add_frame:bind_null(':pixel_data') )
	end

	local function output_video_frame()
		assert( exec_add_frame:bind_blob(':pixel_data', ffi.string(pixel_buffer, pixel_buffer_size)) )
	end

	for i = 1, video.frame_count do
		assert( exec_add_frame:bind_int(':sequence', i) )

		if audio.is_present then
			exec_add_frame:bind_blob(':audio_data', data:blob(audio.chunk_size))
		end
		
		if video.is_present then
			if not data:expectBlob('\5\19') then
				error('header for video frame #' .. i .. ' not found')
			end
			local frame = {}
			frame.size = data:uint16le()
			do
				local packed = data:int32le()
				frame.encoding = bit.band(packed, 15)
				frame.offset = bit.rshift(packed, 8)
				frame.half_resolution_mode = bit.band(packed, 32) == 32
				frame.quarter_resolution_mode = bit.band(packed, 16) == 16
				frame.show = bit.band(packed, 128) == 0
			end
			frame.start = data:pos()
			local decode = frame_decoders[frame.encoding]
			if not decode then
				error('frame #' .. i .. ' has unsupported encoding type: ' .. frame.encoding)
			end
			if not frame.show then
				-- send the previous frame through again
				output_video_frame()
			end
			if frame.quarter_resolution_mode then
				set_resolution_mode('quarter')
			elseif frame.half_resolution_mode then
				set_resolution_mode('half')
			else
				set_resolution_mode('full')
			end
			decode(frame)
			if frame.show then
				output_video_frame()
			end
			if new_palette then
				assert( exec_add_palette:bind_int64(':frame_dbid', db:last_insert_rowid()) )
				assert( exec_add_palette:bind_blob(':new_palette', new_palette) )
				assert( assert( exec_add_palette:step() ) == 'done' )
				assert( exec_add_palette:reset() )
				new_palette = nil
			end
			data:pos('set', frame.start + frame.size)
		end

		assert( assert( exec_add_frame:step() ) == 'done' )
		assert( exec_add_frame:reset() )
	end

	assert( exec_add_frame:finalize() )
	assert( exec_add_palette:finalize() )
end

local function enc_uint16le(v)
	return string.char(bit.band(v, 0xff), bit.band(bit.rshift(v, 8), 0xff))
end

local function enc_uint8(v)
	return string.char(v)
end

function format.togif(db, outpath)
	local exec_get_video = assert(db:prepare [[

		SELECT dbid,
			frames_per_second,
			video_width,
			video_height,
			video_bits_per_pixel,
			video_palette
		FROM gremlin_video

	]])

	assert( assert(exec_get_video:step()) == 'row', 'no video found in file' )

	local video_dbid = exec_get_video:column_int64(0)
	local video_fps = exec_get_video:column_int(1)
	local video_width = exec_get_video:column_int(2)
	local video_height = exec_get_video:column_int(3)
	local video_bits_per_pixel = exec_get_video:column_int(4)
	local video_palette = exec_get_video:column_blob(5)

	assert( exec_get_video:finalize() )

	local f = assert(io.open(outpath, 'wb'))
	f:write 'GIF89a'

	-- logical screen descriptor
	local global_color_table_size = 256
	local original_palette_color_resolution = 8
	local sorted_palette = false
	local packed = bit.bor(
		(global_color_table_size == 0) and 0 or 0x80,
		bit.lshift(original_palette_color_resolution - 1, 4),
		sorted and 0x08 or 0x00,
		select(2, math.frexp(global_color_table_size - 1)) - 1
	)
	local background_color_index = 0
	local pixel_aspect_ratio = nil
	f:write(enc_uint16le(video_width))
	f:write(enc_uint16le(video_height))
	f:write(enc_uint8(packed))
	f:write(enc_uint8(background_color_index))
	f:write(enc_uint8(pixel_aspect_ratio or 0))

	f:write(video_palette)

	local exec_get_frame = assert(db:prepare [[

		SELECT pixel_data, palette_change.new_palette
		FROM gremlin_video_frame
		LEFT JOIN palette_change ON palette_change.frame_dbid = gremlin_video_frame.dbid
		WHERE video_dbid = :video_dbid
		ORDER BY sequence

	]])

	assert( exec_get_frame:bind_int64(':video_dbid', video_dbid) )

	while true do
		local result = assert( exec_get_frame:step() )
		if result == 'done' then
			break
		end
		assert(result == 'row')
		local pixel_data = exec_get_frame:column_blob(0)
		local new_palette = exec_get_frame:column_blob(1)

		-- graphic control extension
		f:write(enc_uint8(0x21)) -- extension introducer
		f:write(enc_uint8(0xF9)) -- graphic control label
		f:write(enc_uint8(4)) -- block size
		local transparent_color = nil
		local user_input = false
		local disposal_method = 0
		-- 0: no disposal specified
		-- 1: do not dispose, leave in place
		-- 2: restore to background color
		-- 3: restore to previous
		local packed = bit.bor(
			bit.lshift(disposal_method, 2),
			user_input and 0x02 or 0x00,
			transparent_color and 0x01 or 0x00
		)
		f:write(enc_uint8(packed))
		f:write(enc_uint16le(1000/video_fps))
		f:write(enc_uint8(transparent_color or 0))

		f:write(enc_uint8(0)) -- block terminator (zero-length block)

		-- image descriptor
		f:write(enc_uint8(0x2C))
		f:write(enc_uint16le(0)) -- left
		f:write(enc_uint16le(0)) -- top
		f:write(enc_uint16le(video_width))
		f:write(enc_uint16le(video_height))

		local palette_size = #(new_palette or '')
		local interlaced = false
		local sorted_palette = false

		if palette_size ~= 0 then
			palette_size = select(2, math.frexp(palette_size - 1)) - 1
		end

		local packed = bit.bor(
			palette and 0x80 or 0x00,
			interlaced and 0x40 or 0x00,
			sorted and 0x20 or 0x00,
			palette_size
		)
		f:write(enc_uint8(packed))

		if new_palette then
			f:write(new_palette)
		end

		-- image data
		f:write(enc_uint8(8)) -- minimum number of bits to represent color values

		local buf = {}
		local buf_byte = 0
		local buf_bits = 0
		local function write_bits(v, bits)
			buf_byte = bit.bor(buf_byte, bit.lshift(v, buf_bits))
			buf_bits = buf_bits + bits
			while buf_bits >= 8 do
				buf[#buf+1] = enc_uint8(bit.band(0xff, buf_byte))
				buf_byte = bit.rshift(buf_byte, 8)
				buf_bits = buf_bits - 8
			end
		end

		local function flush_bits()
			if buf_bits > 0 then
				buf[#buf+1] = enc_uint8(buf_byte)
			end
			for i = 1, #buf, 255 do
				local chunk = table.concat(buf, '', i, math.min(#buf, i+254))
				f:write(enc_uint8(#chunk))
				f:write(chunk)
			end
			f:write(enc_uint8(0))
		end

		local string_table = {}
		for i = 0, 255 do
			string_table[string.char(i)] = i
		end

		local clear_code = 256
		local end_code = 257
		local next_code = end_code + 1

		local codesize = 9

		write_bits(clear_code, codesize)
		
		local pattern = pixel_data:sub(1, 1)
		for j = 2, #pixel_data do
			local k = pixel_data:sub(j, j)
			local combo = pattern .. k
			if string_table[combo] then
				pattern = combo
			else
				codesize = select(2, math.frexp(next_code))
				if codesize == 13 then
					write_bits(clear_code, 12)
					codesize = 9
					string_table = {}
					for i = 0, 255 do
						string_table[string.char(i)] = i
					end
					write_bits(string_table[k], codesize)
					next_code = end_code + 1
				else
					string_table[combo] = next_code
					write_bits(string_table[pattern], codesize)
					next_code = next_code + 1
				end
				pattern = k
			end
		end

		write_bits(end_code, codesize)

		flush_bits()
	end

	assert( exec_get_frame:finalize() )

	f:write(enc_uint8(0x3B)) -- trailer byte

	f:close()

end

return format
