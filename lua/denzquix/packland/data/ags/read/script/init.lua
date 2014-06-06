
local ffi = require 'ffi'
local R = require 'denzquix.packland.reader'

local reader_proto = {}

local SCOM_VERSION = 89

function reader_proto:script(script)
	assert(self:expectBlob 'SCOM', 'unsupported script format')
	local formatVersion = self:int32le()
	assert(formatVersion <= SCOM_VERSION, 'unsupported script version')

	local data_size     = self:int32le()
	local code_size     = self:int32le()
	local strings_size  = self:int32le()

	local data    = self:blob(data_size)
	local code    = self:blob(code_size * 4) -- int array
	local strings = self:blob(strings_size)

	local fixups = {}
	for i = 1, self:int32le() do
		local fixup = {}
		self:script_fixup(fixup)
		fixups[i] = fixup
	end
	for _, fixup in ipairs(fixups) do
		fixup.offset = self:int32le()
	end

	local imports = {}
	for offset = 0, self:int32le()-1 do
		local import = self:nullTerminated()
		if import ~= '' then
			imports[#imports+1] = {name=import, offset=offset}
		end
	end

	local exports = {}
	for i = 1, self:int32le() do
		local export = {}
		self:script_export(export)
		exports[i] = export
	end

	local sections = {}
	if formatVersion >= 83 then
		for i = 1, self:int32le() do
			local section = {}
			section.name = self:nullTerminated()
			section.offset = self:int32le()
			sections[i] = section
		end
	end

	assert(self:int32le() == bit.tobit(0xbeefcafe), 'missing end-of-script marker')

	if sections[1] and sections[1].offset == 0 then
		script.name = sections[1].name
	end

	script.data_length = #data

	script.funcs = {}

	script.vars = {}
end

function reader_proto:script_export(export)
	local name = self:nullTerminated()
	local pre_arg, arg_count = name:match('^([^%$]+)%$(%d+)$')
	if pre_arg then
		export.name = pre_arg
		export.arg_count = tonumber(arg_count)
	else
		export.name = name
	end
	local address = self:int32le()
	local export_type = bit.rshift(address, 24)
	if export_type == 1 then
		export.type = 'function'
	elseif export_type == 2 then
		export.type = 'data'
	else
		export.type = tostring(export_type)
	end
	export.offset = bit.band(address, 0xffffff)
end

function reader_proto:script_fixup(fixup)
	fixup.type = self:uint8()
	if fixup.type == 1 then
		fixup.context = 'code'
		fixup.type = 'data'
	elseif fixup.type == 2 then
		fixup.context = 'code'
		fixup.type = 'code'
	elseif fixup.type == 3 then
		fixup.context = 'code'
		fixup.type = 'strings'
	elseif fixup.type == 4 then
		fixup.context = 'code'
		fixup.type = 'import'
	elseif fixup.type == 5 then
		fixup.context = 'data'
		fixup.type = 'data'
	elseif fixup.type == 6 then
		fixup.context = 'code'
		fixup.type = 'stack'
	else
		fixup.type = tostring(fixup.type)
	end
end

return reader_proto
