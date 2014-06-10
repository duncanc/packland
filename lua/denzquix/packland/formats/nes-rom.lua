
local R = require 'denzquix.packland.reader'

local format = {}

function format.dbinit(db)
	assert(db:exec [[

		CREATE TABLE IF NOT EXISTS nes_rom (
			dbid INTEGER PRIMARY KEY,
			title TEXT NULL
		);

		CREATE TABLE IF NOT EXISTS nes_chip (
			dbid INTEGER PRIMARY KEY,
			rom_dbid INTEGER NOT NULL,
			type TEXT NOT NULL,
			idx INTEGER,
			data BLOB NOT NULL,

			FOREIGN KEY (rom_dbid) REFERENCES nes_rom(dbid)
		);

	]])
end

function format.todb(intype, inpath, db)
	format.dbinit(db)
	local reader = assert(R.fromfile(inpath))

	function reader:rom(rom)
		self:inject('bindata')
		assert( self:expectBlob 'NES\26', 'invalid NES ROM header' )
		local prg_count = self:uint8()
		local chr_count = self:uint8()
		local flags_6 = self:uint8()
		local flags_7 = self:uint8()
		local prg_ram_size = self:uint8()
		if prg_ram_size == 0 then
			prg_ram_size = 8
		end
		prg_ram_size = prg_ram_size * 8
		local flags_9 = self:uint8()
		local flags_10 = self:uint8()
		self:skip(5 * 4)

		rom.chips = {}
		
		if 0 ~= bit.band(flags_6, 4) then
			rom.chips[#rom.chips+1] = {type='trainer', data=self:blob(512)}
		end

		for i = 1, prg_count do
			local idx = i-1
			rom.chips[#rom.chips+1] = {type='prg', idx=idx, data=self:blob(16384)}
		end

		for i = 1, chr_count do
			local idx = i-1
			rom.chips[#rom.chips+1] = {type='chr', idx=idx, data=self:blob(8192)}
		end

		rom.title = self:blob(128)
		if rom.title then
			rom.title = rom.title:match('^%Z+')
		end
	end

	local rom = {}
	reader:rom(rom)

	local rom_dbid

	do
		local exec_add_rom = assert(db:prepare [[

			INSERT INTO nes_rom (title)
			VALUES (:title)

		]])

		assert( exec_add_rom:bind_blob(':title', rom.title) )
		assert( assert( exec_add_rom:step() ) == 'done' )
		assert( exec_add_rom:finalize() )

		rom_dbid = db:last_insert_rowid()
	end

	do
		local exec_add_chip = assert(db:prepare [[

			INSERT INTO nes_chip (rom_dbid, type, idx, data)
			VALUES (:rom_dbid, :type, :idx, :data)

		]])

		assert( exec_add_chip:bind_int64(':rom_dbid', rom_dbid) )

		for _, chip in ipairs(rom.chips) do
			assert( exec_add_chip:bind_text(':type', chip.type) )
			if chip.idx == nil then
				assert( exec_add_chip:bind_null(':idx') )
			else
				assert( exec_add_chip:bind_int(':idx', chip.idx) )
			end
			assert( exec_add_chip:bind_blob(':data', chip.data) )
			assert( assert( exec_add_chip:step() ) == 'done' )
			assert( exec_add_chip:reset() )
		end

		assert( exec_add_chip:finalize() )
	end	

end

return format
