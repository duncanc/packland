

local bit = require 'bit'
local R = require 'denzquix.packland.reader'

local format = {}

function format.dbinit(db)

	assert(db:exec [[

		CREATE TABLE IF NOT EXISTS entry (
			dbid INTEGER PRIMARY KEY,
			lipsync_data TEXT,
			creative_voice BLOB
		);

	]])

end

function format.todb(intype, inpath, db)
	assert(intype == 'file')
	local reader = assert(R.fromfile(inpath))
	reader:inject 'bindata'

	format.dbinit(db)

	assert( reader:expectBlob 'SOU \0\0\0\0' )

	local exec_add_entry = assert(db:prepare [[

		INSERT INTO entry (lipsync_data, creative_voice)
		VALUES (:lipsync_data, :creative_voice)

	]])

	while true do
		local block = reader:blob(4)
		if block == '' or block == nil then
			break
		end
		assert(block == 'VCTL')
		local count = (reader:uint32be() - 8) / 2
		local lipsync_data = {}
		for i = 1, count do
			lipsync_data[i] = tostring( reader:uint16le() )
		end
		if lipsync_data[1] then
			assert( exec_add_entry:bind_text(':lipsync_data', table.concat(lipsync_data, '\n')) )
		else
			assert( exec_add_entry:bind_null(':lipsync_data') )
		end
		local voc_start_pos = reader:pos()
		assert( reader:expectBlob 'Creative Voice File\x1A' )
		local main_header_length = reader:uint16le()
		reader:pos('set', voc_start_pos + main_header_length)
		print(reader:pos())
		while reader:blob(1) ~= '\0' do
			local block_size = reader:uint24le()
			print(reader:pos(), block_size)
			reader:pos('cur', block_size)
		end
		local voc_length = reader:pos() - voc_start_pos
		reader:pos('set', voc_start_pos)
		assert( exec_add_entry:bind_blob(':creative_voice', reader:blob(voc_length)) )
		print('done', reader:pos())

		assert( assert( exec_add_entry:step() ) == 'done' )
		assert( exec_add_entry:reset() )
	end

	assert( exec_add_entry:finalize() )
end

return format
