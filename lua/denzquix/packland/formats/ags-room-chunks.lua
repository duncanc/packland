
local bit = require 'bit'
local ffi = require 'ffi'
local R = require 'denzquix.packland.reader'

-------------------------------------------------------------------------------

local format = {}

local reader_proto = {}

-------------------------------------------------------------------------------

local BLOCKTYPE_MAIN = 1
local BLOCKTYPE_SCRIPT = 2
local BLOCKTYPE_COMPSCRIPT = 3
local BLOCKTYPE_COMPSCRIPT2 = 4
local BLOCKTYPE_OBJECTNAMES = 5
local BLOCKTYPE_ANIMBKGRND = 6
local BLOCKTYPE_COMPSCRIPT3 = 7
local BLOCKTYPE_PROPERTIES = 8
local BLOCKTYPE_OBJECTSCRIPTNAMES = 9
local BLOCKTYPE_EOF = 0xFF

local chunk_names = {
	[BLOCKTYPE_MAIN] = 'main';
	[BLOCKTYPE_SCRIPT] = 'source-code';
	[BLOCKTYPE_COMPSCRIPT] = 'compiled-code-v1';
	[BLOCKTYPE_COMPSCRIPT2] = 'compiled-code-v2';
	[BLOCKTYPE_COMPSCRIPT3] = 'compiled-code-v3';
	[BLOCKTYPE_OBJECTNAMES] = 'object-names';
	[BLOCKTYPE_OBJECTSCRIPTNAMES] = 'object-script-names';
	[BLOCKTYPE_PROPERTIES] = 'properties';
	[BLOCKTYPE_ANIMBKGRND] = 'background-animation';
}

-------------------------------------------------------------------------------

function format.dbinit(db)
	db:exec [[

		CREATE TABLE IF NOT EXISTS room_chunk_store (
			dbid INTEGER PRIMARY KEY,
			room_idx INTEGER,
			format_version INTEGER
		);

		CREATE TABLE IF NOT EXISTS room_chunk (
			dbid INTEGER PRIMARY KEY,
			store_dbid INTEGER NOT NULL,
			chunk_type TEXT NOT NULL,
			content BLOB,
			FOREIGN KEY (store_dbid) REFERENCES room_chunk_store(dbid)
		);

	]]
end

function format.todb(intype, inpath, db)
	assert(intype == 'file', 'input must be a file (got ' .. intype .. ')')
	local reader = assert(R.fromfile(inpath))
	reader:inject('bindata')
	reader:inject(reader_proto)

	local filename = inpath:match('[^\\/]*$'):lower()
	local number
	if filename:match('intro') then
		number = 0
	else
		number = tonumber(filename:lower():match('room(%d+)'))
	end

	local version = reader:int16le()

	format.dbinit(db)

	local store_dbid
	do
		local exec_add_store = db:prepare [[

			INSERT INTO room_chunk_store (room_idx, format_version)
			VALUES (:room_idx, :format_version)

		]]

		if number == nil then
			assert( exec_add_store:bind_null(':room_idx') )
		else
			assert( exec_add_store:bind_int(':room_idx', number) )
		end
		assert( exec_add_store:bind_int(':format_version', version) )
		assert( assert(exec_add_store:step()) == 'done' )
		assert( exec_add_store:reset() )
		assert( exec_add_store:finalize() )

		store_dbid = db:last_insert_rowid()
	end

	local exec_add_chunk = db:prepare [[

		INSERT INTO room_chunk (store_dbid, chunk_type, content)
		VALUES (:store_dbid, :chunk_type, :content)

	]]

	assert( exec_add_chunk:bind_int64(':store_dbid', store_dbid) )

	-- NOTE: unlike other masks, the bytes are ADDED, not subtracted
	function reader:masked_blob(mask, n)
		local buf = {}
		for i = 1, n do
			local b = self:uint8()
			local mb = mask:byte(((i-1) % #mask) + 1)
			buf[i] = string.char(bit.band(0xFF, b + mb))
		end
		return table.concat(buf)
	end

	if version <= 3 then

		assert( exec_add_chunk:bind_text(':chunk_type', chunk_names[BLOCKTYPE_MAIN]) )
		assert( exec_add_chunk:bind_blob(':content', reader:blob('*a')) )
		assert( assert(exec_add_chunk:step()) == 'done' )
		assert( exec_add_chunk:reset() )
		
	else

		while true do
			local chunk_id = reader:uint8()
			if chunk_id == BLOCKTYPE_EOF then
				break
			end
			local chunk_length = reader:int32le()
			local chunk
			if chunk_id == BLOCKTYPE_SCRIPT then
				chunk = reader:masked_blob('Avis Durgan', reader:int32le())
			else
				chunk = reader:blob(chunk_length)
			end
			assert( exec_add_chunk:bind_text(':chunk_type', chunk_names[chunk_id] or tostring(chunk_id)) )
			assert( exec_add_chunk:bind_blob(':content', chunk) )
			assert( assert(exec_add_chunk:step()) == 'done' )
			assert( exec_add_chunk:reset() )
		end

	end	

	assert( exec_add_chunk:finalize() )
end

-------------------------------------------------------------------------------

return format
