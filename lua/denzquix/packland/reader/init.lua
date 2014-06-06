
local lib = {}

local reader_proto = {}
local reader_meta = {__index = reader_proto}

local namespacePrefixes = {std='denzquix.packland.reader.inject.', global=''}

function lib.registerNamespace(namespace, requirePrefix)
	namespacePrefixes[namespace] = requirePrefix
end

function reader_proto:expectBlob(blob)
	local got = self:blob(#blob)
	if got == blob then
		return true
	end
	if got ~= '' then
		self:pos('cur', -#got)
	end
	return false
end

function reader_proto:skip(count)
	return self:pos('cur', count)
end

local injected_cache = setmetatable({}, {__mode = 'k'})

function reader_proto:inject(injection)
	do
		local injected = injected_cache[self]
		if injected then
			if injected[injection] then
				return
			end
		else
			injected = {}
			injected_cache[self] = injected
		end
		injected[injection] = true
	end
	if type(injection) == 'string' then
		local namespace, name = injection:match('^([^:]+):(.-)$')
		if namespace == nil then
			namespace, name = 'std', injection
		end
		local prefix = namespacePrefixes[namespace]
		if prefix == nil then
			error('unknown namespace: ' .. namespace)
		end
		injection = require(prefix..name)
	end
	if injection.inject_ then
		injection.inject_(self)
	else
		for k,v in pairs(injection) do
			self[k] = v
		end
	end
	return self
end

function lib.type(v)
	if getmetatable(v) == reader_meta then
		return 'reader'
	end
	return nil
end

function lib.fromfile(f)
	if type(f) == 'string' then
		local err; f, err = assert(io.open(f, 'rb'))
		if not f then
			return nil, err
		end
	end

	local reader = setmetatable({}, reader_meta)

	function reader:blob(length)
		return f:read(length)
	end

	function reader:pos(...)
		return f:seek(...)
	end

	return reader
end

function lib.fromstring(str)
	local reader = setmetatable({}, reader_meta)

	local pos = 1

	function reader:blob(length)
		local chunk = str:sub(pos, pos+length-1)
		pos = pos + #chunk
		return chunk
	end

	function reader:pos(whence, offset)
		if offset == nil then
			if type(whence) == 'string' then
				offset = 0
			elseif type(whence) == 'number' then
				whence, offset = 'cur', whence
			else
				whence, offset = 'cur', 0
			end
		end
		if whence == 'set' then
			pos = 1 + offset
		elseif whence == 'cur' then
			pos = pos + offset
		elseif whence == 'end' then
			pos = #str + 1 + offset
		end
		return pos-1
	end

	return reader
end

return lib
