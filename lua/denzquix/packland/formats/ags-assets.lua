
local bit = require 'bit'
local ffi = require 'ffi'
local R = require 'denzquix.packland.reader'

-------------------------------------------------------------------------------

local format = {}

local reader_proto = {}

-------------------------------------------------------------------------------

function format.dbinit(db)
	db:exec [[

		CREATE TABLE IF NOT EXISTS file_store (
			dbid INTEGER PRIMARY KEY
		);

		CREATE TABLE IF NOT EXISTS file (
			dbid INTEGER PRIMARY KEY,
			store_dbid INTEGER NOT NULL,
			name TEXT NOT NULL,
			contents BLOB NOT NULL,
			FOREIGN KEY(store_dbid) REFERENCES file_store(dbid)
		);

		CREATE UNIQUE INDEX IF NOT EXISTS unique_file_name
		ON file(store_dbid, name);

	]]

	db:exec [[

		CREATE TABLE IF NOT EXISTS asset_pack (
			dbid INTEGER PRIMARY KEY,
			file_store_dbid INTEGER NOT NULL,
			container_name TEXT NULL,
			master_pack_dbid INTEGER NULL,
			FOREIGN KEY(file_store_dbid) REFERENCES file_store(dbid),
			FOREIGN KEY(master_pack_dbid) REFERENCES asset_pack(dbid)
		);

		CREATE UNIQUE INDEX IF NOT EXISTS unique_asset_pack_container
		ON asset_pack(master_pack_dbid, container_name);

	]]
end

function format.todb(intype, inpath, db)
	assert(intype == 'file', 'input must be a file (got ' .. intype .. ')')
	local reader = assert(R.fromfile(inpath))
	reader:inject('bindata')
	reader:inject(reader_proto)

	local assets = {master_path = inpath:match('[^\\/]+$')}
	reader:assets(assets)

	format.dbinit(db)

	db:exec [[

		INSERT INTO file_store DEFAULT VALUES

	]]

	local store_dbid = db:last_insert_rowid()

	db:exec [[

		INSERT INTO asset_pack (file_store_dbid) VALUES (last_insert_rowid());

		UPDATE asset_pack SET master_pack_dbid = last_insert_rowid() WHERE rowid = last_insert_rowid();

	]]

	local master_pack_dbid = db:last_insert_rowid()

	local container_dbids = {}

	local exec_add_container = db:prepare [[

		INSERT INTO asset_pack (file_store_dbid, master_pack_dbid, container_name)
		VALUES (last_insert_rowid(), :master_pack_dbid, :container_name)

	]]

	local exec_add_file = db:prepare [[

		INSERT INTO file (store_dbid, name, contents)
		SELECT file_store_dbid, :name, :contents
		FROM asset_pack WHERE dbid = :asset_pack_dbid

	]]

	for i, asset in ipairs(assets) do
		local pack_dbid
		local content
		if asset.container == nil then
			pack_dbid = master_pack_dbid
			reader:pos('set', assets.base + asset.offset)
			content = reader:blob(asset.length)
		else
			pack_dbid = container_dbids[asset.container]
			if pack_dbid == nil then
				db:exec [[

					INSERT INTO file_store DEFAULT VALUES

				]]
				exec_add_container:bind_int64(':master_pack_dbid', master_pack_dbid)
				exec_add_container:bind_text(':container_name', asset.container)
				assert(assert(exec_add_container:step()) == 'done')
				assert(exec_add_container:reset())
				pack_dbid = db:last_insert_rowid()
				container_dbids[asset.container] = pack_dbid
			end
			local f = assert(io.open(inpath:gsub('[^\\/]*$', '') .. asset.container, 'rb'))
			f:seek('set', asset.offset)
			content = f:read(asset.length)
			f:close()
		end
		exec_add_file:bind_text(':name', asset.name)
		exec_add_file:bind_blob(':contents', content)
		exec_add_file:bind_int64(':asset_pack_dbid', pack_dbid)
		assert(assert(exec_add_file:step()) == 'done')
		assert(exec_add_file:reset())
	end

	exec_add_container:finalize()
	exec_add_file:finalize()

end

-------------------------------------------------------------------------------

function reader_proto:assets(list)
	list.base = assert(self:assets_begin(), 'unable to find start of data')
	local version = self:uint8()
	local handler = self['assets_v'..version]
	if not handler then
		error('asset format version not supported: ' .. version)
	end
	return handler(self, list)
end

function reader_proto:assets_begin()
	local base = self:pos()
	if self:expectBlob 'CLIB' then
		self:skip(1)
		return base
	end
	self:pos('end', -16)
	local start = self:int32le()
	if not self:expectBlob 'CLIB\1\2\3\4SIGE' then
		self:pos('set', base)
		return nil
	end
	self:pos('set', start)
	if not self:expectBlob 'CLIB' then
		self:pos('set', base)
		return nil
	end
	self:skip(1)
	return start
end

function reader_proto:assets_v6(assets)
	assets.base = 0
	local modifier = self:uint8()
	self:skip(1)
	local file_count = self:int16le()
	self:skip(13) -- password dooberry
	for i = 1, file_count do
		local filename = self:blob(13)
		local buf = {}
		for j = 1, 12 do
			local c = bit.band(0xFF, string.byte(filename, j) - modifier)
			if c == 0 then
				break
			end
			buf[j] = string.char(c)
		end
		assets[i] = {name=table.concat(buf)}
	end
	for i = 1, file_count do
		assets[i].length = self:int32le()
	end
	self:skip(2 * #assets) -- flags & ratio
	assets[1].offset = self:pos()
	for i = 2, #assets do
		assets[i].offset = assets[i-1].offset + assets[i-1].length
	end
end

function reader_proto:assets_v10(assets)
	assert(self:expectBlob '\0', 'not first datafile in chain')

	local containers = {}
	for i = 0, self:int32le()-1 do
		local name = self:nullTerminated(20)
		if name:lower() == assets.master_path:lower() then
			containers[i] = name
		end
	end

	for i = 1, self:int32le() do
		local name = self:nullTerminated(25)
		assets[i] = {name = name}
	end

	for i = 1, #assets do
		assets[i].offset = self:int32le()
	end
	for i = 1, #assets do
		assets[i].length = self:int32le()
	end
	for i = 1, #assets do
		assets[i].container = containers[self:uint8()]
	end
end

function reader_proto:assets_v11(assets)
	assert(self:expectBlob '\0', 'not first datafile in chain')

	local containers = {}
	for i = 0, self:int32le()-1 do
		local name = self:nullTerminated(20)
		if name:lower() ~= assets.master_path:lower()
		and not name:lower():match('^ac2game%.ags$') then
			containers[i] = name
		end
	end

	for i = 1, self:int32le() do
		local name = self:masked_blob("My\001\222\004Jibzle", 25):match('^%Z*')
		assets[i] = {name = name}
	end

	for i = 1, #assets do
		assets[i].offset = self:int32le()
	end
	for i = 1, #assets do
		assets[i].length = self:int32le()
	end
	for i = 1, #assets do
		assets[i].container = containers[self:uint8()]
	end
end

reader_proto.assets_v15 = reader_proto.assets_v11

function reader_proto:masked_blob(mask, n)
	local buf = {}
	for i = 1, n do
		local b = self:uint8()
		local mb = mask:byte(((i-1) % #mask) + 1)
		buf[i] = string.char(bit.band(0xFF, b - mb))
	end
	return table.concat(buf)
end

function reader_proto:assets_v20(assets)
	assert(self:expectBlob '\0', 'not first datafile in chain')
	local containers = {}
	for i = 0, self:int32le()-1 do
		containers[i] = self:nullTerminated()
		if containers[i]:lower() == assets.master_path:lower() then
			containers[i] = nil
		end
	end
	for i = 1, self:int32le() do
		assets[i] = {name = self:masked_blob("My\001\222\004Jibzle", math.floor(self:int16le()/5))}
	end
	for _, asset in ipairs(assets) do
		asset.offset = self:int32le()
	end
	for _, asset in ipairs(assets) do
		asset.length = self:int32le()
	end
	for _, asset in ipairs(assets) do
		asset.container = containers[self:uint8()]
	end	
end

function reader_proto:assets_v21(assets)
	assert(self:expectBlob '\0', 'not first datafile in chain')

	self:crypto_init()

	local containers = {}
	for i = 0, self:crypto_int32le()-1 do
		containers[i] = self:crypto_nullTerminated()
		if containers[i]:lower() == assets.master_path:lower() then
			containers[i] = nil
		end
	end

	for i = 1, self:crypto_int32le() do
		assets[i] = {name = self:crypto_nullTerminated()}
	end
	for i = 1, #assets do
		assets[i].offset = self:crypto_int32le()
	end
	for i = 1, #assets do
		assets[i].length = self:crypto_int32le()
	end
	for i = 1, #assets do
		assets[i].container = containers[self:crypto_uint8()]
	end
end

function reader_proto:crypto_init()
	local seed = self:int32le() + 9338638

	local function crypto_next()
		seed = bit.tobit(seed * 214013 + 2531011)
		return bit.band(bit.rshift(seed, 16), 0x7FFF)
	end

	function self:crypto_uint8()
		return bit.band(0xFF, self:uint8() - crypto_next())
	end

	function self:crypto_int32le()
		local b1, b2, b3, b4 = self:uint8(4)
		b1 = bit.band(0xFF, b1 - crypto_next())
		b2 = bit.band(0xFF, b2 - crypto_next())
		b3 = bit.band(0xFF, b3 - crypto_next())
		b4 = bit.band(0xFF, b4 - crypto_next())
		return bit.bor(
			bit.lshift(b4, 24),
			bit.lshift(b3, 16),
			bit.lshift(b2, 8),
			b1)
	end

	function self:crypto_nullTerminated()
		local buf = {}
		while true do
			local b = self:uint8(1)
			b = bit.band(0xFF, b - crypto_next())
			if b == 0 then
				break
			end
			buf[#buf+1] = string.char(b)
		end
		return table.concat(buf)
	end
end

-------------------------------------------------------------------------------

return format
