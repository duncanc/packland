
local bit = require 'bit'

-------------------------------------------------------------------------------

local reader_proto = {}

function reader_proto:uint8(count)
	local b = self:blob(count or 1) or ""
	return (b or ""):byte(1, -1)
end

function reader_proto:int8()
	local b = self:uint8()
	if b == nil then
		return nil
	end
	return bit.arshift(bit.lshift(b, 24), 24)
end

function reader_proto:uint16le()
	local b1, b2 = self:uint8(2)
	if not (b1 and b2) then
		return nil
	end
	return bit.bor(bit.lshift(b2, 8), b1)
end

function reader_proto:int16le()
	local v = self:uint16le()
	if v == nil then
		return nil
	end
	return bit.arshift(bit.lshift(v, 16), 16)
end

function reader_proto:int32le()
	local b1, b2, b3, b4 = self:uint8(4)
	return bit.bor(
		bit.lshift(b4, 24),
		bit.lshift(b3, 16),
		bit.lshift(b2, 8),
		b1)
end

function reader_proto:nullTerminated(length)
	if length then
		return self:blob(length):match('^%Z*')
	end
	local buf = {}
	while true do
		local c = self:blob(1)
		if c == '\0' or c == nil or c == '' then
			break
		end
	end
	return table.concat(buf)
end

-------------------------------------------------------------------------------

local injector = {}

function injector.inject_(reader)
	reader:inject(reader_proto)
end

return injector
