
local versioning = {}

local v_meta = {}

function versioning.schema(name)
	return setmetatable({name=name}, v_meta)
end

function v_meta:__call(value)
	return setmetatable({name=self.name, value=value}, v_meta)
end

local function assert_same(a, b)
	if a.name ~= b.name then
		error('incompatible version comparison (' .. self.name .. '/' .. other.name .. ')', 3)
	end
end

function v_meta:__eq(other)
	assert_same(self, other)
	return self.value == other.value
end

function v_meta:__lt(other)
	assert_same(self, other)
	return self.value < other.value
end

function v_meta:__le(other)
	assert_same(self, other)
	return self.value <= other.value
end

return versioning
