
local bit = require 'bit'
local R = require 'denzquix.packland.reader'
local format = {}

function format.dbinit(db)
	assert(db:exec [[

		CREATE TABLE IF NOT EXISTS parser_word (
			dbid INTEGER PRIMARY KEY,
			word TEXT,
			code INTEGER
		);

	]])
end

local reader_proto = {}

function format.todb(intype, inpath, db)
	format.dbinit(db)

	local reader = assert( R.fromfile(inpath) )

	reader:inject 'bindata'
	reader:inject(reader_proto)

	reader:pos('set', 26 * 2)

	local words = {}
	reader:words(words)

	local exec_add_word = assert(db:prepare [[
		INSERT INTO parser_word (word, code) VALUES (:word, :code)
	]])

	for _, word in ipairs(words) do
		assert( exec_add_word:bind_text(':word', word.word) )
		assert( exec_add_word:bind_int(':code', word.code) )
		assert( exec_add_word:step() )
		assert( exec_add_word:reset() )
	end

	assert( exec_add_word:finalize() )
end

function reader_proto:words(words)
	local last_word = ''
	while true do
		local last_word_len = self:uint8()
		if last_word_len == nil then
			return
		end
		local word = last_word:sub(1, last_word_len)
		while true do
			local c = self:uint8()
			if c == nil then
				return
			end
			word = word .. string.char(bit.bxor(0x7F, bit.band(c, 0x7F)))
			if c >= 0x80 then
				break
			end
		end
		local code = self:uint16be()
		words[#words+1] = {word=word, code=code}
		last_word = word
	end
end

return format
