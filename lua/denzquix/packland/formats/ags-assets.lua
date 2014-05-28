
local bit = require 'bit'
local ffi = require 'ffi'
local R = require 'denzquix.packland.reader'

-------------------------------------------------------------------------------

local format = {}

local reader_proto = {}

-------------------------------------------------------------------------------

function format.dbinit(db)
	db:exec [[

		CREATE TABLE IF NOT EXISTS filesystem (
			id INTEGER PRIMARY KEY
		);

		CREATE TABLE IF NOT EXISTS file (
			filesystem_id INTEGER NOT NULL,
			name TEXT NOT NULL,
			contents BLOB NOT NULL,
			FOREIGN KEY(filesystem_id) REFERENCES filesystem(id)
		);

		CREATE UNIQUE INDEX IF NOT EXISTS unique_file_name
		ON file(filesystem_id, name);

	]]

	db:exec [[

		CREATE TABLE IF NOT EXISTS asset_pack (
			id INTEGER PRIMARY KEY,
			filesystem_id INTEGER NOT NULL,
			container_name TEXT NULL,
			master_pack_id INTEGER NULL,
			FOREIGN KEY(filesystem_id) REFERENCES filesystem(id),
			FOREIGN KEY(master_pack_id) REFERENCES asset_pack(id)
		);

		CREATE UNIQUE INDEX IF NOT EXISTS unique_asset_pack_container
		ON asset_pack(master_pack_id, container_name);

	]]
end

function format.todb(intype, inpath, db)
	assert(intype == 'file', 'input must be a file (got ' .. intype .. ')')
	local reader = assert(R.fromfile(inpath))
	reader:inject('bindata')
	reader:inject(reader_proto)

	local assets = {}
	reader:assets(assets)

	format.dbinit(db)

	db:exec [[

		INSERT INTO filesystem DEFAULT VALUES;

	]]

	local filesystem_id = db:last_insert_rowid()

	db:exec [[

		INSERT INTO asset_pack (filesystem_id) VALUES (last_insert_rowid());

		UPDATE asset_pack SET master_pack_id = last_insert_rowid() WHERE rowid = last_insert_rowid();

	]]

	local master_pack_id = db:last_insert_rowid()

	local container_ids = {}

	local exec_add_container = db:prepare [[

		INSERT INTO asset_pack (master_pack_id, container_name)
		VALUES (?, ?)

	]]

	local exec_add_file = db:prepare [[

		INSERT INTO file (filesystem_id, name, contents)
		SELECT filesystem_id, ?, ? FROM asset_pack WHERE id = ?

	]]

	for i, asset in ipairs(assets) do
		local pack_id
		local content
		if asset.container == nil then
			pack_id = master_pack_id
			reader:pos('set', asset.offset)
			content = reader:blob(asset.length)
		else
			pack_id = container_ids[asset.container]
			if pack_id == nil then
				exec_add_container:bind_int64(1, master_pack_id)
				exec_add_container:bind_text(2, asset.container)
				assert(assert(exec_add_container:step()) == 'done')
				assert(exec_add_container:reset())
				pack_id = db:last_insert_rowid()
				container_ids[asset.container] = pack_id
			end
			local f = assert(io.open(inpath:gsub('[^\\/]*$', '') .. asset.container, 'rb'))
			f:seek('set', asset.offset)
			content = f:read(asset.length)
			f:close()
		end
		exec_add_file:bind_text(1, asset.name)
		exec_add_file:bind_blob(2, content)
		exec_add_file:bind_int64(3, pack_id)
		assert(assert(exec_add_file:step()) == 'done')
		assert(exec_add_file:reset())
	end

	exec_add_container:finalize()
	exec_add_file:finalize()

end

-------------------------------------------------------------------------------

function reader_proto:assets(list)
	assert(self:assets_begin(), 'unable to find start of data')
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
		return true
	end
	self:pos('end', -16)
	local start = self:int32le()
	if not self:expectBlob 'CLIB\1\2\3\4SIGE' then
		self:pos('set', base)
		return false
	end
	self:pos('set', start)
	if not self:expectBlob 'CLIB' then
		self:pos('set', base)
		return false
	end
	self:skip(1)
	return true
end

function reader_proto:assets_v6(assets)
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

-------------------------------------------------------------------------------

return format
