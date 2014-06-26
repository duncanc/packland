
local R = require 'denzquix.packland.reader'

local format = {}

function format.dbinit(db)

	assert(db:exec [[

		CREATE TABLE IF NOT EXISTS audio_sample (
			dbid INTEGER PRIMARY KEY,
			sample_rate INTEGER,
			sample_format TEXT,
			sample_data BLOB
		);

		CREATE TABLE IF NOT EXISTS iff_8svx (
			dbid INTEGER PRIMARY KEY,
			sample_dbid INTEGER,
			high_octave_one_shot_samples INTEGER,
			high_octave_repeat_samples INTEGER,
			high_octave_samples_per_cycle INTEGER,
			waveform_octaves_in_sample INTEGER,
			volume INTEGER,

			FOREIGN KEY (sample_dbid) REFERENCES audio_sample(dbid)
		);

	]])

end

local reader_proto = {}

function format.todb(intype, inpath, db, context)
	local reader = R.fromfile(inpath)
	reader:inject 'bindata'
	reader:inject(reader_proto)

	local iff = {}
	reader:iff_form(iff)

	format.dbinit(db)

	if iff.type == '8SVX' then

		local sample_data
		for _, chunk in ipairs(iff) do
			if chunk.type == 'BODY' then
				sample_data = chunk.data
				break
			end
		end

		local exec_add_sample = assert(db:prepare [[

			INSERT INTO audio_sample (sample_rate, sample_format, sample_data)
			VALUES (:sample_rate, :sample_format, :sample_data)

		]])

		assert( exec_add_sample:bind_int(':sample_rate', iff.sample_rate) )
		assert( exec_add_sample:bind_text(':sample_format', iff.sample_format) )
		assert( exec_add_sample:bind_blob(':sample_data', sample_data) )

		assert( assert( exec_add_sample:step() ) == 'done' )
		assert( exec_add_sample:finalize() )

		local sample_dbid = db:last_insert_rowid()

		local exec_add_8svx = assert(db:prepare [[

			INSERT INTO iff_8svx (
				sample_dbid,
				high_octave_one_shot_samples,
				high_octave_repeat_samples,
				high_octave_samples_per_cycle,
				waveform_octaves_in_sample,
				volume)
			VALUES (
				:sample_dbid,
				:high_octave_one_shot_samples,
				:high_octave_repeat_samples,
				:high_octave_samples_per_cycle,
				:waveform_octaves_in_sample,
				:volume)

		]])

		assert( exec_add_8svx:bind_int64(':sample_dbid', sample_dbid) )
		assert( exec_add_8svx:bind_int(':high_octave_one_shot_samples', iff.high_octave_one_shot_samples) )
		assert( exec_add_8svx:bind_int(':high_octave_repeat_samples', iff.high_octave_repeat_samples) )
		assert( exec_add_8svx:bind_int(':high_octave_samples_per_cycle', iff.high_octave_samples_per_cycle) )
		assert( exec_add_8svx:bind_int(':waveform_octaves_in_sample', iff.waveform_octaves_in_sample) )
		assert( exec_add_8svx:bind_int(':volume', iff.volume) )

		assert( assert( exec_add_8svx:step() ) == 'done' )
		assert( exec_add_8svx:finalize() )

	end
end

function reader_proto:iff_form(iff)
	assert( self:expectBlob 'FORM', 'IFF header not found' )
	local data = self:blob( self:uint32be() )
	local data_reader = R.fromstring(data)
	data_reader:inject 'bindata'
	data_reader:inject(reader_proto)
	local end_pos = data_reader:pos('end')
	data_reader:pos('set', 0)
	iff.type = data_reader:blob(4)
	while data_reader:pos() < end_pos do
		local chunk_type = data_reader:blob(4)
		local chunk_len = data_reader:uint32be()
		local chunk_data = data_reader:blob(chunk_len)
		local chunk_handler = data_reader['iff_chunk_'..chunk_type]
		if chunk_handler then
			local chunk_reader = R.fromstring(chunk_data)
			chunk_reader:inject 'bindata'
			chunk_reader:inject(reader_proto)
			chunk_handler(chunk_reader, iff)
		else
			-- "BODY" (signed bytes -128 to 127)
			-- "NAME"
			-- "AUTH"
			-- "ANNO"
			-- "(c) "
			iff[#iff+1] = {type=chunk_type, data=chunk_data}
		end
	end
end

function reader_proto:iff_chunk_VHDR(iff)
	iff.high_octave_one_shot_samples = self:uint32be()
	iff.high_octave_repeat_samples = self:uint32be()
	iff.high_octave_samples_per_cycle = self:uint32be() -- if repeating
	iff.sample_rate = self:uint16be()
	iff.waveform_octaves_in_sample = self:uint8()
	iff.compression = self:uint8()
	iff.sample_format = 'i8'
	if iff.compression == 0 then
		iff.compression = nil
	elseif iff.compression == 1 then
		error 'TODO: fibonacci delta encoding'
		iff.compression = 'fibonacci_delta_encoding'
	else
		error 'unsupported compression type'
	end
	iff.volume = self:uint32be() -- 65536 = full volume
end

function reader_proto:iff_chunk_BMHD(iff)
	-- bitmap header
	iff.width = self:uint16be()
	iff.height = self:uint16be()
	iff.x = self:uint16be()
	iff.y = self:uint16be()
	iff.bitplanes = self:uint8()
	iff.masking = self:uint8()
	iff.compression = self:uint8()
	iff.padding = self:uint8() -- always 0?
	iff.transparency = self:uint16be()
	iff.aspect_ratio_x = self:uint8()
	iff.aspect_ratio_y = self:uint8()
	iff.page_width = self:uint16be()
	iff.page_height = self:uint16be()
end

function reader_proto:iff_chunk_CMAP(iff)
	local start = self:pos()
	local stop = self:pos('end')
	self:pos(start)
	local count = math.floor((stop - start) / 3)
	iff.palette = self:blob(count * 3)
end

return format
